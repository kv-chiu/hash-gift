'use client'

import { Suspense } from 'react'
import { ClaimPacket } from '@/components/ClaimPacket'
import { WalletConnect } from '@/components/WalletConnect'
import Link from 'next/link'

function ClaimContent() {
  return <ClaimPacket />
}

export default function ClaimPage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-950 via-gray-900 to-gray-950">
      {/* Header */}
      <header className="border-b border-gray-800">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <Link href="/" className="text-2xl font-bold bg-gradient-to-r from-red-400 via-orange-400 to-yellow-400 bg-clip-text text-transparent">
            🧧 Hash Gift
          </Link>
          <WalletConnect />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-md mx-auto px-4 py-8">
        <div className="bg-gray-900/50 backdrop-blur-sm border border-gray-800 rounded-2xl p-6">
          <Suspense fallback={<div className="text-center py-8 text-gray-400">加载中...</div>}>
            <ClaimContent />
          </Suspense>
        </div>

        <div className="mt-6 text-center">
          <Link href="/" className="text-purple-400 hover:text-purple-300 transition-colors">
            ← 返回首页
          </Link>
        </div>
      </main>
    </div>
  )
}
