import { http, createConfig } from 'wagmi'
import { mainnet, sepolia, localhost } from 'wagmi/chains'

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
  chains: [anvil, sepolia, mainnet],
  transports: {
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
