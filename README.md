# Cross-Chain Liquidity Bridge
## This project is still under development/research
A liquidity-based cross-chain bridge connecting Ethereum and Solana with minimal slippage using StableSwap AMM. Read about the Architecture Plan [Here](docs/LiquidityPoolBridgeArchitecturePlan.pdf) 

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- Rust 1.70+
- Solana CLI 1.17+
- Anchor 0.29+

### Setup
```bash
# Clone the repository
git clone https://github.com/Emengkeng/cross-chain-bridge
cd cross-chain-bridge

# Run setup script
./scripts/setup.sh

# Open workspace in VS Code
code cross-chain-bridge.code-workspace
```
## 📁 Project Structure
```
cross-chain-bridge/
├── solana-bridge/          # Solana programs (Rust/Anchor)
│   ├── programs/
│   │   └── bridge/        # Cross-chain gateway
│   └── tests/             # Integration tests
├── ethereum-bridge/        # Ethereum contracts (Solidity)
│   ├── contracts/
│   │   ├── core/          # Main contracts
│   │   ├── libraries/     # Shared libraries
│   │   └── security/      # Security modules
│   └── test/              # Unit & integration tests
├── docs/                   # Documentation
└── scripts/                # Utility scripts
```

## 🛠️ Development Commands

### Solana
```bash
cd solana-bridge

# Build programs
anchor build

# Run tests
anchor test

# Deploy to devnet
anchor deploy --provider.cluster devnet
```

### Ethereum
```bash
cd ethereum-bridge

# Compile contracts
npm run compile

# Run tests
npm test

# Deploy to local network
npm run deploy:local

# Deploy to testnet
npm run deploy:goerli
```

### Run All Tests
```bash
./scripts/test-all.sh
```

## 📚 Documentation

- [Architecture Overview](docs/architecture/overview.md)
- [Getting Started Guide](docs/guides/getting-started.md)
- [API Documentation](docs/api/)

## 👥 Team

- Dev A: AMM Specialist
- Dev B: Math Engine
- Dev B: Bridge & Security

## 📄 License

MIT