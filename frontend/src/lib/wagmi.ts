import { http, createConfig } from 'wagmi'
import { mainnet, sepolia, localhost, type Chain } from 'wagmi/chains'

// Mantle Sepolia 测试网配置
const mantleSepolia = {
  id: 5003,
  name: 'Mantle Sepolia Testnet',
  nativeCurrency: { name: 'MNT', symbol: 'MNT', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://rpc.sepolia.mantle.xyz'] },
  },
  blockExplorers: {
    default: { name: 'Mantle Sepolia Explorer', url: 'https://sepolia.mantlescan.xyz' },
  },
  testnet: true,
} as const satisfies Chain

// 本地测试网配置
const anvil = {
  ...localhost,
  id: 31337,
  name: 'Anvil',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['http://127.0.0.1:8545'] },
  },
} as const

export const config = createConfig({
  chains: [mantleSepolia, anvil, sepolia, mainnet],
  transports: {
    [mantleSepolia.id]: http(),
    [anvil.id]: http(),
    [sepolia.id]: http(),
    [mainnet.id]: http(),
  },
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}
