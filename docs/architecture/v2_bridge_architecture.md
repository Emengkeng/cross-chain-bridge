# Cross-Chain Liquidity Bridge
## Integration Architecture & Development Guide

**Version:** 2.0 (Integration Approach)  
**Last Updated:** 2025-11-05  
**Team Size:** 2-3 Developers  
**Tech Stack:** Solana (Rust/Anchor), Ethereum (Solidity), Wormhole, Curve Finance, Orca Whirlpools

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture Layers](#2-architecture-layers)
3. [External Protocol Integration](#3-external-protocol-integration)
4. [Component Responsibilities](#4-component-responsibilities)
5. [Development Workflow](#5-development-workflow)
6. [Module Ownership](#6-module-ownership)
7. [API Contracts](#7-api-contracts)
8. [Testing Strategy](#8-testing-strategy)
9. [Deployment Pipeline](#9-deployment-pipeline)

---

## 1. System Overview

### 1.1 What We're Building

A **liquidity-based cross-chain bridge** that allows users to swap stablecoins (USDC/USDT) between Ethereum and Solana by integrating with battle-tested AMMs instead of building custom swap logic.

```
User Flow:
1. User deposits 1000 USDC on Ethereum
2. Bridge locks tokens → calls Curve to swap → gets USD value
3. Wormhole sends message: "$1000 to Solana address XYZ"
4. Solana bridge receives message → calls Orca to swap → releases USDC
5. User receives ~998 USDC on Solana (2 USDC bridge fee + AMM fees)
```

### 1.2 Core Innovation

- **No wrapped tokens** (no wUSDC, no synthetic assets)
- **Leverage proven AMM protocols** (Curve on Ethereum, Orca on Solana)
- **Focus on bridge security** rather than swap mechanics
- **Cross-chain messaging** via Wormhole

### 1.3 Key Architecture Decision

**BUILD vs INTEGRATE Decision Matrix:**

| Aspect | Custom AMM | Integrated AMM | Decision |
|--------|------------|----------------|----------|
| **Development Time** | 10+ weeks | 3-4 weeks | ✅ Integrate |
| **Security Risk** | High (needs audit) | Low (already audited) | ✅ Integrate |
| **Math Complexity** | Must implement StableSwap | Use existing | ✅ Integrate |
| **Liquidity** | Start from zero | Use existing pools | ✅ Integrate |
| **Testnet Support** | Must deploy own | Already deployed | ✅ Integrate |
| **Control** | Full | Limited | ⚠️ Trade-off |
| **Fee Customization** | Full | Work within their model | ⚠️ Trade-off |

**Conclusion:** Integrate with existing AMMs for MVP, evaluate custom AMM later if needed.

### 1.4 Selected Protocols

**Ethereum Side: Curve Finance**
- Battle-tested StableSwap implementation
- Deep USDC/USDT liquidity
- Extensive security audits
- Goerli/Sepolia testnet support
- Gas-optimized

**Solana Side: Orca Whirlpools**
- Leading Solana DEX
- Concentrated liquidity pools
- Excellent SDK and documentation
- Active devnet pools
- Compute-optimized

---

## 2. Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     USER INTERFACE                          │
│              (Web App / SDK - Future)                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   BRIDGE LAYER (Our Code)                   │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │  EVM Bridge      │◄────────────►│  Solana Bridge   │    │
│  │  - Lock/Unlock   │   Wormhole   │  - Lock/Unlock   │    │
│  │  - Messaging     │              │  - Verification  │    │
│  │  - Accounting    │              │  - Accounting    │    │
│  └────────┬─────────┘              └─────────┬────────┘    │
└───────────┼──────────────────────────────────┼─────────────┘
            ↓                                    ↓
┌─────────────────────────────────────────────────────────────┐
│              EXTERNAL AMM LAYER (Not Our Code)              │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │  Curve Finance   │              │  Orca Whirlpools │    │
│  │  - StableSwap    │              │  - Concentrated  │    │
│  │  - USDC/USDT     │              │  - USDC/USDT     │    │
│  └──────────────────┘              └──────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**What We Build:** Bridge layer only (purple box)
**What We Use:** AMM layer (blue box)
**What We Don't Build:** Swap math, liquidity pools, LP tokens

---

## 3. External Protocol Integration

### 3.1 Curve Finance Integration (Ethereum)

**Protocol Details:**
- **Contract:** StableSwap pool (immutable, audited)
- **Pool Address (Goerli):** `0x...` (Research Task #1)
- **Supported Pairs:** USDC/USDT
- **Fee:** ~0.04% (4 basis points)

**Integration Interface:**
```solidity
interface ICurvePool {
    // Get exchange output amount (view function)
    function get_dy(
        int128 i,      // Input token index (0=USDC, 1=USDT)
        int128 j,      // Output token index
        uint256 dx     // Input amount
    ) external view returns (uint256);
    
    // Execute exchange
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy  // Slippage protection
    ) external returns (uint256);
}
```

**Our Integration Pattern:**
```solidity
contract EthereumBridge {
    ICurvePool public immutable curvePool;
    
    function deposit(
        address tokenIn,
        uint256 amountIn,
        uint256 minUsdOut
    ) external {
        // 1. Lock user's tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // 2. Approve Curve
        IERC20(tokenIn).approve(address(curvePool), amountIn);
        
        // 3. Swap to normalized token (e.g., USDC)
        int128 i = tokenIn == USDC ? 0 : 1;
        uint256 usdValue = curvePool.exchange(i, 0, amountIn, minUsdOut);
        
        // 4. Emit Wormhole message
        emitTransferMessage(recipient, usdValue);
    }
}
```

### 3.2 Orca Whirlpools Integration (Solana)

**Protocol Details:**
- **Program ID:** `whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc`
- **Pool Address (Devnet):** TBD (Research Task #2)
- **Supported Pairs:** USDC/USDT
- **Fee:** ~0.05-0.30% (configurable)

**Integration Interface:**
```rust
// Using Orca SDK
use whirlpool::{
    self,
    state::Whirlpool,
};

pub struct OrcaIntegration {
    whirlpool: Pubkey,
}

impl OrcaIntegration {
    pub fn swap(
        &self,
        ctx: Context<Swap>,
        amount_in: u64,
        minimum_amount_out: u64,
    ) -> Result<u64> {
        // Call Orca's swap instruction
        whirlpool::cpi::swap(
            CpiContext::new(
                ctx.accounts.whirlpool_program.to_account_info(),
                whirlpool::cpi::accounts::Swap {
                    whirlpool: ctx.accounts.whirlpool.to_account_info(),
                    token_authority: ctx.accounts.token_authority.to_account_info(),
                    // ... other accounts
                },
            ),
            amount_in,
            minimum_amount_out,
            // ... other params
        )
    }
}
```

**Our Integration Pattern:**
```rust
pub fn process_withdrawal(
    ctx: Context<Withdrawal>,
    transfer_message: TransferMessage,
) -> Result<()> {
    // 1. Verify Wormhole VAA
    verify_vaa(&ctx.accounts.vaa)?;
    
    // 2. Check transfer hasn't been processed
    require!(!ctx.accounts.transfer_state.processed, ErrorCode::AlreadyProcessed);
    
    // 3. Swap via Orca (USD value → USDC)
    let amount_out = orca_integration::swap(
        &ctx.accounts,
        transfer_message.amount_usd,
        calculate_min_output(transfer_message.amount_usd),
    )?;
    
    // 4. Transfer to user
    token::transfer(
        CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.bridge_token_account.to_account_info(),
                to: ctx.accounts.user_token_account.to_account_info(),
                authority: ctx.accounts.bridge_authority.to_account_info(),
            },
        ),
        amount_out,
    )?;
    
    Ok(())
}
```

### 3.3 Integration Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| **AMM pool drained/paused** | Monitor pool health, circuit breaker |
| **High slippage** | Set max slippage limits, use price oracles |
| **AMM upgrade breaks integration** | Use versioned interfaces, monitor upgrades |
| **Liquidity fragmentation** | Start with major pairs only |
| **Front-running** | Use private mempools where available |

---

## 4. Component Responsibilities

### 4.1 Solana Program Structure

```
solana-bridge/
├── programs/
│   └── bridge/                       # Main bridge program
│       ├── src/
│       │   ├── lib.rs               # Program entry
│       │   ├── instructions/        # Core bridge logic
│       │   │   ├── mod.rs
│       │   │   ├── initialize.rs    # Setup bridge config
│       │   │   ├── deposit.rs       # Lock tokens, call Orca, emit message
│       │   │   └── withdraw.rs      # Verify VAA, call Orca, release
│       │   ├── state/               # Account structures
│       │   │   ├── mod.rs
│       │   │   ├── bridge_config.rs # Bridge parameters
│       │   │   └── transfer.rs      # Transfer tracking
│       │   ├── integrations/        # External protocol wrappers
│       │   │   ├── mod.rs
│       │   │   └── orca.rs          # Orca Whirlpool integration
│       │   ├── verification/        # Security modules
│       │   │   ├── mod.rs
│       │   │   └── wormhole.rs      # VAA verification
│       │   ├── security/            # Safety checks
│       │   │   ├── mod.rs
│       │   │   ├── circuit_breaker.rs
│       │   │   └── rate_limiter.rs
│       │   └── errors.rs            # Error codes
│       └── Cargo.toml
│
├── tests/                            # Integration tests
│   ├── bridge.ts
│   ├── orca_integration.ts
│   └── cross_chain.ts
│
└── Anchor.toml
```

**Key Difference from v1.0:** No AMM code, just integration wrappers.

### 4.2 Ethereum Contract Structure

```
ethereum-bridge/
├── contracts/
│   ├── core/                         # Core contracts
│   │   ├── BridgeGateway.sol        # Main bridge logic
│   │   └── TransferManager.sol      # Transfer state tracking
│   │
│   ├── integrations/                 # External protocol wrappers
│   │   └── CurveIntegration.sol     # Curve pool interface
│   │
│   ├── interfaces/                   # Contract interfaces
│   │   ├── IBridgeGateway.sol
│   │   ├── ICurvePool.sol
│   │   ├── IWormhole.sol
│   │   └── IERC20.sol
│   │
│   ├── libraries/                    # Shared utilities
│   │   ├── SafeTransfer.sol
│   │   ├── MessageCodec.sol         # Encode/decode
│   │   └── PriceOracle.sol          # Price validation
│   │
│   └── security/                     # Security modules
│       ├── ReentrancyGuard.sol
│       ├── AccessControl.sol
│       ├── CircuitBreaker.sol
│       └── PauseModule.sol
│
├── test/
│   ├── Bridge.test.ts
│   ├── CurveIntegration.test.ts
│   ├── Security.test.ts
│   └── CrossChain.integration.test.ts
│
├── scripts/
│   ├── deploy.ts
│   ├── configure.ts
│   └── verify.ts
│
└── hardhat.config.ts
```

**Key Difference from v1.0:** No AMM contracts, just integration layer.

---

## 5. Development Workflow

### 5.1 Phase 0: Research & Validation (Week 1)

**Goal:** Validate AMM integrations work on testnets

| Task | Owner | Output | Success Criteria |
|------|-------|--------|------------------|
| Test Curve on Goerli | Dev A | POC contract | Execute swap successfully |
| Test Orca on Devnet | Dev B | POC program | Execute swap successfully |
| Gas/Compute benchmarks | Both | Cost analysis | Document realistic costs |
| Liquidity check | Dev B | Liquidity report | Confirm sufficient testnet liquidity |
| SDK evaluation | Both | Integration guide | Document API usage |

**Deliverables:**
- [ ] Curve integration POC (Goerli)
- [ ] Orca integration POC (Devnet)
- [ ] Cost analysis spreadsheet
- [ ] Decision document: "Proceed with integration? Y/N"

### 5.2 Phase 1: Bridge Core (Week 2-3)

**Goal:** Build bridge logic without cross-chain messaging

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Solana bridge state | Dev B | Phase 0 | State accounts |
| EVM bridge contract | Dev A | Phase 0 | Core contract |
| Curve wrapper | Dev A | EVM bridge | Integration module |
| Orca wrapper | Dev B | Solana bridge | Integration module |
| Local testing | Both | All above | Test suite |

**Milestone:** Can deposit on one chain, simulate message, withdraw on same chain

### 5.3 Phase 2: Cross-Chain Messaging (Week 4-5)

**Goal:** Implement Wormhole integration

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Wormhole SDK setup | Dev B | Phase 1 | Dependencies |
| Message encoding spec | Dev B | None | Spec document |
| Solana VAA verification | Dev B | Wormhole SDK | Verification module |
| EVM message emission | Dev A | Wormhole SDK | Emission logic |
| Cross-chain test | Both | All above | Working bridge |

**Milestone:** Can send USDC from Ethereum → Solana successfully

### 5.4 Phase 3: Security & Features (Week 6-7)

**Goal:** Production-ready security features

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Circuit breakers | Dev B | Phase 2 | Pause mechanism |
| Rate limiting | Dev B | Phase 2 | Rate limiter |
| Price oracles | Dev A | Phase 2 | Oracle integration |
| Slippage protection | Both | Phase 2 | Slippage guards |
| Admin functions | Dev A | All | Admin interface |

**Milestone:** Production-ready security layer

### 5.5 Phase 4: Testing & Optimization (Week 8)

**Goal:** Comprehensive testing and optimization

| Task | Owner | Dependencies | Output |
|------|-------|--------------|--------|
| Integration tests | Both | Phase 3 | Full test suite |
| Gas optimization | Dev A | EVM contracts | Optimized code |
| Compute optimization | Dev B | Solana programs | Optimized code |
| Security review prep | Both | All | Audit package |
| Load testing | Both | All | Performance report |

---

## 6. Module Ownership

### 6.1 Developer A: Ethereum Bridge Specialist

**Responsibilities:**
- Ethereum bridge contract development
- Curve Finance integration
- Wormhole message emission (EVM side)
- Gas optimization
- EVM testing

**Key Files:**
```
contracts/core/BridgeGateway.sol
contracts/integrations/CurveIntegration.sol
contracts/security/CircuitBreaker.sol
```

**Critical Interface:**
```solidity
contract BridgeGateway {
    function deposit(
        address tokenIn,
        uint256 amountIn,
        uint256 minUsdOut,
        bytes32 solanaRecipient,
        uint256 maxSlippage
    ) external payable returns (uint64 sequence);
    
    function emergencyPause() external onlyOwner;
}
```

### 6.2 Developer B: Solana Bridge Specialist

**Responsibilities:**
- Solana bridge program development
- Orca Whirlpools integration
- Wormhole VAA verification (Solana side)
- Compute optimization
- Solana testing

**Key Files:**
```
programs/bridge/src/instructions/deposit.rs
programs/bridge/src/instructions/withdraw.rs
programs/bridge/src/integrations/orca.rs
programs/bridge/src/verification/wormhole.rs
```

**Critical Interface:**
```rust
pub fn deposit(
    ctx: Context<Deposit>,
    amount: u64,
    min_amount_out: u64,
    eth_recipient: [u8; 20],
) -> Result<()>;

pub fn withdraw(
    ctx: Context<Withdraw>,
    vaa: Vec<u8>,
) -> Result<()>;
```

### 6.3 Shared Responsibilities

**Message Format (Both developers must implement identically):**
```rust
#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct TransferMessage {
    pub version: u8,              // Protocol version (1)
    pub transfer_id: [u8; 32],    // Unique transfer ID
    pub sender: Vec<u8>,          // Source address (20 or 32 bytes)
    pub recipient: Vec<u8>,       // Destination address
    pub amount_usd: u64,          // USD value (6 decimals)
    pub nonce: u64,               // Replay protection
    pub source_chain: u16,        // Wormhole chain ID
    pub timestamp: i64,           // Unix timestamp
}
```

---

## 7. API Contracts

### 7.1 External Protocol APIs

#### Curve Finance (Read-Only Reference)

```solidity
interface ICurvePool {
    // Price quote (doesn't execute)
    function get_dy(int128 i, int128 j, uint256 dx) 
        external view returns (uint256);
    
    // Execute swap
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) 
        external returns (uint256);
    
    // Pool balances
    function balances(uint256 i) external view returns (uint256);
}
```

**Usage Example:**
```solidity
// 1. Get quote
uint256 expectedOut = curvePool.get_dy(0, 1, amountIn);

// 2. Apply slippage tolerance (0.5%)
uint256 minOut = expectedOut * 995 / 1000;

// 3. Execute
uint256 actualOut = curvePool.exchange(0, 1, amountIn, minOut);
```

#### Orca Whirlpools (Read-Only Reference)

```rust
// Using @orca-so/whirlpools-sdk
use orca_whirlpools::{
    WhirlpoolClient,
    swap_quote,
};

// Get quote
let quote = swap_quote(
    &whirlpool,
    amount_in,
    a_to_b, // true if swapping A→B
    slippage_tolerance,
)?;

// Execute via CPI
whirlpool::cpi::swap(
    cpi_ctx,
    quote.amount,
    quote.other_amount_threshold,
    quote.sqrt_price_limit,
    quote.a_to_b,
)?;
```

### 7.2 Bridge Internal APIs

#### Deposit Flow

```solidity
// Ethereum
function deposit(
    address tokenIn,      // USDC or USDT
    uint256 amountIn,     // Amount to bridge
    uint256 minUsdOut,    // Slippage protection
    bytes32 solanaRecipient, // Solana wallet
    uint256 maxSlippage   // Max acceptable slippage (bps)
) external payable returns (uint64 wormholeSequence);
```

```rust
// Solana
pub fn deposit(
    ctx: Context<Deposit>,
    amount: u64,              // Amount to bridge
    min_amount_out: u64,      // Slippage protection
    eth_recipient: [u8; 20],  // Ethereum address
) -> Result<()>;
```

#### Withdrawal Flow

```solidity
// Ethereum (if supporting Solana → Ethereum)
function withdraw(bytes memory vaa) external;
```

```rust
// Solana
pub fn withdraw(
    ctx: Context<Withdraw>,
    vaa: Vec<u8>,  // Wormhole VAA bytes
) -> Result<()>;
```

---

## 8. Testing Strategy

### 8.1 Testing Pyramid (Simplified)

```
                ┌─────────────┐
                │  E2E Tests  │  ← 10% (Full cross-chain)
                └─────────────┘
            ┌─────────────────────┐
            │ Integration Tests   │  ← 30% (Bridge + AMM)
            └─────────────────────┘
        ┌───────────────────────────────┐
        │      Unit Tests               │  ← 60% (Bridge logic only)
        └───────────────────────────────┘
```

**Key Difference from v1.0:** No math unit tests needed (using Curve/Orca)

### 8.2 Test Responsibilities

| Test Type | Owner | Frequency | Focus |
|-----------|-------|-----------|-------|
| Bridge unit tests | Both | Every commit | Lock/unlock, accounting |
| Curve integration | Dev A | Every commit | Wrapper correctness |
| Orca integration | Dev B | Every commit | Wrapper correctness |
| VAA verification | Dev B | Every commit | Message security |
| Cross-chain flow | Both | Daily | Full user journey |
| Security tests | Both | Before PR | Attack vectors |

### 8.3 Critical Test Cases

```typescript
// Must pass before any deployment

describe("Bridge Security", () => {
  it("prevents replay attacks", async () => {
    // Process same VAA twice → should revert
  });
  
  it("validates VAA signatures", async () => {
    // Submit invalid VAA → should revert
  });
  
  it("enforces slippage limits", async () => {
    // High slippage scenario → should revert
  });
  
  it("respects circuit breaker", async () => {
    // When paused → all operations revert
  });
});

describe("AMM Integration", () => {
  it("handles Curve swap failure gracefully", async () => {
    // Curve reverts → bridge doesn't lock tokens
  });
  
  it("handles Orca swap failure gracefully", async () => {
    // Orca reverts → refund mechanism works
  });
  
  it("validates AMM pool health", async () => {
    // Low liquidity → reject or warn
  });
});

describe("Cross-Chain Flow", () => {
  it("completes ETH → SOL transfer", async () => {
    // Full deposit + VAA + withdraw cycle
  });
  
  it("handles failed withdrawal gracefully", async () => {
    // VAA processed but Orca fails → recovery path
  });
  
  it("maintains accurate accounting", async () => {
    // After 100 transfers → balances match
  });
});
```

### 8.4 Testnet Integration Testing

**Pre-Mainnet Checklist:**
- [ ] Execute 10+ successful ETH → SOL transfers
- [ ] Execute 10+ successful SOL → ETH transfers
- [ ] Test with varying amounts ($10, $100, $1000, $10000)
- [ ] Verify slippage stays within expected range
- [ ] Test circuit breaker activation
- [ ] Test rate limiter
- [ ] Monitor gas/compute costs
- [ ] Verify Wormhole message finality times

---

## 9. Deployment Pipeline

### 9.1 Environment Strategy

```
Development → Testnet Testing → Mainnet Beta → Full Mainnet
(Local)       (Goerli/Devnet)   (Limited $)    (Full volume)
```

### 9.2 Deployment Checklist

**Phase 1: Testnet Deployment**
- [ ] Deploy Ethereum bridge to Goerli
- [ ] Configure Curve pool address (testnet)
- [ ] Deploy Solana bridge to Devnet
- [ ] Configure Orca pool address (testnet)
- [ ] Configure Wormhole bridge addresses
- [ ] Fund bridge with test tokens for liquidity
- [ ] Execute 20+ test transfers
- [ ] Monitor for any anomalies

**Phase 2: Security Audit**
- [ ] Code freeze
- [ ] Submit to auditor
- [ ] Address findings
- [ ] Re-audit critical changes
- [ ] Publish audit report

**Phase 3: Mainnet Beta**
- [ ] Deploy to mainnet with low caps ($10k total)
- [ ] Whitelist initial users
- [ ] Monitor 24/7 for 1 week
- [ ] Gradually increase caps
- [ ] Gather user feedback

**Phase 4: Full Launch**
- [ ] Remove caps
- [ ] Public announcement
- [ ] Monitor and optimize

### 9.3 Configuration Management

**Critical Configuration Values:**

```typescript
// Ethereum
const BRIDGE_CONFIG = {
  curvePool: "0x...", // Mainnet Curve USDC/USDT pool
  wormholeBridge: "0x...", // Wormhole core bridge
  maxSingleTransfer: ethers.parseUnits("50000", 6), // $50k
  maxDailyVolume: ethers.parseUnits("500000", 6), // $500k/day
  minTransfer: ethers.parseUnits("10", 6), // $10
  bridgeFee: 20, // 20 bps = 0.2%
  maxSlippageBps: 100, // 1%
};

// Solana
const BRIDGE_CONFIG = {
  orcaWhirlpool: new PublicKey("..."), // USDC/USDT pool
  wormholeBridge: new PublicKey("..."),
  maxSingleTransfer: 50_000_000_000, // $50k (6 decimals)
  maxDailyVolume: 500_000_000_000,
  minTransfer: 10_000_000, // $10
  bridgeFee: 20, // 20 bps
  maxSlippageBps: 100,
};
```

---

## 10. Risk Management

### 10.1 External Protocol Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Curve pool drained | Low | Critical | Monitor pool health, circuit breaker |
| Orca pool drained | Low | Critical | Monitor pool health, circuit breaker |
| Curve upgrade breaks API | Low | High | Version pinning, upgrade monitoring |
| Orca upgrade breaks API | Low | High | Version pinning, upgrade monitoring |
| High slippage event | Medium | Medium | Strict slippage limits, price oracles |

### 10.2 Monitoring & Alerts

**Critical Metrics to Monitor:**
```typescript
interface BridgeMetrics {
  // Health
  curvePoolBalance: { usdc: number; usdt: number };
  orcaPoolBalance: { usdc: number; usdt: number };
  bridgeBalance: { eth: number; sol: number };
  
  // Usage
  transfersLast24h: number;
  volumeLast24h: number;
  avgSlippage: number;
  
  // Security
  failedTransfers: number;
  circuitBreakerTrips: number;
  unusualActivityDetected: boolean;
}
```

**Alert Thresholds:**
- Pool liquidity drops below $100k → Warning
- Pool liquidity drops below $50k → Critical, pause bridge
- Slippage exceeds 2% → Warning
- Failed transfer rate >5% → Critical
- Unusual volume spike (>10x average) → Investigation

---

## 11. Future Enhancements

### 11.1 Post-MVP Features

**If Integration Works Well:**
- [ ] Add more token pairs (USDC/DAI, etc.)
- [ ] Support more chains (Polygon, BSC)
- [ ] Implement LP incentives for rebalancing
- [ ] Build SDK for easier integration
- [ ] Add batch transfers

**If We Need More Control:**
- [ ] Fork Curve/Orca for customization
- [ ] Build hybrid model (our fees + their swaps)
- [ ] Implement custom liquidity incentives
- [ ] Add flash loan protection

### 11.2 Decision Points

**When to Consider Custom AMM:**
- Existing AMMs lack needed features
- Fees too high for competitiveness
- Need tighter integration with bridge logic
- Want to capture more value
- Have resources for full audit

---

## 12. Resources & References

### 12.1 External Protocol Documentation

- **Curve Finance:** https://curve.readthedocs.io/
- **Orca Whirlpools:** https://orca-so.gitbook.io/orca-developer-portal/
- **Wormhole:** https://docs.wormhole.com
- **Solana:** https://docs.solana.com
- **Anchor:** https://www.anchor-lang.com

### 12.2 Integration Examples

- **Curve Integration Example:** https://github.com/curvefi/curve-contract/tree/master/contracts/testing
- **Orca SDK Examples:** https://github.com/orca-so/whirlpools/tree/main/sdk/examples
- **Wormhole Bridge Examples:** https://github.com/wormhole-foundation/wormhole-examples

### 12.3 Code Templates

**Quick Start Repositories:**
```bash
# Ethereum Bridge Template
git clone https://github.com/your-org/eth-bridge-template
cd eth-bridge-template
npm install
npx hardhat test

# Solana Bridge Template
git clone https://github.com/your-org/solana-bridge-template
cd solana-bridge-template
anchor build
anchor test
```

---

## 13. Development Setup

### 13.1 Prerequisites

**Required Tools:**
- Node.js 18+
- Rust 1.70+
- Solana CLI 1.16+
- Anchor 0.28+
- Hardhat
- Docker (for local testing)

**Recommended IDE Setup:**
- VS Code with extensions:
  - Rust Analyzer
  - Solidity
  - Anchor Language Support
  - Prettier

### 13.2 Environment Setup

**Ethereum Development:**
```bash
# Install dependencies
cd ethereum-bridge
npm install

# Setup environment
cp .env.example .env
# Edit .env with:
# - GOERLI_RPC_URL
# - PRIVATE_KEY
# - ETHERSCAN_API_KEY

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Deploy to Goerli
npx hardhat run scripts/deploy.ts --network goerli
```

**Solana Development:**
```bash
# Install dependencies
cd solana-bridge
npm install

# Build program
anchor build

# Configure Anchor
anchor keys list  # Get program ID
# Update Anchor.toml and lib.rs with program ID

# Run tests
anchor test

# Deploy to Devnet
anchor deploy --provider.cluster devnet
```

### 13.3 Local Testing Environment

**Option 1: Using Testnets (Recommended)**
```bash
# Ethereum: Goerli/Sepolia
# Solana: Devnet

# Advantages:
# - Real AMM protocols deployed
# - Real Wormhole relayers
# - Realistic gas/compute costs
# - No local infrastructure needed

# Get testnet tokens:
# ETH: https://goerlifaucet.com
# SOL: solana airdrop 2 --url devnet
```

**Option 2: Local Fork (Advanced)**
```bash
# Fork mainnet for testing
# Ethereum
npx hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY

# Solana (using Solana Test Validator)
solana-test-validator --clone CURVE_PROGRAM_ID --url mainnet-beta

# Advantages:
# - Faster iteration
# - Mainnet state/liquidity
# - No testnet token needed

# Disadvantages:
# - Complex setup
# - Wormhole mocking needed
```

---

## 14. Communication & Collaboration

### 14.1 Daily Workflow

**Async Standups (Slack/Discord):**
```markdown
**Daily Update - [Date]**

👤 Developer: [Name]

✅ Yesterday:
- Completed Curve integration wrapper
- Added slippage tests
- Fixed gas optimization issue

🚧 Today:
- Implement circuit breaker
- Write integration tests
- Code review for Dev B's PR

🚫 Blockers:
- Need Goerli testnet funds
- Waiting on Wormhole testnet config

📊 Tests:
- Unit: ✅ 45/45 passing
- Integration: 🟡 3/8 passing (in progress)

🔗 PR: https://github.com/your-org/bridge/pull/123
```

### 14.2 Code Review Guidelines

**Before Submitting PR:**
- [ ] All tests passing locally
- [ ] Code formatted (`cargo fmt`, `prettier`)
- [ ] No compiler warnings
- [ ] Gas/compute usage documented
- [ ] Security considerations noted

**PR Template:**
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] New feature
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Tested on testnet
- [ ] Gas/compute benchmarks included

## Security Considerations
List any security implications

## Checklist
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated
- [ ] No hardcoded values
- [ ] Error handling comprehensive

## Related Issues
Fixes #123
```

**Review Focus Areas:**
- **Security:** Reentrancy, overflow, access control
- **Integration:** Correct AMM/Wormhole usage
- **Error Handling:** All paths covered
- **Testing:** Adequate coverage
- **Gas/Compute:** Optimized where possible

### 14.3 Decision Log

**Major Decisions Template:**
```markdown
## Decision: [Title]
**Date:** 2025-11-05
**Status:** Proposed | Accepted | Rejected | Superseded

### Context
Why do we need to make this decision?

### Options Considered
1. **Option A:** Description
   - Pros: ...
   - Cons: ...
   
2. **Option B:** Description
   - Pros: ...
   - Cons: ...

### Decision
We chose Option [A/B] because...

### Consequences
- Positive: ...
- Negative: ...
- Mitigations: ...

### Action Items
- [ ] Update documentation
- [ ] Inform team
- [ ] Update code
```

**Example Decision:**
```markdown
## Decision: Use Curve + Orca Instead of Custom AMM
**Date:** 2025-11-05
**Status:** Accepted

### Context
Original plan was to build custom StableSwap AMM. Discovered existing protocols might work.

### Options Considered
1. **Build Custom AMM**
   - Pros: Full control, custom fees
   - Cons: 10+ weeks, security audit needed, start with zero liquidity
   
2. **Integrate Curve + Orca**
   - Pros: 3-4 weeks, audited, existing liquidity
   - Cons: Less control, dependent on external protocols

### Decision
Use Curve + Orca for MVP.

### Consequences
- Positive: Faster time to market, lower security risk
- Negative: Less fee flexibility, external dependencies
- Mitigations: Monitor pool health, circuit breakers, consider custom AMM for v2

### Action Items
- [x] Update technical documentation
- [ ] Research Curve/Orca APIs
- [ ] Build POC integrations
```

---

## 15. Troubleshooting Guide

### 15.1 Common Issues

**Issue: Curve swap fails with "Exchange resulted in fewer coins than expected"**
```solidity
// Problem: Slippage too tight
uint256 minOut = expectedOut * 999 / 1000; // 0.1% slippage

// Solution: Use more realistic slippage
uint256 minOut = expectedOut * 995 / 1000; // 0.5% slippage

// Or: Get fresh quote right before swap
uint256 freshQuote = curvePool.get_dy(i, j, amountIn);
uint256 minOut = freshQuote * 995 / 1000;
```

**Issue: Orca swap fails with "Amount exceeds slippage tolerance"**
```rust
// Problem: Price moved between quote and execution
let quote = get_quote(amount)?; // Gets quote
// ... time passes ...
swap(quote)?; // Price changed, fails

// Solution: Get quote immediately before swap
let quote = get_quote(amount)?;
swap(quote)?; // Execute immediately
```

**Issue: Wormhole VAA verification fails**
```rust
// Common causes:
// 1. VAA not yet finalized (need to wait for guardians)
// 2. Using wrong guardian set
// 3. VAA already processed (replay protection)

// Debug steps:
msg!("VAA timestamp: {}", vaa.timestamp);
msg!("Current guardian set: {}", guardian_set.index);
msg!("VAA guardian set: {}", vaa.guardian_set_index);
msg!("Transfer already processed: {}", transfer_state.processed);
```

**Issue: Transaction fails with "insufficient funds"**
```bash
# Ethereum
# Check: Do you have enough ETH for gas + Wormhole fee?
# Wormhole charges ~0.001 ETH per message

# Solution: Request more from faucet or fund wallet

# Solana  
# Check: Do you have enough SOL for rent + compute?
# Need ~0.01 SOL for transactions

# Solution: 
solana airdrop 2 --url devnet
```

### 15.2 Debug Commands

**Ethereum Debugging:**
```bash
# Watch contract events
npx hardhat run scripts/watch-events.ts --network goerli

# Check transaction details
npx hardhat verify-tx 0x[TX_HASH] --network goerli

# Call view functions
npx hardhat console --network goerli
> const bridge = await ethers.getContractAt("BridgeGateway", "0x...")
> await bridge.getTransferStatus("0x...")
```

**Solana Debugging:**
```bash
# Watch program logs
solana logs [PROGRAM_ID] --url devnet

# Get account data
solana account [ACCOUNT_ADDRESS] --url devnet

# Simulate transaction
anchor test --skip-deploy --skip-local-validator

# Check program is deployed
solana program show [PROGRAM_ID] --url devnet
```

**Wormhole Debugging:**
```bash
# Check if message was emitted
curl https://api.wormholescan.io/api/v1/observations/[CHAIN_ID]/[EMITTER]/[SEQUENCE]

# Get VAA
curl https://api.wormholescan.io/api/v1/vaas/[CHAIN_ID]/[EMITTER]/[SEQUENCE]

# Check guardian signatures
curl https://api.wormholescan.io/api/v1/governor/available-notional/[CHAIN_ID]
```

### 15.3 Testing Checklist

**Before Claiming "It Works":**
```markdown
- [ ] Deposit on Ethereum with USDC
- [ ] Deposit on Ethereum with USDT
- [ ] Verify Wormhole message emitted
- [ ] Wait for VAA (check Wormholescan)
- [ ] Submit VAA to Solana bridge
- [ ] Verify withdrawal successful
- [ ] Check user received correct amount
- [ ] Verify bridge accounting correct
- [ ] Repeat test with different amounts
- [ ] Test slippage protection works
- [ ] Test circuit breaker works
- [ ] Test rate limiter works
- [ ] Check gas/compute costs reasonable
```

---

## 16. Performance Optimization

### 16.1 Gas Optimization (Ethereum)

**Expensive Operations to Minimize:**
```solidity
// ❌ Expensive: Multiple external calls
function deposit_bad(address token, uint256 amount) external {
    IERC20(token).transferFrom(msg.sender, address(this), amount);
    IERC20(token).approve(curvePool, amount);
    curvePool.exchange(0, 1, amount, minOut);
    wormhole.publishMessage(...);
}

// ✅ Better: Batch approvals
function deposit_good(address token, uint256 amount) external {
    // Use pre-approved allowance pattern
    IERC20(token).transferFrom(msg.sender, address(this), amount);
    // Curve exchange (already has max approval)
    curvePool.exchange(0, 1, amount, minOut);
    wormhole.publishMessage(...);
}

// ✅ Best: Minimize storage writes
// Cache frequently accessed values
// Use events instead of storage where possible
```

**Target Gas Costs:**
- Deposit: <200k gas (~$10-20 at 50 gwei)
- Withdraw: <150k gas (~$7-15 at 50 gwei)

### 16.2 Compute Optimization (Solana)

**Compute Unit Targets:**
```rust
// Target: <200k compute units per instruction

// ❌ Expensive: Multiple CPI calls
pub fn deposit_bad(ctx: Context<Deposit>, amount: u64) -> Result<()> {
    // Each CPI costs ~3k-10k CUs
    token::transfer(...)?;  // CPI 1
    orca::swap(...)?;       // CPI 2
    // Multiple account deserializations
}

// ✅ Better: Minimize CPIs, use references
pub fn deposit_good(ctx: Context<Deposit>, amount: u64) -> Result<()> {
    // Use zero-copy where possible
    let pool = ctx.accounts.pool.load()?;
    
    // Batch operations
    token::transfer(...)?;
    orca::swap(...)?;
}
```

**Optimization Checklist:**
- [ ] Use `zero_copy` for large accounts
- [ ] Minimize account deserializations
- [ ] Use `&mut` instead of cloning
- [ ] Avoid unnecessary logging in production
- [ ] Request optimal compute units

---

## 17. Security Hardening

### 17.1 Security Checklist

**Pre-Deployment Security Review:**

**Access Control:**
- [ ] Only owner can pause/unpause
- [ ] Only owner can update config
- [ ] Only owner can withdraw fees
- [ ] Multi-sig for owner role

**Reentrancy Protection:**
- [ ] All state changes before external calls
- [ ] ReentrancyGuard on all public functions
- [ ] Checks-Effects-Interactions pattern

**Input Validation:**
- [ ] Validate all addresses are not zero
- [ ] Validate amounts are within bounds
- [ ] Validate slippage parameters
- [ ] Validate chain IDs

**Overflow Protection:**
- [ ] Use SafeMath/checked_add everywhere
- [ ] Test with max uint values
- [ ] Test with zero values

**Message Security:**
- [ ] VAA signature verification
- [ ] Replay protection (nonce tracking)
- [ ] Source chain validation
- [ ] Emitter address validation

**Economic Security:**
- [ ] Circuit breaker tested
- [ ] Rate limits tested
- [ ] Max transaction limits enforced
- [ ] Fee collection secure

### 17.2 Audit Preparation

**Documents to Prepare:**
```markdown
audit-package/
├── README.md                    # Overview
├── architecture/
│   ├── system-diagram.png
│   ├── flow-diagrams/
│   └── threat-model.md
├── contracts/
│   ├── ethereum/               # All Solidity code
│   └── solana/                 # All Rust code
├── tests/
│   ├── test-reports.html       # Coverage reports
│   └── test-cases.md           # Critical scenarios
├── documentation/
│   ├── technical-spec.md       # This document
│   ├── integration-guide.md
│   └── deployment-guide.md
└── concerns.md                  # Known issues/risks
```

**Key Questions Auditors Will Ask:**
1. How do you prevent replay attacks?
2. What happens if Curve/Orca is paused?
3. How do you handle failed withdrawals?
4. Can the owner rug users?
5. What are the circuit breaker conditions?
6. How is slippage calculated?
7. What happens if Wormhole is compromised?

---

## 18. Deployment Runbook

### 18.1 Pre-Deployment Checklist

**Code Quality:**
- [ ] All tests passing (100%)
- [ ] Code coverage >90%
- [ ] No TODOs in production code
- [ ] No console.log/msg! in production
- [ ] All configs externalized
- [ ] Documentation complete

**Security:**
- [ ] Security audit completed
- [ ] All high/critical findings resolved
- [ ] Audit report published
- [ ] Bug bounty program ready
- [ ] Emergency contacts documented

**Infrastructure:**
- [ ] RPC endpoints configured
- [ ] Monitoring setup
- [ ] Alert system configured
- [ ] Backup owner keys secured
- [ ] Incident response plan documented

### 18.2 Deployment Steps

**Step 1: Deploy to Testnet (Day 1)**
```bash
# 1. Deploy Ethereum contracts
cd ethereum-bridge
npx hardhat run scripts/deploy.ts --network goerli
# Note: BridgeGateway deployed at 0x...

# 2. Verify on Etherscan
npx hardhat verify --network goerli 0x... [CONSTRUCTOR_ARGS]

# 3. Deploy Solana program
cd solana-bridge
anchor build
anchor deploy --provider.cluster devnet
# Note: Program deployed at [PROGRAM_ID]

# 4. Initialize bridge
npx hardhat run scripts/initialize.ts --network goerli
anchor run initialize --provider.cluster devnet

# 5. Fund with test tokens
npx hardhat run scripts/fund-bridge.ts --network goerli
```

**Step 2: Integration Testing (Day 2-7)**
```bash
# Run comprehensive test suite
npm run test:integration

# Execute manual test transfers
# - $10, $100, $1000, $10000
# - USDC and USDT
# - Both directions

# Monitor for issues
npm run monitor --network testnet
```

**Step 3: Mainnet Deployment (Day 8)**
```bash
# PRODUCTION DEPLOYMENT - BE CAREFUL!

# 1. Final code review
git checkout main
git pull origin main
npm run build
npm run test

# 2. Deploy Ethereum
npx hardhat run scripts/deploy.ts --network mainnet

# 3. Deploy Solana
anchor deploy --provider.cluster mainnet-beta

# 4. Initialize with conservative limits
npx hardhat run scripts/initialize-production.ts --network mainnet

# 5. Transfer ownership to multisig
npx hardhat run scripts/transfer-ownership.ts --network mainnet
```

**Step 4: Verification (Day 8)**
```bash
# Verify deployments
npx hardhat verify --network mainnet [ADDRESS]
anchor verify [PROGRAM_ID]

# Verify config
npx hardhat run scripts/verify-config.ts --network mainnet

# Execute test transfer ($10)
npx hardhat run scripts/test-transfer.ts --network mainnet

# Monitor for 24 hours before increasing limits
```

### 18.3 Post-Deployment Monitoring

**First 24 Hours:**
- [ ] Monitor every transaction
- [ ] Check all transfers complete successfully
- [ ] Verify gas/compute costs as expected
- [ ] Monitor AMM pool health
- [ ] Check for any errors in logs
- [ ] Verify accounting accuracy

**First Week:**
- [ ] Daily volume review
- [ ] Slippage analysis
- [ ] User feedback collection
- [ ] Performance metrics review
- [ ] Gradually increase limits

**Ongoing:**
- [ ] Weekly security reviews
- [ ] Monthly financial audits
- [ ] Quarterly protocol upgrades
- [ ] Continuous monitoring

---

## 19. Glossary

| Term | Definition |
|------|------------|
| **AMM** | Automated Market Maker - protocol that provides liquidity |
| **VAA** | Verified Action Approval - Wormhole's cross-chain message |
| **CPI** | Cross-Program Invocation - Solana's way to call other programs |
| **Slippage** | Difference between expected and actual swap output |
| **Circuit Breaker** | Emergency pause mechanism for security |
| **Rate Limiter** | Mechanism to limit transaction volume over time |
| **Guardian** | Wormhole validator that signs messages |
| **Invariant** | StableSwap constant maintained during swaps |
| **Liquidity Pool** | Smart contract holding token reserves |
| **PDA** | Program Derived Address - Solana account owned by program |

---

## 20. Quick Reference

### 20.1 Important Addresses

**Ethereum Mainnet:**
```
Curve USDC/USDT Pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7
Wormhole Core Bridge: 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B
USDC Token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
USDT Token: 0xdAC17F958D2ee523a2206206994597C13D831ec7
```

**Solana Mainnet:**
```
Orca Whirlpool Program: whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc
Wormhole Core Bridge: worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth
USDC Token: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
USDT Token: Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB
```

### 20.2 Essential Commands

```bash
# Development
anchor build && anchor test
npx hardhat compile && npx hardhat test

# Deployment
anchor deploy --provider.cluster devnet
npx hardhat run scripts/deploy.ts --network goerli

# Monitoring
solana logs [PROGRAM_ID] --url mainnet-beta
npx hardhat run scripts/monitor.ts --network mainnet

# Verification
anchor verify [PROGRAM_ID]
npx hardhat verify --network mainnet [ADDRESS]
```

---

**Document Version:** 2.0 - Integration Approach  
**Last Updated:** 2025-11-05  
**Next Review:** After Phase 0 completion or when integration approach changes

**For Questions:**
- Technical: Post in #dev-bridge channel
- Security: Contact security@your-project.com
- General: See README.md

---

## Appendix: Migration Notes from v1.0

**What Changed:**
- ✅ Removed custom AMM development (Section 3.1-3.2 in v1.0)
- ✅ Added external protocol integration (Section 3)
- ✅ Simplified math module (no longer needed)
- ✅ Reduced team size from 3+ to 2-3 developers
- ✅ Cut development time from 10+ weeks to 3-4 weeks
- ✅ Simplified testing (no math verification needed)
- ✅ Updated deployment pipeline

**What Stayed the Same:**
- Core bridge architecture
- Wormhole integration approach
- Security requirements
- Message format
- Deployment strategy

**Action Items for Existing Team:**
- [ ] Review new Section 3 (External Protocol Integration)
- [ ] Update local dev environment per Section 13
- [ ] Run Phase 0 research tasks (Section 5.1)
- [ ] Adjust project timeline
- [ ] Update GitHub issues/milestones