'use client'

import { useState, useSyncExternalStore } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseEther, keccak256, encodePacked } from 'viem'
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts'
import { HASH_GIFT_ABI, HASH_GIFT_ADDRESS } from '@/lib/contract'

interface ShareData {
  packetId: string
  privateKey: string
  contractAddress: string
}

export function CreatePacket() {
  const { address, isConnected } = useAccount()
  const [amount, setAmount] = useState('')
  const [count, setCount] = useState('1')
  const [duration, setDuration] = useState('86400') // 1天
  const [isRandom, setIsRandom] = useState(false)
  const [shareData, setShareData] = useState<ShareData | null>(null)

  // 使用 useSyncExternalStore 确保 hydration 安全，避免 SSR/CSR 不匹配
  const mounted = useSyncExternalStore(
    () => () => {},        // subscribe: no-op
    () => true,            // getSnapshot: client returns true
    () => false            // getServerSnapshot: server returns false
  )

  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const handleCreate = async () => {
    if (!address || !amount) return

    // 生成一次性密钥对（防抢跑核心）
    const privateKey = generatePrivateKey()
    const signer = privateKeyToAccount(privateKey)
    
    // 生成唯一红包ID
    const packetId = keccak256(encodePacked(
      ['address', 'uint256', 'uint256'],
      [address, BigInt(Date.now()), BigInt(Math.random() * 1e18)]
    ))

    writeContract({
      address: HASH_GIFT_ADDRESS,
      abi: HASH_GIFT_ABI,
      functionName: 'createPacket',
      args: [packetId, signer.address, BigInt(count), BigInt(duration), isRandom],
      value: parseEther(amount),
    }, {
      onSuccess: () => {
        setShareData({
          packetId,
          privateKey,
          contractAddress: HASH_GIFT_ADDRESS,
        })
      }
    })
  }

  const shareUrl = shareData 
    ? `${typeof window !== 'undefined' ? window.location.origin : ''}/claim?p=${shareData.packetId}&k=${shareData.privateKey.slice(2)}`
    : ''

  // 避免 hydration 不匹配：在客户端挂载之前显示加载状态
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

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold bg-gradient-to-r from-red-400 to-orange-400 bg-clip-text text-transparent">
        🧧 创建红包
      </h2>

      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-2">金额 (ETH)</label>
          <input
            type="number"
            step="0.001"
            min="0.0001"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl focus:border-purple-500 focus:outline-none"
            placeholder="0.1"
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-2">份数</label>
          <input
            type="number"
            min="1"
            max="1000"
            value={count}
            onChange={(e) => setCount(e.target.value)}
            className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl focus:border-purple-500 focus:outline-none"
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-2">有效期</label>
          <select
            value={duration}
            onChange={(e) => setDuration(e.target.value)}
            className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl focus:border-purple-500 focus:outline-none"
          >
            <option value="3600">1 小时</option>
            <option value="86400">1 天</option>
            <option value="604800">7 天</option>
            <option value="2592000">30 天</option>
          </select>
        </div>

        <label className="flex items-center gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={isRandom}
            onChange={(e) => setIsRandom(e.target.checked)}
            className="w-5 h-5 rounded bg-gray-800 border-gray-700"
          />
          <span className="text-gray-300">拼手气红包</span>
        </label>

        <button
          onClick={handleCreate}
          disabled={isPending || isConfirming || !amount}
          className="w-full py-4 bg-gradient-to-r from-red-500 to-orange-500 rounded-xl font-bold text-lg hover:opacity-90 transition-opacity disabled:opacity-50"
        >
          {isPending ? '确认交易...' : isConfirming ? '上链中...' : '发红包'}
        </button>

        {error && (
          <div className="p-4 bg-red-500/20 border border-red-500/50 rounded-xl text-red-400 text-sm">
            {error.message}
          </div>
        )}

        {isSuccess && shareData && (
          <div className="p-4 bg-green-500/20 border border-green-500/50 rounded-xl space-y-3">
            <p className="text-green-400 font-semibold">✅ 红包创建成功！</p>
            <div>
              <p className="text-sm text-gray-400 mb-1">分享链接：</p>
              <div className="flex gap-2">
                <input
                  readOnly
                  value={shareUrl}
                  className="flex-1 px-3 py-2 bg-gray-800 rounded-lg text-sm font-mono"
                />
                <button
                  onClick={() => navigator.clipboard.writeText(shareUrl)}
                  className="px-4 py-2 bg-purple-500 rounded-lg hover:bg-purple-600 transition-colors"
                >
                  复制
                </button>
              </div>
            </div>
            <p className="text-xs text-gray-500">
              ⚠️ 此链接包含私钥，请通过安全渠道发送给接收者
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
