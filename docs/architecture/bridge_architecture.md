# Cross-Chain Liquidity Bridge
## Technical Architecture & Development Guide

**Version:** 1.0  
**Last Updated:** 2025-11-03  
**Team Size:** Multiple Developers  
**Tech Stack:** Solana (Rust/Anchor), Ethereum (Solidity), Wormhole

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture Layers](#2-architecture-layers)
3. [Component Responsibilities](#3-component-responsibilities)
4. [Development Workflow](#4-development-workflow)
5. [Module Ownership](#5-module-ownership)
6. [API Contracts](#6-api-contracts)
7. [Testing Strategy](#7-testing-strategy)
8. [Deployment Pipeline](#8-deployment-pipeline)

---

## 1. System Overview

### 1.1 What We're Building

A **liquidity-based cross-chain bridge** that allows users to swap stablecoins (USDC/USDT) between Ethereum and Solana with minimal slippage and no wrapped tokens.

```
User Flow:
1. User deposits 1000 USDC on Ethereum
2. Ethereum pool swaps to USD value → $1000
3. Wormhole sends message: "$1000 to Solana address XYZ"
4. Solana pool receives message, swaps $1000 → 998 USDC
5. User receives 998 USDC on Solana (2 USDC fee)
```

### 1.2 Core Innovation

- **No wrapped tokens** (no wUSDC, no synthetic assets)
- **Direct native swaps** using pooled liquidity
- **StableSwap math** for minimal slippage
- **Cross-chain messaging** via Wormhole

### 1.3 Key Constraints

| Constraint | Reason |
|------------|--------|
| **No floating-point math** | Prevents exploit vulnerabilities |
| **Fixed-point precision: 10^18** | Must match between chains |
| **StableSwap invariant D** | Must stay constant during swaps |
| **Message verification required** | Security against fake withdrawals |

---

## 2. Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     USER INTERFACE                          │
│              (Web App / SDK - Future)                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   BRIDGE GATEWAY LAYER                      │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │  EVM Gateway     │◄────────────►│  Solana Gateway  │    │
│  │  (Solidity)      │   Wormhole   │  (Rust/Anchor)   │    │
│  └──────────────────┘              └──────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                     AMM POOL LAYER                          │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │  EVM Pool        │              │  Solana Pool     │    │
│  │  (StableSwap)    │              │  (StableSwap)    │    │
│  └──────────────────┘              └──────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    MATH ENGINE LAYER                        │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │  Fixed-Point     │              │  Fixed-Point     │    │
│  │  StableSwap      │              │  StableSwap      │    │
│  │  (Solidity)      │              │  (Rust)          │    │
│  └──────────────────┘              └──────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Component Responsibilities

### 3.1 Solana Program Structure

```
solana-bridge/
├── programs/
│   ├── amm/                          # Core AMM (Owner: Dev A)
│   │   ├── src/
│   │   │   ├── lib.rs               # Program entry
│   │   │   ├── instructions/        # Instruction handlers
│   │   │   │   ├── mod.rs
│   │   │   │   ├── initialize.rs    # Setup pool
│   │   │   │   ├── add_liquidity.rs # LP deposits
│   │   │   │   ├── remove_liquidity.rs
│   │   │   │   └── swap.rs          # Local swaps
│   │   │   ├── state/               # Account structures
│   │   │   │   ├── mod.rs
│   │   │   │   ├── pool.rs          # Pool state
│   │   │   │   └── lp_token.rs      # LP tracking
│   │   │   ├── math/                # Math engine (Owner: Dev B)
│   │   │   │   ├── mod.rs
│   │   │   │   ├── constants.rs     # PRECISION, etc.
│   │   │   │   ├── fixed_point.rs   # Core arithmetic
│   │   │   │   └── stable_swap.rs   # get_D, get_Y
│   │   │   └── errors.rs            # Error codes
│   │   └── Cargo.toml
│   │
│   └── bridge/                       # Cross-chain (Owner: Dev B)
│       ├── src/
│       │   ├── lib.rs
│       │   ├── instructions/
│       │   │   ├── init_bridge.rs
│       │   │   ├── deposit.rs       # Lock & message
│       │   │   └── withdraw.rs      # Verify & release
│       │   ├── state/
│       │   │   ├── bridge_config.rs
│       │   │   └── transfer.rs      # Transfer tracking
│       │   └── verification/
│       │       └── wormhole.rs      # VAA verification
│       └── Cargo.toml
│
├── tests/                            # Integration tests
│   ├── amm.ts
│   ├── bridge.ts
│   └── cross_chain.ts
│
└── Anchor.toml
```

### 3.2 Ethereum Contract Structure

```
ethereum-bridge/
├── contracts/
│   ├── core/                         # Core contracts
│   │   ├── LiquidityPool.sol        # AMM pool (Owner: Dev A)
│   │   ├── BridgeGateway.sol        # Cross-chain (Owner: Dev B)
│   │   └── StableSwapMath.sol       # Math library (Owner: Dev B)
│   │
│   ├── interfaces/                   # Contract interfaces
│   │   ├── ILiquidityPool.sol
│   │   ├── IBridgeGateway.sol
│   │   ├── IWormhole.sol
│   │   └── IERC20.sol
│   │
│   ├── libraries/                    # Shared utilities
│   │   ├── FixedPointMath.sol
│   │   ├── SafeTransfer.sol
│   │   └── MessageCodec.sol         # Encode/decode
│   │
│   └── security/                     # Security modules
│       ├── ReentrancyGuard.sol
│       ├── AccessControl.sol
│       └── PauseModule.sol
│
├── test/
│   ├── LiquidityPool.test.ts
│   ├── StableSwap.test.ts
│   ├── Bridge.test.ts
│   └── CrossChain.integration.test.ts
│
├── scripts/
│   ├── deploy.ts
│   └── verify.ts
│
└── hardhat.config.ts
```

---

## 4. Development Workflow

### 4.1 Phase 1: Foundation (Week 1-3)

**Goal:** Build and test core math & local pools

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Fixed-point math (Rust) | Dev B | None | `math/` module |
| Fixed-point math (Solidity) | Dev B | None | `StableSwapMath.sol` |
| Cross-verify math | Dev B | Both above | Test report |
| Solana pool state | Dev A | Math module | `state/pool.rs` |
| EVM pool contract | Dev A | Math library | `LiquidityPool.sol` |
| Local swap instructions | Dev A | All above | Working AMM |

**Milestone:** Both chains can execute local swaps with identical outputs

### 4.2 Phase 2: Cross-Chain Messaging (Week 4-6)

**Goal:** Implement Wormhole integration

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Wormhole SDK setup | Dev B | None | Dependencies |
| Message encoding spec | Dev B | None | Spec document |
| Solana VAA verification | Dev B | Wormhole SDK | `verification/` |
| EVM message emission | Dev B | Wormhole SDK | `BridgeGateway.sol` |
| Deposit flow | Dev B | AMM + Messaging | End-to-end deposit |
| Withdrawal flow | Dev B | AMM + Messaging | End-to-end withdrawal |

**Milestone:** Can send test message from ETH → Solana (no value yet)

### 4.3 Phase 3: Economic Mechanisms (Week 7-8)

**Goal:** Implement fees, rebalancing, safety features

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Dynamic fees | Dev A | AMM | Fee calculation |
| Incentive pools | Dev A | AMM | IP tracking |
| Rebalancing logic | Dev A | Bridge | Solver interface |
| Circuit breakers | Dev C | Bridge | Pause mechanism |
| Oracle integration | Dev C | Bridge | Price verification |

**Milestone:** Full economic model operational

### 4.4 Phase 4: Testing & Audit (Week 9-10)

**Goal:** Comprehensive testing and security audit

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Unit test coverage | All | All modules | 90%+ coverage |
| Integration tests | All | All modules | Test suite |
| Fuzz testing | Dev A | Math modules | Security report |
| Gas optimization | Dev B | EVM contracts | Optimized code |
| Security audit prep | Dev B | All | Audit package |

---

## 5. Module Ownership

### 5.1 Developer A: AMM Specialist

**Responsibilities:**
- Liquidity pool state management
- Swap execution logic
- LP token accounting
- Fee collection and distribution
- Pool initialization

**Key Files:**
```
Solana: programs/amm/src/instructions/{initialize,swap,add_liquidity}.rs
EVM:    contracts/core/LiquidityPool.sol
```

**Interfaces to Implement:**
```rust
// Solana: instructions/swap.rs
pub fn handler(
    ctx: Context<Swap>,
    amount_in: u64,
    min_amount_out: u64,
) -> Result<()> {
    // Your implementation
}
```

```solidity
// EVM: LiquidityPool.sol
function swap(
    address tokenIn,
    uint256 amountIn,
    uint256 minAmountOut
) external returns (uint256 amountOut) {
    // Your implementation
}
```

### 5.2 Developer B: Math Engine Specialist

**Responsibilities:**
- Fixed-point arithmetic primitives
- StableSwap invariant calculation (get_D)
- Output calculation (get_Y)
- Numerical convergence testing
- Cross-chain math verification

**Key Files:**
```
Solana: programs/amm/src/math/{fixed_point,stable_swap}.rs
EVM:    contracts/core/StableSwapMath.sol, libraries/FixedPointMath.sol
```

**Critical Contract:**
```rust
// Must implement these EXACTLY the same on both chains
pub fn get_d(reserve_a: u64, reserve_b: u64, amp: u64) -> Result<u128>;
pub fn get_y(invariant_d: u128, new_reserve_x: u64, amp: u64) -> Result<u128>;
```

**Verification Requirement:**
- Every test case MUST produce identical output on Solana and EVM
- Maintain a shared test fixture file: `test-vectors.json`

### 5.3 Developer C: Bridge & Security Specialist

**Responsibilities:**
- Wormhole VAA verification
- Message encoding/decoding
- Cross-chain deposit flow
- Cross-chain withdrawal flow
- Access control
- Circuit breakers

**Key Files:**
```
Solana: programs/bridge/src/{instructions,verification}/
EVM:    contracts/core/BridgeGateway.sol, security/
```

**Message Format Spec:**
```typescript
interface CrossChainMessage {
    version: u8;              // Protocol version
    transferId: bytes32;      // Unique transfer ID
    sender: bytes;            // Source chain sender (20 or 32 bytes)
    recipient: bytes;         // Destination chain recipient
    amountUSD: u64;           // Normalized USD value (6 decimals)
    nonce: u64;               // Replay protection
    sourceChain: u16;         // Wormhole chain ID
    timestamp: u64;           // Unix timestamp
}
```

---

## 6. API Contracts

### 6.1 Internal Module APIs

#### Math Module → AMM Module

```rust
// Solana
use crate::math::StableSwap;

pub struct SwapCalculation {
    pub amount_out: u64,
    pub fee: u64,
    pub new_invariant_d: u128,
}

impl AmmInstructions {
    fn calculate_swap(&self, amount_in: u64) -> Result<SwapCalculation> {
        let amount_out = StableSwap::calculate_swap_amount(
            amount_in,
            self.pool.reserve_a,
            self.pool.reserve_b,
            self.pool.invariant_d,
            self.pool.amplification,
        )?;
        
        Ok(SwapCalculation { amount_out, fee: 0, new_invariant_d: 0 })
    }
}
```

#### AMM Module → Bridge Module

```rust
// Solana
pub struct DepositResult {
    pub usd_value: u64,
    pub fee_taken: u64,
    pub pool_updated: bool,
}

impl BridgeInstructions {
    pub fn process_deposit(
        &mut self,
        token_in: Pubkey,
        amount_in: u64,
    ) -> Result<DepositResult> {
        // Call AMM swap
        // Get USD value
        // Return for message encoding
    }
}
```

### 6.2 Cross-Chain Consistency Contract

Both chains MUST implement these with **identical behavior**:

```typescript
// Shared Interface (Pseudo-code)
interface IStableSwapMath {
    // Calculate invariant D
    // MUST return same value given same inputs
    function calculateD(
        reserveA: u64,
        reserveB: u64,
        amplification: u64
    ): u128;
    
    // Calculate output amount Y
    // MUST return same value given same inputs
    function calculateY(
        invariantD: u128,
        newReserveX: u64,
        amplification: u64
    ): u128;
}
```

**Testing Contract:**
Create `test-vectors.json`:
```json
{
  "version": "1.0",
  "precision": "1000000000000000000",
  "test_cases": [
    {
      "name": "balanced_pool_100k",
      "reserveA": "100000000000",
      "reserveB": "100000000000",
      "amplification": "100",
      "expectedD": "200000000000000000000000",
      "tolerance": "0.001"
    },
    {
      "name": "10k_swap_balanced",
      "reserveA": "100000000000",
      "reserveB": "100000000000",
      "amplification": "100",
      "amountIn": "10000000000",
      "expectedOut": "9997523100",
      "tolerance": "0.001"
    }
  ]
}
```

**Both teams must pass these tests:**
```bash
# Solana
cargo test --features test-vectors

# Ethereum
npx hardhat test --grep "test-vectors"
```

---

## 7. Testing Strategy

### 7.1 Testing Pyramid

```
                    ┌─────────────┐
                    │  E2E Tests  │  ← 5% (Slow, Full Bridge)
                    └─────────────┘
                  ┌───────────────────┐
                  │ Integration Tests │  ← 25% (Multi-module)
                  └───────────────────┘
              ┌─────────────────────────────┐
              │      Unit Tests             │  ← 70% (Fast, Isolated)
              └─────────────────────────────┘
```

### 7.2 Test Responsibilities

| Test Type | Owner | Frequency | Location |
|-----------|-------|-----------|----------|
| Math unit tests | Dev B | Every commit | `math/*.rs`, `StableSwap.test.ts` |
| AMM unit tests | Dev A | Every commit | `instructions/*.rs`, `LiquidityPool.test.ts` |
| Bridge unit tests | Dev A,B | Every commit | `verification/*.rs`, `BridgeGateway.test.ts` |
| Cross-chain math | Dev B | Daily | `tests/cross_verify.ts` |
| Integration tests | All | Before PR | `tests/*.ts` |
| E2E tests | Dev B | Before release | `tests/e2e/` |

### 7.3 Required Test Coverage

**Minimum Coverage Targets:**
- Math modules: **100%** (security-critical)
- AMM instructions: **95%**
- Bridge instructions: **90%**
- Overall: **90%**

**Test Commands:**
```bash
# Solana
anchor test
cargo tarpaulin --out Html  # Coverage report

# Ethereum
npx hardhat test
npx hardhat coverage
```

### 7.4 Critical Test Cases (Everyone Must Test)

```typescript
// test-cases.md

1. Math Verification
   - [ ] D calculation matches between chains (±0.001%)
   - [ ] Y calculation matches between chains (±0.001%)
   - [ ] Invariant maintained after swap (±0.001%)
   - [ ] No overflow with max values
   - [ ] Convergence within 255 iterations

2. AMM Operations
   - [ ] Initialize pool with balanced liquidity
   - [ ] Swap with minimal slippage (<1% for stable pairs)
   - [ ] Extreme imbalance protection (cannot drain pool)
   - [ ] Fee collection works correctly
   - [ ] LP token accounting accurate

3. Bridge Operations
   - [ ] Deposit locks tokens and emits message
   - [ ] Withdrawal verifies VAA correctly
   - [ ] Replay attack prevention
   - [ ] Invalid message rejection
   - [ ] Circuit breaker works

4. Security
   - [ ] Reentrancy protection (EVM)
   - [ ] Access control enforced
   - [ ] Slippage limits enforced
   - [ ] Pause mechanism works
   - [ ] No floating-point math (compile-time check)
```

---

## 8. Deployment Pipeline

### 8.1 Environment Strategy

```
Development  →  Testnet  →  Mainnet Beta  →  Mainnet
(Local)         (Public)    (Limited)        (Full)
```

### 8.2 Deployment Checklist

**Pre-Deployment:**
- [ ] All tests passing (100% for math, 90%+ overall)
- [ ] Cross-chain math verified
- [ ] Security audit completed
- [ ] Gas optimization done (EVM)
- [ ] Compute optimization done (Solana)
- [ ] Documentation complete
- [ ] Monitoring setup ready

**Deployment Order:**
1. Deploy EVM math library (immutable)
2. Deploy Solana math program (upgradeable initially)
3. Cross-verify math on testnets
4. Deploy EVM pool contract
5. Deploy Solana pool program
6. Initialize both pools with test liquidity
7. Test local swaps on both chains
8. Deploy bridge contracts
9. Test cross-chain flow with small amounts
10. Gradually increase limits

### 8.3 Deployment Scripts

```typescript
// scripts/deploy-sequence.ts

async function deployAll() {
    console.log("🚀 Starting deployment sequence...\n");
    
    // Step 1: Math libraries
    console.log("1️⃣ Deploying math libraries...");
    const mathLib = await deployMathLibrary();
    await verifyMathLibrary(mathLib);
    
    // Step 2: AMM contracts
    console.log("2️⃣ Deploying AMM pools...");
    const pools = await deployPools(mathLib);
    await verifyPools(pools);
    
    // Step 3: Bridge contracts
    console.log("3️⃣ Deploying bridge contracts...");
    const bridge = await deployBridge(pools);
    await verifyBridge(bridge);
    
    // Step 4: Initialize
    console.log("4️⃣ Initializing system...");
    await initializeSystem(pools, bridge);
    
    // Step 5: Verify
    console.log("5️⃣ Running verification tests...");
    await runVerificationTests();
    
    console.log("✅ Deployment complete!");
}
```

---

## 9. Communication Protocols

### 9.1 Daily Standups (Async in Discord/Slack)

Template:
```
Developer: [Name]
Date: [YYYY-MM-DD]

✅ Completed yesterday:
- [Task 1]
- [Task 2]

🚧 Working on today:
- [Task 1]
- [Task 2]

🚫 Blockers:
- [Blocker 1] - needs [Dev X]

📊 Test Status:
- Unit tests: [passing/failing]
- Integration: [passing/failing]
```

### 9.2 Code Review Process

**Before Creating PR:**
1. All tests passing locally
2. Code formatted (`cargo fmt`, `prettier`)
3. No compiler warnings
4. Documentation updated

**PR Template:**
```markdown
## Summary
[Brief description]

## Type
- [ ] Feature
- [ ] Bug fix
- [ ] Refactor
- [ ] Tests

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Math verified (if applicable)
- [ ] Gas/compute optimized

## Testing
[Describe testing done]

## Dependencies
[List any dependent PRs]
```

**Review Assignment:**
- Math changes: Must be reviewed by Dev B + 1 other
- Bridge changes: Must be reviewed by Dev C + 1 other
- AMM changes: Must be reviewed by Dev A + 1 other

### 9.3 Issue Tracking

**Issue Labels:**
- `module: math` - Math engine issues
- `module: amm` - AMM pool issues
- `module: bridge` - Bridge issues
- `priority: critical` - Blocks development
- `priority: high` - Should fix soon
- `priority: low` - Nice to have
- `type: bug` - Something broken
- `type: feature` - New functionality
- `type: test` - Test-related

---

## 10. Knowledge Base

### 10.1 Key Concepts Everyone Should Know

**StableSwap Invariant:**
```
For 2 tokens: A * 4 * (x + y) + D = 4 * A * D + D³ / (4 * x * y)

Where:
- A = amplification (10-1000, higher = lower slippage)
- x, y = token reserves
- D = invariant (constant during swaps)
```

**Fixed-Point Math:**
```
PRECISION = 10^18

Real value 2.5:
Fixed-point: 2_500_000_000_000_000_000

Multiply: (a * b) / PRECISION
Divide: (a * PRECISION) / b
```

**Wormhole Chain IDs:**
```
Ethereum: 2
Solana: 1
BSC: 4
Polygon: 5
```

### 10.2 Common Pitfalls

❌ **DON'T:**
```rust
// Never use floating point
let result = 1.5 * amount; // WRONG!

// Never use unchecked math
let sum = a + b; // WRONG! Could overflow

// Never assume message validity
process_withdrawal(msg); // WRONG! Verify first
```

✅ **DO:**
```rust
// Use fixed-point
let result = FixedPoint::mul(1_500_000_000_000_000_000, amount, PRECISION)?;

// Use checked math
let sum = a.checked_add(b).ok_or(MathError::Overflow)?;

// Verify messages
verify_vaa(msg)?;
process_withdrawal(msg)?;
```

### 10.3 Debugging Tips

**Math Not Matching Between Chains:**
```bash
# 1. Add extensive logging
msg!("D calculation: reserves={},{} amp={}", a, b, amp);
console.log("D calculation:", {a, b, amp});

# 2. Compare step-by-step
- Print d at each Newton-Raphson iteration
- Compare iteration counts
- Check PRECISION constant

# 3. Test with simple values
reserveA = 1_000_000
reserveB = 1_000_000
amp = 100
# Expected D ≈ 2_000_000 * PRECISION
```

**Transaction Failing:**
```bash
# Solana
solana logs -u devnet  # Watch real-time logs
anchor test --skip-build  # Skip rebuild

# Ethereum
npx hardhat node  # Local node with detailed logs
npx hardhat test --network localhost --trace
```

---

## 11. Resources & References

### 11.1 Documentation

- **Solana:** https://docs.solana.com
- **Anchor:** https://www.anchor-lang.com
- **Wormhole:** https://docs.wormhole.com
- **StableSwap:** Curve whitepaper (see references in research doc)

### 11.2 Code References

- **Orca Whirlpools:** https://github.com/orca-so/whirlpools
- **Curve StableSwap:** https://github.com/curvefi/curve-contract
- **Wormhole Examples:** https://github.com/wormhole-foundation/wormhole-examples

### 11.3 Team Communication

- **GitHub:** [Your repo URL]
- **Discord/Slack:** [Your channel]
- **Notion/Wiki:** [Your wiki URL]
- **Design Docs:** [Your docs folder]

---

## 12. Glossary

| Term | Definition |
|------|------------|
| **AMM** | Automated Market Maker - algorithm that prices assets |
| **CLB** | Cross-chain Liquidity Bridge |
| **D** | StableSwap invariant - measure of total liquidity |
| **LP** | Liquidity Provider - user who deposits tokens |
| **PDA** | Program Derived Address - Solana account owned by program |
| **VAA** | Verified Action Approval - Wormhole signed message |
| **XCMP** | Cross-Chain Messaging Protocol |
| **Slippage** | Price difference between expected and actual |
| **Invariant** | Value that must remain constant (D during swaps) |
| **Fixed-point** | Integer representation of decimals |

---

## Appendix A: Quick Start Commands

```bash
# Solana Development
cd solana-bridge
anchor build
anchor test
anchor deploy --provider.cluster devnet

# Ethereum Development
cd ethereum-bridge
npm install
npx hardhat compile
npx hardhat test
npx hardhat deploy --network goerli

# Cross-Chain Verification
npm run verify-math  # Compare outputs between chains
```

---

**Last Updated:** 2025-10-30  
**Next Review:** When adding new modules or before mainnet deployment

For questions or clarifications, contact the respective module owner or post in the team channel.