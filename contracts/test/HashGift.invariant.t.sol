// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../src/HashGift.sol";

/**
 * @title HashGift 不变量测试
 * @notice 验证合约在任意操作序列下保持核心不变量
 */
contract HashGiftInvariantTest is StdInvariant, Test {
    HashGift public hashGift;
    HashGiftHandler public handler;

    function setUp() public {
        hashGift = new HashGift();
        handler = new HashGiftHandler(hashGift);
        
        // 设置 handler 为目标合约
        targetContract(address(handler));
        
        // 排除合约本身
        excludeSender(address(hashGift));
    }

    /**
     * @notice 不变量1：合约余额 >= 所有活跃红包剩余金额之和
     */
    function invariant_ContractBalanceCoversPackets() public view {
        uint256 totalRemaining = handler.getTotalRemainingAmount();
        assertGe(
            address(hashGift).balance,
            totalRemaining,
            "Contract balance should cover all remaining amounts"
        );
    }

    /**
     * @notice 不变量2：已领取份数不超过总份数
     */
    function invariant_ClaimedCountNeverExceedsTotalCount() public view {
        bytes32[] memory packetIds = handler.getPacketIds();
        for (uint256 i = 0; i < packetIds.length; i++) {
            HashGift.RedPacket memory packet = hashGift.getPacket(packetIds[i]);
            assertLe(
                packet.claimedCount,
                packet.totalCount,
                "Claimed count should never exceed total count"
            );
        }
    }

    /**
     * @notice 不变量3：剩余金额不超过总金额
     */
    function invariant_RemainingNeverExceedsTotal() public view {
        bytes32[] memory packetIds = handler.getPacketIds();
        for (uint256 i = 0; i < packetIds.length; i++) {
            HashGift.RedPacket memory packet = hashGift.getPacket(packetIds[i]);
            assertLe(
                packet.remainingAmount,
                packet.totalAmount,
                "Remaining amount should never exceed total amount"
            );
        }
    }

    /**
     * @notice 不变量4：用户只能领取一次
     */
    function invariant_NoDoubleClaim() public view {
        // 通过 handler 记录的领取次数验证
        assertTrue(
            handler.noDoubleClaims(),
            "No user should be able to claim twice"
        );
    }
}

/**
 * @title Handler 合约 - 用于模糊调用 HashGift
 */
contract HashGiftHandler is Test {
    HashGift public hashGift;
    
    bytes32[] public packetIds;
    mapping(bytes32 => bool) public packetExists;
    mapping(bytes32 => mapping(address => uint256)) public claimCounts;
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer;
    
    address[] public actors;

    constructor(HashGift _hashGift) {
        hashGift = _hashGift;
        signer = vm.addr(signerPrivateKey);
        
        // 创建测试用户
        for (uint i = 1; i <= 10; i++) {
            address actor = address(uint160(i * 1000));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    function createPacket(
        uint256 actorSeed,
        uint256 amount,
        uint256 count,
        uint256 duration
    ) external {
        // 约束参数
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 0.001 ether, 10 ether);
        count = bound(count, 1, 50);
        duration = bound(duration, 1 hours, 7 days);
        
        // 确保每份至少 MIN_AMOUNT
        if (amount / count < hashGift.MIN_AMOUNT()) {
            amount = hashGift.MIN_AMOUNT() * count;
        }
        
        bytes32 packetId = keccak256(abi.encodePacked(block.timestamp, actor, packetIds.length));
        
        if (!packetExists[packetId]) {
            vm.prank(actor);
            hashGift.createPacket{value: amount}(packetId, signer, count, duration, false);
            
            packetIds.push(packetId);
            packetExists[packetId] = true;
        }
    }

    function claimPacket(uint256 actorSeed, uint256 packetIndex) external {
        if (packetIds.length == 0) return;
        
        address claimer = actors[actorSeed % actors.length];
        bytes32 packetId = packetIds[packetIndex % packetIds.length];
        
        HashGift.RedPacket memory packet = hashGift.getPacket(packetId);
        
        // 跳过无效情况
        if (!packet.isActive) return;
        if (packet.remainingAmount == 0) return;
        if (block.timestamp >= packet.expireTime) return;
        if (hashGift.hasUserClaimed(packetId, claimer)) return;
        
        // 生成签名并领取
        bytes memory signature = _signClaim(packetId, claimer);
        
        vm.prank(claimer);
        try hashGift.claimPacket(packetId, signature) {
            claimCounts[packetId][claimer]++;
        } catch {}
    }

    function warpTime(uint256 delta) external {
        delta = bound(delta, 0, 3 days);
        vm.warp(block.timestamp + delta);
    }

    function refund(uint256 actorSeed, uint256 packetIndex) external {
        if (packetIds.length == 0) return;
        
        bytes32 packetId = packetIds[packetIndex % packetIds.length];
        HashGift.RedPacket memory packet = hashGift.getPacket(packetId);
        
        if (!packet.isActive) return;
        if (block.timestamp < packet.expireTime) return;
        if (packet.remainingAmount == 0) return;
        
        vm.prank(packet.creator);
        try hashGift.refund(packetId) {} catch {}
    }

    // ============ 视图函数 ============

    function getTotalRemainingAmount() external view returns (uint256 total) {
        for (uint256 i = 0; i < packetIds.length; i++) {
            HashGift.RedPacket memory packet = hashGift.getPacket(packetIds[i]);
            if (packet.isActive) {
                total += packet.remainingAmount;
            }
        }
    }

    function getPacketIds() external view returns (bytes32[] memory) {
        return packetIds;
    }

    function noDoubleClaims() external view returns (bool) {
        for (uint256 i = 0; i < packetIds.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                if (claimCounts[packetIds[i]][actors[j]] > 1) {
                    return false;
                }
            }
        }
        return true;
    }

    function _signClaim(bytes32 _packetId, address _claimer) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(_packetId, _claimer));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }
}
