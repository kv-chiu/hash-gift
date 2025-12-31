// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/HashGift.sol";

/**
 * @title E2E Integration Test
 * @notice 模拟完整的红包创建和领取流程
 */
contract E2ETest is Test {
    HashGift public hashGift;
    
    // 测试用户
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    // 一次性密钥
    uint256 public signerPrivateKey;
    address public signer;
    
    function setUp() public {
        hashGift = new HashGift();
        
        // 生成签名密钥
        signerPrivateKey = 0x12345;
        signer = vm.addr(signerPrivateKey);
        
        // 给用户分配 ETH
        vm.deal(alice, 10 ether);
        vm.deal(bob, 1 ether);
        vm.deal(charlie, 1 ether);
    }

    /**
     * @notice 完整 E2E 流程：创建 -> 多人领取 -> 退款
     */
    function test_E2E_FullFlow() public {
        bytes32 packetId = keccak256("e2e-test-packet");
        
        // === Step 1: Alice 创建红包 ===
        vm.prank(alice);
        hashGift.createPacket{value: 1 ether}(
            packetId,
            signer,
            3,        // 3 份
            1 days,   // 1 天有效期
            false     // 平均分配
        );
        
        // 验证创建成功
        HashGift.RedPacket memory packet = hashGift.getPacket(packetId);
        assertEq(packet.totalAmount, 1 ether);
        assertEq(packet.totalCount, 3);
        assertTrue(packet.isActive);
        
        console.log("Step 1: Alice created packet with 1 ETH for 3 people");
        
        // === Step 2: Bob 领取红包 ===
        bytes memory bobSig = _signClaim(packetId, bob);
        
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        hashGift.claimPacket(packetId, bobSig);
        uint256 bobClaimed = bob.balance - bobBalanceBefore;
        
        console.log("Step 2: Bob claimed", bobClaimed / 1e15, "finney");
        assertGt(bobClaimed, 0);
        assertTrue(hashGift.hasUserClaimed(packetId, bob));
        
        // === Step 3: Charlie 领取红包 ===
        bytes memory charlieSig = _signClaim(packetId, charlie);
        
        uint256 charlieBalanceBefore = charlie.balance;
        vm.prank(charlie);
        hashGift.claimPacket(packetId, charlieSig);
        uint256 charlieClaimed = charlie.balance - charlieBalanceBefore;
        
        console.log("Step 3: Charlie claimed", charlieClaimed / 1e15, "finney");
        assertGt(charlieClaimed, 0);
        
        // === Step 4: 时间快进，Alice 退款剩余 ===
        vm.warp(block.timestamp + 2 days);
        
        packet = hashGift.getPacket(packetId);
        uint256 remaining = packet.remainingAmount;
        
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        hashGift.refund(packetId);
        uint256 aliceRefunded = alice.balance - aliceBalanceBefore;
        
        console.log("Step 4: Alice refunded", aliceRefunded / 1e15, "finney");
        assertEq(aliceRefunded, remaining);
        
        // === 最终验证：资金守恒 ===
        assertEq(bobClaimed + charlieClaimed + aliceRefunded, 1 ether);
        console.log("E2E Test PASSED: Total distributed equals total deposited");
    }

    /**
     * @notice 防抢跑测试
     */
    function test_E2E_AntiFrontRunning() public {
        bytes32 packetId = keccak256("anti-mev-test");
        
        vm.prank(alice);
        hashGift.createPacket{value: 0.5 ether}(
            packetId, signer, 1, 1 days, false
        );
        
        // Bob 获得有效签名
        bytes memory bobSig = _signClaim(packetId, bob);
        
        // Charlie 尝试使用 Bob 的签名抢跑 (MEV攻击模拟)
        vm.prank(charlie);
        vm.expectRevert(HashGift.InvalidSignature.selector);
        hashGift.claimPacket(packetId, bobSig);
        
        // Bob 正常领取成功
        vm.prank(bob);
        hashGift.claimPacket(packetId, bobSig);
        
        console.log("Anti-MEV test PASSED: Frontrunning prevented");
    }

    /**
     * @notice 拼手气红包测试
     */
    function test_E2E_RandomPacket() public {
        bytes32 packetId = keccak256("random-test");
        
        vm.prank(alice);
        hashGift.createPacket{value: 1 ether}(
            packetId, signer, 10, 1 days, true // isRandom = true
        );
        
        uint256 totalClaimed = 0;
        
        for (uint i = 1; i <= 10; i++) {
            address claimer = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            vm.deal(claimer, 0.01 ether);
            
            bytes memory sig = _signClaim(packetId, claimer);
            
            uint256 balanceBefore = claimer.balance;
            vm.prank(claimer);
            hashGift.claimPacket(packetId, sig);
            uint256 claimed = claimer.balance - balanceBefore;
            
            totalClaimed += claimed;
            console.log("User claimed:", claimed / 1e15, "finney");
        }
        
        // 所有人领完后应该刚好是 1 ETH
        assertEq(totalClaimed, 1 ether);
        console.log("Random packet test PASSED");
    }

    function _signClaim(bytes32 _packetId, address _claimer) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(_packetId, _claimer));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }
}
