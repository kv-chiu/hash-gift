'use client'

import { useState, useEffect } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract } from 'wagmi'
import { keccak256, encodePacked, formatEther, type Hex } from 'viem'
import { signMessage } from 'viem/accounts'
import { HASH_GIFT_ABI, HASH_GIFT_ADDRESS } from '@/lib/contract'

interface ClaimPacketProps {
  packetId?: string
  privateKey?: string
}

export function ClaimPacket({ packetId: initialPacketId, privateKey: initialPrivateKey }: ClaimPacketProps) {
  const { address, isConnected } = useAccount()
  const [packetId, setPacketId] = useState(initialPacketId || '')
  const [privateKey, setPrivateKey] = useState(initialPrivateKey || '')
  const [claimedAmount, setClaimedAmount] = useState<string | null>(null)
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  // 读取红包信息
  const { data: packet, refetch } = useReadContract({
    address: HASH_GIFT_ADDRESS,
    abi: HASH_GIFT_ABI,
    functionName: 'getPacket',
    args: packetId ? [packetId as Hex] : undefined,
    query: { enabled: !!packetId }
  })

  // 检查是否已领取
  const { data: hasClaimed } = useReadContract({
    address: HASH_GIFT_ADDRESS,
    abi: HASH_GIFT_ABI,
    functionName: 'hasUserClaimed',
    args: packetId && address ? [packetId as Hex, address] : undefined,
    query: { enabled: !!packetId && !!address }
  })

  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  // 从 URL 解析参数
  useEffect(() => {
    if (typeof window !== 'undefined') {
      const params = new URLSearchParams(window.location.search)
      const p = params.get('p')
      const k = params.get('k')
      if (p) setPacketId(p)
      if (k) setPrivateKey(`0x${k}`)
    }
  }, [])

  // 保存领取前的预期金额
  const [expectedAmount, setExpectedAmount] = useState<bigint | null>(null)

  const handleClaim = async () => {
    if (!address || !packetId || !privateKey || !packet) return

    // 领取前计算预期金额
    const remaining = packet.remainingAmount
    const remainingCount = packet.totalCount - packet.claimedCount
    const expected = remainingCount > 0n ? remaining / remainingCount : remaining
    setExpectedAmount(expected)

    try {
      // 生成防抢跑签名：签名内容包含领取者地址
      const messageHash = keccak256(encodePacked(
        ['bytes32', 'address'],
        [packetId as Hex, address]
      ))

      const signature = await signMessage({
        privateKey: privateKey as Hex,
        message: { raw: messageHash }
      })

      writeContract({
        address: HASH_GIFT_ADDRESS,
        abi: HASH_GIFT_ABI,
        functionName: 'claimPacket',
        args: [packetId as Hex, signature],
      })
    } catch (err) {
      console.error('签名失败:', err)
      setExpectedAmount(null)
    }
  }

  useEffect(() => {
    if (isSuccess && expectedAmount !== null) {
      // 使用领取前保存的预期金额
      setClaimedAmount(formatEther(expectedAmount))
      refetch()
    }
  }, [isSuccess, expectedAmount, refetch])

  if (!mounted) {
    return (
      <div className="text-center text-gray-400 py-8">
        加载中...
      </div>
    )
  }

  if (!isConnected) {
    return (
      <div className="text-center text-gray-400 py-8">
        请先连接钱包
      </div>
    )
  }

  const isExpired = packet && Number(packet.expireTime) * 1000 < Date.now()
  const isEmpty = packet && packet.remainingAmount === 0n

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold bg-gradient-to-r from-yellow-400 to-red-400 bg-clip-text text-transparent">
        🎁 领取红包
      </h2>

      {!initialPacketId && (
        <div className="space-y-4">
          <div>
            <label className="block text-sm text-gray-400 mb-2">红包 ID</label>
            <input
              value={packetId}
              onChange={(e) => setPacketId(e.target.value)}
              className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl focus:border-purple-500 focus:outline-none font-mono text-sm"
              placeholder="0x..."
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-2">私钥</label>
            <input
              type="password"
              value={privateKey}
              onChange={(e) => setPrivateKey(e.target.value)}
              className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl focus:border-purple-500 focus:outline-none font-mono text-sm"
              placeholder="0x..."
            />
          </div>
        </div>
      )}

      {packet && packet.isActive && (
        <div className="p-4 bg-gray-800/50 rounded-xl space-y-2">
          <div className="flex justify-between">
            <span className="text-gray-400">总金额</span>
            <span className="font-semibold">{formatEther(packet.totalAmount)} ETH</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">剩余 / 总数</span>
            <span>{Number(packet.totalCount - packet.claimedCount)} / {Number(packet.totalCount)}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">类型</span>
            <span>{packet.isRandom ? '🎲 拼手气' : '💰 平均分'}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">状态</span>
            <span className={isExpired ? 'text-red-400' : isEmpty ? 'text-orange-400' : 'text-green-400'}>
              {isExpired ? '已过期' : isEmpty ? '已抢完' : '可领取'}
            </span>
          </div>
        </div>
      )}

      {hasClaimed && (
        <div className="p-4 bg-yellow-500/20 border border-yellow-500/50 rounded-xl text-yellow-400">
          ⚠️ 你已经领取过这个红包了
        </div>
      )}

      <button
        onClick={handleClaim}
        disabled={isPending || isConfirming || !packetId || !privateKey || hasClaimed || isExpired || isEmpty}
        className="w-full py-4 bg-gradient-to-r from-yellow-500 to-red-500 rounded-xl font-bold text-lg hover:opacity-90 transition-opacity disabled:opacity-50"
      >
        {isPending ? '确认交易...' : isConfirming ? '领取中...' : '开红包'}
      </button>

      {error && (
        <div className="p-4 bg-red-500/20 border border-red-500/50 rounded-xl text-red-400 text-sm">
          {error.message}
        </div>
      )}

      {isSuccess && claimedAmount && (
        <div className="p-6 bg-gradient-to-r from-red-500/20 to-orange-500/20 border border-orange-500/50 rounded-xl text-center">
          <p className="text-4xl mb-2">🎉</p>
          <p className="text-2xl font-bold text-orange-400">恭喜获得</p>
          <p className="text-3xl font-bold mt-2">{claimedAmount} ETH</p>
        </div>
      )}
    </div>
  )
}
