export const HASH_GIFT_ABI = [
  {
    "type": "function",
    "name": "createPacket",
    "inputs": [
      { "name": "packetId", "type": "bytes32" },
      { "name": "signer", "type": "address" },
      { "name": "count", "type": "uint256" },
      { "name": "duration", "type": "uint256" },
      { "name": "isRandom", "type": "bool" }
    ],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "claimPacket",
    "inputs": [
      { "name": "packetId", "type": "bytes32" },
      { "name": "signature", "type": "bytes" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "refund",
    "inputs": [{ "name": "packetId", "type": "bytes32" }],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getPacket",
    "inputs": [{ "name": "packetId", "type": "bytes32" }],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "components": [
          { "name": "creator", "type": "address" },
          { "name": "totalAmount", "type": "uint256" },
          { "name": "remainingAmount", "type": "uint256" },
          { "name": "totalCount", "type": "uint256" },
          { "name": "claimedCount", "type": "uint256" },
          { "name": "signer", "type": "address" },
          { "name": "expireTime", "type": "uint256" },
          { "name": "isRandom", "type": "bool" },
          { "name": "isActive", "type": "bool" }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "hasUserClaimed",
    "inputs": [
      { "name": "packetId", "type": "bytes32" },
      { "name": "user", "type": "address" }
    ],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "PacketCreated",
    "inputs": [
      { "name": "packetId", "type": "bytes32", "indexed": true },
      { "name": "creator", "type": "address", "indexed": true },
      { "name": "amount", "type": "uint256", "indexed": false },
      { "name": "count", "type": "uint256", "indexed": false },
      { "name": "expireTime", "type": "uint256", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "PacketClaimed",
    "inputs": [
      { "name": "packetId", "type": "bytes32", "indexed": true },
      { "name": "claimer", "type": "address", "indexed": true },
      { "name": "amount", "type": "uint256", "indexed": false }
    ]
  }
] as const

// Mantle Sepolia Testnet 合约地址
export const HASH_GIFT_ADDRESS = '0x235F4F52f8283eBE9B63ADB052d2b8B15C0331B4' as const
