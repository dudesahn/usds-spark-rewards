# X-Ray Report

> Grove USDS Compounder | commit `f8f796db93c52432cca0ed26861e94f5aaf20975` | x-ray v2

## 1. Protocol Overview

This repository contains a Yearn V3 strategy that stakes USDS into the Grove staking contract and compounds GROVE rewards back into USDS. The companion APR oracle estimates the reward APR from Grove staking emissions and live GROVE/USDC market pricing.

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Contract | Role | Source |
|---|---|---|
| `GroveCompounder` | Yearn strategy hook implementation. Stakes USDS, withdraws USDS, harvests GROVE, sells or auctions rewards, and reports total assets. | `src/GroveCompounder.sol` |
| `GroveCompounderAprOracle` | View-only APR oracle. Reads Grove staking rewards, prices GROVE in USDS terms through UniV3 if usable or a configurable UniV4 pool set otherwise, and caps reported APR at 50%. | `src/periphery/GroveCompounderAprOracle.sol` |

Protocol-authored scope is 630 source lines: 237 in `GroveCompounder.sol` and 393 in `GroveCompounderAprOracle.sol`. The simulator libraries and interfaces add supporting context but are not the primary review scope.

### Backwards-Compatibility Code

The strategy is a Grove port of the prior Spark reward compounder pattern. Compatibility-sensitive areas are the Yearn Tokenized Strategy/BaseHealthCheck inheritance surface, Uniswap V3 swapper integration, auction integration, and the PSM USDC -> USDS conversion path.

### How It Fits Together

1. Users enter and exit through inherited Yearn V3 vault functions on `GroveCompounder`.
2. `_deployFunds()` stakes deposited USDS into the external Grove staking contract with referral code `2009`.
3. `_freeFunds()` withdraws USDS from the Grove staking contract for Yearn withdrawals.
4. `_harvestAndReport()` claims GROVE, then either sends rewards to an auction by default or swaps GROVE -> USDC -> USDS through UniV3 plus the PSM when `useAuction == false`.
5. Any resulting USDS above the dust threshold is restaked before the hook reports `balanceOfStake() + balanceOfAsset()`.
6. `GroveCompounderAprOracle` reads current Grove staking emissions and total staked assets, computes a GROVE price, adjusts for the requested debt delta, and returns APR bounded by `MAX_EXPECTED_APR`.

## 2. Threat & Trust Model

### Protocol Threat Profile

Small Yearn strategy with high external-dependency weight. Core value risk comes from external staking behavior, reward-sale routing, oracle pricing assumptions, and inherited Yearn vault mechanics rather than large in-repo state machines.

### Actors & Adversary Model

| Actor | Capabilities |
|---|---|
| Depositor/withdrawer | Uses inherited Yearn V3 deposit, mint, withdraw, and redeem paths. Deposit availability is affected by `availableDepositLimit()`. |
| Keeper | Calls inherited `report()` and custom `kickAuction()`. Can trigger reward movement but should not be able to redirect principal or sell assets. |
| Management | Configures sale mode, auction, UniV3 fee, referral, oracle management, and oracle V4 pool list. Trusted for configuration correctness. |
| Auction buyer | Interacts with the external Yearn auction contract after rewards are transferred there. |
| External protocols | Grove staking contract, PSM wrapper, UniV3 router/factory/pool, UniV4 StateView, and Yearn base contracts. |

See [entry-points.md](entry-points.md) for the full callable entry point map.

### Trust Boundaries

