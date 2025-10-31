#!/bin/bash

echo "🧪 Running all tests..."

# Test Solana
echo "Testing Solana programs..."
cd solana-bridge
anchor test
SOLANA_EXIT=$?
cd ..

# Test Ethereum
echo "Testing Ethereum contracts..."
cd ethereum-bridge
npm test
ETH_EXIT=$?
cd ..

# Report results
echo ""
if [ $SOLANA_EXIT -eq 0 ] && [ $ETH_EXIT -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
