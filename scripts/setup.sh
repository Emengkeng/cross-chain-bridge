#!/bin/bash

echo "🚀 Setting up Cross-Chain Bridge Development Environment"

# Check prerequisites
echo "Checking prerequisites..."
command -v node >/dev/null 2>&1 || { echo "❌ Node.js not installed"; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "❌ Rust not installed"; exit 1; }
command -v solana >/dev/null 2>&1 || { echo "❌ Solana CLI not installed"; exit 1; }
command -v anchor >/dev/null 2>&1 || { echo "❌ Anchor not installed"; exit 1; }

echo "✅ All prerequisites installed"

# Setup Solana
echo "📦 Setting up Solana workspace..."
cd solana-bridge
anchor build
cd ..

# Setup Ethereum
echo "⟠ Setting up Ethereum workspace..."
cd ethereum-bridge
npm install
npx hardhat compile
cd ..

echo "✅ Workspace setup complete!"
echo ""
echo "Next steps:"
echo "1. Open workspace: code cross-chain-bridge.code-workspace"
echo "2. Install recommended VS Code extensions"
echo "3. Start building!"
