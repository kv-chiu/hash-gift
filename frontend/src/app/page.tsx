'use client'

import { useState } from 'react'
import { WalletConnect } from '@/components/WalletConnect'
import { CreatePacket } from '@/components/CreatePacket'
import { ClaimPacket } from '@/components/ClaimPacket'

export default function Home() {
  const [tab, setTab] = useState<'create' | 'claim'>('create')

  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-950 via-gray-900 to-gray-950">
      {/* Header */}
      <header className="border-b border-gray-800">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-red-400 via-orange-400 to-yellow-400 bg-clip-text text-transparent">
            🧧 Hash Gift
          </h1>
          <WalletConnect />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-md mx-auto px-4 py-8">
        {/* Tabs */}
        <div className="flex gap-2 mb-8">
          <button
            onClick={() => setTab('create')}
            className={`flex-1 py-3 rounded-xl font-semibold transition-all ${
              tab === 'create'
                ? 'bg-gradient-to-r from-red-500 to-orange-500'
                : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
            }`}
          >
            发红包
          </button>
          <button
            onClick={() => setTab('claim')}
            className={`flex-1 py-3 rounded-xl font-semibold transition-all ${
              tab === 'claim'
                ? 'bg-gradient-to-r from-yellow-500 to-red-500'
                : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
            }`}
          >
            领红包
          </button>
        </div>

        {/* Content */}
        <div className="bg-gray-900/50 backdrop-blur-sm border border-gray-800 rounded-2xl p-6">
          {tab === 'create' ? <CreatePacket /> : <ClaimPacket />}
        </div>

        {/* Info */}
        <div className="mt-8 p-4 bg-gray-800/50 rounded-xl text-sm text-gray-400 space-y-2">
          <p>🔐 <strong>防抢跑机制：</strong>采用 ECDSA 签名验证，签名绑定领取者地址</p>
          <p>⛓️ <strong>链上透明：</strong>所有交易记录公开可查</p>
          <p>🔒 <strong>安全保障：</strong>资金由智能合约托管，无法被篡改</p>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-800 mt-16">
        <div className="max-w-4xl mx-auto px-4 py-6 text-center text-gray-500 text-sm">
          Hash Gift - Web3 去中心化红包 Demo
        </div>
      </footer>
    </div>
  )
}
