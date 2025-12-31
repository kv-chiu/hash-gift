// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title HashGift - 去中心化口令红包
 * @notice 支持防抢跑的 ECDSA 签名验证机制
 * @dev 使用一次性密钥对防止 MEV 抢跑攻击
 */
contract HashGift is ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct RedPacket {
        address creator;         // 红包创建者
        uint256 totalAmount;     // 总金额
        uint256 remainingAmount; // 剩余金额
        uint256 totalCount;      // 总份数
        uint256 claimedCount;    // 已领取份数
        address signer;          // 签名验证地址（公钥派生）
        uint256 expireTime;      // 过期时间戳
        bool isRandom;           // 是否随机金额
        bool isActive;           // 是否激活
    }

    // 红包ID => 红包信息
    mapping(bytes32 => RedPacket) public packets;
    // 红包ID => 用户地址 => 是否已领取
    mapping(bytes32 => mapping(address => bool)) public hasClaimed;
    // 红包ID => 领取记录
    mapping(bytes32 => address[]) public claimRecords;

    // 最小红包金额 (防止粉尘攻击)
    uint256 public constant MIN_AMOUNT = 0.0001 ether;
    // 最大份数限制
    uint256 public constant MAX_COUNT = 1000;
    // 最大有效期 (30天)
    uint256 public constant MAX_DURATION = 30 days;

    // 事件
    event PacketCreated(
        bytes32 indexed packetId,
        address indexed creator,
        uint256 amount,
        uint256 count,
        uint256 expireTime
    );
    
    event PacketClaimed(
        bytes32 indexed packetId,
        address indexed claimer,
        uint256 amount
    );
    
    event PacketRefunded(
        bytes32 indexed packetId,
        address indexed creator,
        uint256 amount
    );

    error InvalidAmount();
    error InvalidCount();
    error InvalidDuration();
    error PacketExists();
    error PacketNotFound();
    error PacketExpired();
    error PacketNotExpired();
    error PacketEmpty();
    error AlreadyClaimed();
    error InvalidSignature();
    error NotCreator();
    error TransferFailed();

    /**
     * @notice 创建红包
     * @param packetId 红包唯一ID（前端生成的随机bytes32）
     * @param signer 签名验证地址（由一次性私钥派生）
     * @param count 红包份数
     * @param duration 有效期（秒）
     * @param isRandom 是否随机金额
     */
    function createPacket(
        bytes32 packetId,
        address signer,
        uint256 count,
        uint256 duration,
        bool isRandom
    ) external payable {
        if (msg.value < MIN_AMOUNT) revert InvalidAmount();
        if (count == 0 || count > MAX_COUNT) revert InvalidCount();
        if (duration == 0 || duration > MAX_DURATION) revert InvalidDuration();
        if (packets[packetId].isActive) revert PacketExists();
        if (msg.value / count < MIN_AMOUNT) revert InvalidAmount();

        packets[packetId] = RedPacket({
            creator: msg.sender,
            totalAmount: msg.value,
            remainingAmount: msg.value,
            totalCount: count,
            claimedCount: 0,
            signer: signer,
            expireTime: block.timestamp + duration,
            isRandom: isRandom,
            isActive: true
        });

        emit PacketCreated(packetId, msg.sender, msg.value, count, block.timestamp + duration);
    }

    /**
     * @notice 领取红包（防抢跑：签名必须包含领取者地址）
     * @param packetId 红包ID
     * @param signature 由一次性私钥对 (packetId, msg.sender) 的签名
     */
    function claimPacket(
        bytes32 packetId,
        bytes calldata signature
    ) external nonReentrant {
        RedPacket storage packet = packets[packetId];
        
        if (!packet.isActive) revert PacketNotFound();
        if (block.timestamp >= packet.expireTime) revert PacketExpired();
        if (packet.remainingAmount == 0) revert PacketEmpty();
        if (hasClaimed[packetId][msg.sender]) revert AlreadyClaimed();

        // 核心防抢跑逻辑：验证签名包含 msg.sender
        bytes32 messageHash = keccak256(abi.encodePacked(packetId, msg.sender));
        bytes32 ethSignedHash = messageHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedHash.recover(signature);
        
        if (recoveredSigner != packet.signer) revert InvalidSignature();

        hasClaimed[packetId][msg.sender] = true;
        claimRecords[packetId].push(msg.sender);

        // 计算领取金额（必须在 claimedCount++ 之前）
        uint256 claimAmount = _calculateClaimAmount(packet);
        
        packet.claimedCount++;
        packet.remainingAmount -= claimAmount;

        // 转账
        (bool success, ) = payable(msg.sender).call{value: claimAmount}("");
        if (!success) revert TransferFailed();

        emit PacketClaimed(packetId, msg.sender, claimAmount);
    }

    /**
     * @notice 退款（红包过期后创建者可取回剩余金额）
     * @param packetId 红包ID
     */
    function refund(bytes32 packetId) external nonReentrant {
        RedPacket storage packet = packets[packetId];
        
        if (!packet.isActive) revert PacketNotFound();
        if (packet.creator != msg.sender) revert NotCreator();
        if (block.timestamp < packet.expireTime) revert PacketNotExpired();
        if (packet.remainingAmount == 0) revert PacketEmpty();

        uint256 refundAmount = packet.remainingAmount;
        packet.remainingAmount = 0;
        packet.isActive = false;

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) revert TransferFailed();

        emit PacketRefunded(packetId, msg.sender, refundAmount);
    }

    /**
     * @notice 获取红包信息
     */
    function getPacket(bytes32 packetId) external view returns (RedPacket memory) {
        return packets[packetId];
    }

    /**
     * @notice 获取红包领取记录
     */
    function getClaimRecords(bytes32 packetId) external view returns (address[] memory) {
        return claimRecords[packetId];
    }

    /**
     * @notice 检查用户是否已领取
     */
    function hasUserClaimed(bytes32 packetId, address user) external view returns (bool) {
        return hasClaimed[packetId][user];
    }

    /**
     * @dev 计算领取金额（随机或平均）
     */
    function _calculateClaimAmount(RedPacket storage packet) internal view returns (uint256) {
        uint256 remainingCount = packet.totalCount - packet.claimedCount;
        
        if (remainingCount == 1) {
            return packet.remainingAmount;
        }

        if (packet.isRandom) {
            // 随机金额：使用链上伪随机（生产环境应使用 Chainlink VRF）
            uint256 maxAmount = (packet.remainingAmount * 2) / remainingCount;
            uint256 minAmount = MIN_AMOUNT;
            
            if (maxAmount <= minAmount) {
                return packet.remainingAmount / remainingCount;
            }

            uint256 randomValue = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                packet.claimedCount
            )));
            
            return minAmount + (randomValue % (maxAmount - minAmount));
        } else {
            // 平均金额
            return packet.remainingAmount / remainingCount;
        }
    }
}