| Boundary | Direction | Dependency |
|---|---|---|
| Staked principal | `GroveCompounder -> STAKING` | `stake()`, `withdraw()`, `getReward()`, `earned()`, `totalSupply()`, `rewardRate()`, `periodFinish()` |
| Reward sale | `GroveCompounder -> Auction` or `GroveCompounder -> UniV3/PSM` | Auction receiver/want validation, UniV3 fee config, PSM `tin()` and `sellGem()` |
| Oracle pricing | `GroveCompounderAprOracle -> UniV3/UniV4` | V3 active liquidity and USDC balance gates; V4 active liquidity, median-deviation filter, configurable pool set |
| Yearn inheritance | External callers -> inherited base -> custom hooks | Inherited ERC4626/accounting/role semantics call `_deployFunds()`, `_freeFunds()`, `_harvestAndReport()`, and `_emergencyWithdraw()` |

### Key Attack Surfaces

- **Reward sale mode branch** &nbsp;[[G-3](invariants.md#g-3), [G-9](invariants.md#g-9)] - `GroveCompounder._harvestAndReport()` chooses direct swap or auction at `src/GroveCompounder.sol:96-108`; audit both branches for value movement, slippage, and dependency behavior.
- **Auction token kick** &nbsp;[[G-4](invariants.md#g-4), [G-5](invariants.md#g-5)] - `kickAuction()` lets keepers move arbitrary non-asset tokens held by the strategy to the configured auction at `src/GroveCompounder.sol:158-179`.
- **Staking principal accounting** &nbsp;[[E-1](invariants.md#e-1)] - Strategy-reported assets come from external staking balance plus idle USDS at `src/GroveCompounder.sol:111-117`; trace every path that changes either term.
- **PSM fee dependency** &nbsp;[[G-3](invariants.md#g-3)] - Direct swap route requires `PSM_WRAPPER.tin() == 0` before converting USDC to USDS at `src/GroveCompounder.sol:96-105`.
- **APR price fallback** &nbsp;[[I-3](invariants.md#i-3), [I-4](invariants.md#i-4)] - `_grovePrice()` uses UniV3 only if its pool clears liquidity and USDC balance gates, then falls back to selected UniV4 pricing at `src/periphery/GroveCompounderAprOracle.sol:211-237`.
- **V4 pool-list selection** &nbsp;[[I-2](invariants.md#i-2), [I-4](invariants.md#i-4)] - Oracle management can replace, add, or remove candidate pools; selection filters by active liquidity and 10% median price deviation at `src/periphery/GroveCompounderAprOracle.sol:147-176` and `255-335`.
- **APR cap and debt delta** &nbsp;[[G-11](invariants.md#g-11), [I-3](invariants.md#i-3)] - `aprAfterDebtChange()` adjusts total staked assets by signed delta, reverts for zero denominator, and rejects APR above 50% at `src/periphery/GroveCompounderAprOracle.sol:109-132`.

### Upgrade Architecture Concerns

No proxy or upgrade hook is implemented in the two in-scope contracts. Upgrade risk is operational: deployed strategy/oracle replacement and management-controlled configuration changes.

### Protocol-Type Concerns

As a Yearn V3 strategy, the critical questions are whether custom hooks preserve Tokenized Strategy accounting expectations, whether external reward-sale paths can strand or misprice rewards, and whether APR hints stay bounded under live liquidity drift. As an APR oracle, the code intentionally uses spot-like pool state rather than time-weighted quotes; its defense is pool gating, multi-pool median filtering, and a hard APR cap.

### Temporal Risk Profile

The strategy's profit path depends on weekly Grove reward periods and live auction execution. The oracle returns zero after `periodFinish`, while tests top up live reward state to avoid end-of-week drift. Pool liquidity can move between V3 and V4 pools, so pricing behavior is live-state-sensitive.

### Composability & Dependency Risks

- Grove staking is the only principal venue.
- The direct swap path depends on UniV3 pool liquidity and a zero PSM fee.
- The default auction path depends on a configured auction whose `receiver` is this strategy and whose `want` is USDS.
- The oracle's UniV4 path depends on `StateView.getLiquidity()` and `StateView.getSlot0()` for each configured pool.

## 3. Invariants

> Full invariant map: [invariants.md](invariants.md)

Summary: 20 enforced guards, 4 inferred single-contract invariants, 0 scoped cross-contract invariants, and 1 economic invariant were extracted for the two in-scope contracts. Cross-contract assumptions involving Grove staking, PSM, UniV3/UniV4, and Yearn base contracts are listed as trust boundaries rather than formal scoped invariants because their implementations are outside the two-contract review scope.

## 4. Documentation Quality

The root README is the standard Yearn Tokenized Strategy mix template and does not describe Grove-specific configuration, the chosen auction default, PSM fee guard, V4 pool fallback, or APR cap. Tests currently encode most product intent.

## 5. Test Analysis

### Test Depth

Fork tests cover strategy setup, auction defaulting, PSM fee guard on the swap path, auction-path behavior when PSM fees are nonzero, profit reporting, fee behavior, shutdown, function signatures, oracle pool setters, V4 pool fallback, V4 pool median/liquidity selection, stale V3 liquidity, and the 50% APR cap.

### Gaps

- Tests depend on live mainnet staking state and pool liquidity.
- `forge coverage` in this x-ray run did not produce useful coverage: it pulled dependencies, then fork-dependent `setUp()` reverted when run without the fork environment.
- The stock x-ray enumeration script hit macOS `grep -P` incompatibilities, so nSLOC/test-function counts from that raw output are not reliable. Portable supplemental line counts were used instead.

## 6. Developer & Git History

### Contributors

Git history in this worktree shows a single contributor: `dudesahn`.

### Review & Process Signals

The recent history is security-relevant and shows iterative hardening around Grove pricing and reward sale routing. The top git-security candidate is `334030f fix: harden grove reward pricing`, followed by `087c8aa fix: guard grove psm swaps` and `872efb4 feat: make grove oracle pools configurable`.

### File Hotspots

Hotspots by recent source churn include `src/GroveCompounder.sol`, `src/periphery/GroveCompounderAprOracle.sol`, `src/test/utils/Setup.sol`, `src/test/Operation.t.sol`, and `src/test/Oracle.t.sol`.

### Security-Relevant Commits

| Commit | Signal |
|---|---|
| `334030f` | Hardened Grove reward pricing, APR cap, and V4 selection behavior. |
| `087c8aa` | Added direct-swap PSM fee guard. |
| `872efb4` | Made Grove oracle pools configurable. |
| `94b7b58` | Added Grove V4 oracle fallback. |
| `2b20055` | Ported compounder from Spark pattern to Grove. |

### Dangerous Area Evolution

Reward pricing changed repeatedly because GROVE liquidity moved between pools and V3 liquidity became unreliable. Treat oracle pool selection and sale-mode defaults as the highest-churn risk surface.

### Forked Dependencies

The worktree uses external Yearn periphery, Tokenized Strategy, OpenZeppelin, Uniswap V3, and forge-std dependencies under `lib/`. Coverage auto-installed missing dependencies into the detached worktree during x-ray.

### Technical Debt Markers

- The README is generic rather than Grove-specific.
- The x-ray script's BSD grep incompatibility makes raw metrics noisy on macOS.
- Live fork tests are sensitive to current reward period and pool liquidity.

### Security Observations

The custom in-scope code is compact and mostly defensive: auction is default, PSM fee is guarded before direct swaps, V3 liquidity is gated, V4 candidate pools are configurable, and APR is capped. The main audit burden is validating assumptions at external boundaries and inherited Yearn behavior.

### Cross-Reference Synthesis

The strongest review lanes are boundary/periphery for external calls, economic/security for reward routing and oracle pricing, access-control/trust-gap for management and keeper powers, and math/numerical for price conversion and APR denominator behavior.

## X-Ray Verdict

Proceed to focused Solidity Auditor lanes. Prioritize external dependency behavior, inherited Yearn hook assumptions, reward token movement, V4 pool selection, APR caps, and live-liquidity failure modes. Use this x-ray as orientation only; every reported issue must be independently validated against source and tests.
