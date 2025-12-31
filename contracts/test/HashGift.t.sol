// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/HashGift.sol";

contract HashGiftTest is Test {
    HashGift public hashGift;
    
    address public creator = address(0x1);
    address public claimer1 = address(0x2);
    address public claimer2 = address(0x3);
    address public attacker = address(0x4);
    
    // 一次性签名密钥
    uint256 public signerPrivateKey = 0xA11CE;
    address public signer;
    
    bytes32 public packetId;
    
    function setUp() public {
        hashGift = new HashGift();
        signer = vm.addr(signerPrivateKey);
        packetId = keccak256("test-packet-1");
        
        // 给测试账户一些 ETH
        vm.deal(creator, 100 ether);
        vm.deal(claimer1, 1 ether);
        vm.deal(claimer2, 1 ether);
        vm.deal(attacker, 1 ether);
    }

    // ============ 创建红包测试 ============

    function test_CreatePacket_Success() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(
            packetId,
            signer,
            10,      // 10 份
            1 days,  // 1 天有效期
            false    // 平均分配
        );
        
        HashGift.RedPacket memory packet = hashGift.getPacket(packetId);
        
        assertEq(packet.creator, creator);
        assertEq(packet.totalAmount, 1 ether);
        assertEq(packet.remainingAmount, 1 ether);
        assertEq(packet.totalCount, 10);
        assertEq(packet.claimedCount, 0);
        assertEq(packet.signer, signer);
        assertTrue(packet.isActive);
    }

    function test_CreatePacket_RevertOnZeroAmount() public {
        vm.prank(creator);
        vm.expectRevert(HashGift.InvalidAmount.selector);
        hashGift.createPacket{value: 0}(packetId, signer, 10, 1 days, false);
    }

    function test_CreatePacket_RevertOnZeroCount() public {
        vm.prank(creator);
        vm.expectRevert(HashGift.InvalidCount.selector);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 0, 1 days, false);
    }

    function test_CreatePacket_RevertOnTooManyCount() public {
        vm.prank(creator);
        vm.expectRevert(HashGift.InvalidCount.selector);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 1001, 1 days, false);
    }

    function test_CreatePacket_RevertOnDuplicateId() public {
        vm.startPrank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        vm.expectRevert(HashGift.PacketExists.selector);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        vm.stopPrank();
    }

    // ============ 领取红包测试 ============

    function test_ClaimPacket_Success() public {
        // 创建红包
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        // 生成有效签名
        bytes memory signature = _signClaim(packetId, claimer1);
        
        uint256 balanceBefore = claimer1.balance;
        
        vm.prank(claimer1);
        hashGift.claimPacket(packetId, signature);
        
        uint256 balanceAfter = claimer1.balance;
        
        // 平均分配：1 ether / 10 = 0.1 ether
        assertEq(balanceAfter - balanceBefore, 0.1 ether);
        assertTrue(hashGift.hasUserClaimed(packetId, claimer1));
    }

    function test_ClaimPacket_AntiMEV_RevertOnWrongSigner() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        // 攻击者看到交易后尝试用自己地址领取
        // 但签名是针对 claimer1 的，所以会失败
        bytes memory signatureForClaimer1 = _signClaim(packetId, claimer1);
        
        vm.prank(attacker);
        vm.expectRevert(HashGift.InvalidSignature.selector);
        hashGift.claimPacket(packetId, signatureForClaimer1);
    }

    function test_ClaimPacket_RevertOnDoubleClaim() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        bytes memory signature = _signClaim(packetId, claimer1);
        
        vm.startPrank(claimer1);
        hashGift.claimPacket(packetId, signature);
        
        vm.expectRevert(HashGift.AlreadyClaimed.selector);
        hashGift.claimPacket(packetId, signature);
        vm.stopPrank();
    }

    function test_ClaimPacket_RevertOnExpired() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        // 时间快进 2 天
        vm.warp(block.timestamp + 2 days);
        
        bytes memory signature = _signClaim(packetId, claimer1);
        
        vm.prank(claimer1);
        vm.expectRevert(HashGift.PacketExpired.selector);
        hashGift.claimPacket(packetId, signature);
    }

    function test_ClaimPacket_MultipleClaimers() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 2, 1 days, false);
        
        // Claimer1 领取
        bytes memory sig1 = _signClaim(packetId, claimer1);
        vm.prank(claimer1);
        hashGift.claimPacket(packetId, sig1);
        
        // Claimer2 领取
        bytes memory sig2 = _signClaim(packetId, claimer2);
        vm.prank(claimer2);
        hashGift.claimPacket(packetId, sig2);
        
        // 验证红包已空
        HashGift.RedPacket memory packet = hashGift.getPacket(packetId);
        assertEq(packet.remainingAmount, 0);
        assertEq(packet.claimedCount, 2);
    }

    // ============ 退款测试 ============

    function test_Refund_Success() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        // Claimer1 领取一份
        bytes memory signature = _signClaim(packetId, claimer1);
        vm.prank(claimer1);
        hashGift.claimPacket(packetId, signature);
        
        // 时间快进过期
        vm.warp(block.timestamp + 2 days);
        
        uint256 balanceBefore = creator.balance;
        
        vm.prank(creator);
        hashGift.refund(packetId);
        
        uint256 balanceAfter = creator.balance;
        
        // 退回剩余 0.9 ether
        assertEq(balanceAfter - balanceBefore, 0.9 ether);
    }

    function test_Refund_RevertOnNotExpired() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        vm.prank(creator);
        vm.expectRevert(HashGift.PacketNotExpired.selector);
        hashGift.refund(packetId);
    }

    function test_Refund_RevertOnNotCreator() public {
        vm.prank(creator);
        hashGift.createPacket{value: 1 ether}(packetId, signer, 10, 1 days, false);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(attacker);
        vm.expectRevert(HashGift.NotCreator.selector);
        hashGift.refund(packetId);
    }

    // ============ Fuzz 测试 ============

    function testFuzz_CreatePacket(uint256 amount, uint256 count) public {
        // 限制输入范围
        amount = bound(amount, 0.001 ether, 10 ether);
        count = bound(count, 1, 100);
        
        // 确保每份至少 MIN_AMOUNT
        vm.assume(amount / count >= hashGift.MIN_AMOUNT());
        
        bytes32 fuzzPacketId = keccak256(abi.encodePacked(amount, count));
        
        vm.prank(creator);
        hashGift.createPacket{value: amount}(fuzzPacketId, signer, count, 1 days, false);
        
        HashGift.RedPacket memory packet = hashGift.getPacket(fuzzPacketId);
        assertEq(packet.totalAmount, amount);
        assertEq(packet.totalCount, count);
    }

    function testFuzz_ClaimPacket(uint256 amount, uint256 claimerSeed) public {
        amount = bound(amount, 0.01 ether, 5 ether);
        
        // 使用 makeAddr 生成安全的 EOA 地址
        string memory label = string(abi.encodePacked("fuzzClaimer", vm.toString(claimerSeed)));
        address fuzzClaimer = makeAddr(label);
        vm.deal(fuzzClaimer, 1 ether);
        
        bytes32 fuzzPacketId = keccak256(abi.encodePacked(amount, claimerSeed, block.timestamp));
        
        vm.prank(creator);
        hashGift.createPacket{value: amount}(fuzzPacketId, signer, 1, 1 days, false);
        
        bytes memory signature = _signClaim(fuzzPacketId, fuzzClaimer);
        
        uint256 balanceBefore = fuzzClaimer.balance;
        
        vm.prank(fuzzClaimer);
        hashGift.claimPacket(fuzzPacketId, signature);
        
        uint256 balanceAfter = fuzzClaimer.balance;
        assertEq(balanceAfter - balanceBefore, amount);
    }

    // ============ 辅助函数 ============

    function _signClaim(bytes32 _packetId, address _claimer) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(_packetId, _claimer));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }
}
