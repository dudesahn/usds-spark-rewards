# X-Ray Report

> Grove USDS Compounder | 737 production nSLOC (669 executable + 68 interfaces) | f8f796d (`HEAD`, detached) | Foundry | 25/07/26

---

## 1. Protocol Overview

**What it does:** A Yearn V3 tokenized strategy stakes USDS in Sky Rewards, realizes GROVE incentives through Auction or Uniswap/PSM, and exposes a pool-derived APR oracle.

- **Users**: ERC-4626 vaults and depositors enter through the imported TokenizedStrategy runtime.
- **Core flow**: USDS is staked, GROVE rewards are claimed and sold, proceeds are converted back to USDS, and assets are restaked.
- **Key mechanism**: Dual reward-sale routing plus V3-first/V4-fallback market pricing for APR estimation.
- **Token model**: USDS is strategy principal, GROVE is reward inventory, and USDC is the intermediate sale/PSM asset.
- **Admin model**: Imported strategy management/keeper roles and a separate one-step APR-oracle management address act without a first-party timelock.

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|---------------|------:|------|
| Strategy | `GroveCompounder` | 142 | Stakes USDS and realizes GROVE rewards through Auction or Uniswap/PSM |
| APR pricing | `GroveCompounderAprOracle` | 286 | Estimates staking APR from V3 or selected V4 pool prices |
| Quote math | `UniswapV3SwapSimulator`, `UniswapV3SwapSimulatorCore` | 241 | Replays Uniswap V3 swap steps against live pool state |

The remaining 68 production nSLOC are first-party interfaces used at integration boundaries.

### How It Fits Together

The core trick: reward inventory is periodically converted back into the same USDS asset that the strategy compounds in Sky Rewards.

### Deposit and Stake

```text
TokenizedStrategy.deposit()                  (imported runtime)
└─ GroveCompounder._deployFunds(amount)
   └─ SkyRewards.stake(amount, referral)     (principal leaves strategy custody)
```

### Report Through Auction

```text
TokenizedStrategy.report()                   (imported runtime)
└─ GroveCompounder._harvestAndReport()
   ├─ SkyRewards.getReward()
   ├─ GroveCompounder._kickAuction(GROVE)
   │  ├─ GROVE.safeTransfer(Auction)
   │  └─ Auction.kick(GROVE)                 (sale settles externally)
   └─ SkyRewards.stake(available USDS)
```

### Report Through Uniswap and PSM

```text
TokenizedStrategy.report()
└─ GroveCompounder._harvestAndReport()
   ├─ UniswapV3Swapper._swapFrom(GROVE, USDC)
   ├─ PsmWrapper.sellGem(USDC → USDS)        (requires zero PSM fee)
   └─ SkyRewards.stake(available USDS)
```

### APR Quote

```text
GroveCompounderAprOracle.aprAfterDebtChange()
├─ SkyRewards.totalSupply/rewardRate/periodFinish
├─ V3 path: UniswapV3SwapSimulator.simulateExactInputSingle()
└─ V4 fallback: StateView liquidity + slot0 → median/deviation filter
   └─ rewardRate × seconds/year × GROVE price ÷ adjusted staked assets
```

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Yield Aggregator** with **DEX/AMM** and **Stablecoin/PSM** characteristics

The strategy compounds external staking rewards, while both realized yield and forecast APR depend on public market liquidity and a USDC-to-USDS conversion boundary.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|--------------|
| Strategy management | Trusted | Instant reward-sale configuration and manual reward claims in first-party code; imported runtime grants broader strategy powers; no first-party timelock |
| Strategy keepers | Bounded (operations) | Can kick reward auctions and use imported report paths; explicit first-party action is not paused here |
| APR-oracle management | Trusted | One-step transfer plus instant replacement/addition/removal of V3/V4 pricing sources; no timelock or pause |
| ERC-4626 users/vaults | Untrusted | Enter through imported deposit/withdraw surfaces and rely on reported strategy accounting |

**Adversary Ranking** (ordered by threat level for this protocol type, adjusted by git evidence):

1. **Market-price manipulator / MEV searcher** — Public Uniswap state determines reward valuation and therefore reported APR.
2. **Compromised management** — Management can immediately redirect sale configuration or pricing inputs at both trust boundaries.
3. **External dependency failure or governance change** — Sky Rewards, PSM, Auction, and Uniswap behavior and liquidity are outside first-party control.
4. **Permissionless vault user** — Imported ERC-4626 flows interact with asynchronously realized rewards and external staking liquidity.
5. **Compromised keeper** — Keeper actions can move accumulated rewards into the configured auction and trigger report-time external calls.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Imported TokenizedStrategy ↔ GroveCompounder** — ERC-4626 accounting, role assignment, report, shutdown, and health-check behavior live in dependencies while first-party hooks move funds at `src/GroveCompounder.sol:76-123`.

- **Strategy management ↔ reward venues** — Instant `setAuction`, sale-mode, fee, and threshold changes determine how reward inventory exits at `src/GroveCompounder.sol:189-235`; no first-party delay protects operations.

- **APR-oracle management ↔ consumers** — One-step management transfer and instant pool-list changes control the data sources behind `aprAfterDebtChange` at `src/periphery/GroveCompounderAprOracle.sol:135-175`.

- **First-party code ↔ external protocols** — Staking, PSM, Auction, and Uniswap calls are synchronous and generally fail closed, but their state, upgrades, and liquidity are not controlled here.

### Key Attack Surfaces

- **Initial auction-mode configuration** &nbsp;&#91;[I-4](invariants.md#i-4), [G-6](invariants.md#g-6)&#93; — `GroveCompounder.sol:19-22,107-109,174-179` begins with auction mode selected before an auction address exists; worth tracing deployment ordering and first profitable report behavior.

- **Reward-sale path asymmetry** &nbsp;&#91;[G-3](invariants.md#g-3), [G-4](invariants.md#g-4), [G-5](invariants.md#g-5)&#93; — `GroveCompounder.sol:89-117,158-180` routes identical GROVE inventory through paths with different fee, threshold, settlement, and external-call assumptions.

- **V3-first / V4-fallback price selection** &nbsp;&#91;[I-2](invariants.md#i-2), [I-3](invariants.md#i-3), [I-5](invariants.md#i-5)&#93; — `GroveCompounderAprOracle.sol:211-305` combines a single V3 quote with median-filtered V4 candidates; worth tracing liquidity units, pool orientation, and fallback transitions.

- **APR numerator/denominator scaling** &nbsp;&#91;[G-12](invariants.md#g-12), [G-13](invariants.md#g-13)&#93; — `GroveCompounderAprOracle.sol:109-132` mixes external reward rate, a hypothetical signed debt delta, token decimal normalization, and a hard maximum.

- **Replicated Uniswap V3 swap traversal** &nbsp;&#91;[G-24](invariants.md#g-24), [G-25](invariants.md#g-25)&#93; — `UniswapV3SwapSimulatorCore.sol:61-190` copies tick traversal and uses unchecked signed deltas; worth comparing boundary and rounding behavior to the pinned upstream implementation.

- **External staking accounting and pause state** — `GroveCompounder.sol:38-41,76-123,125-133` checks pause on deployment/deposit limits while harvest and withdrawal behavior remains defined by the external staking contract.

- **Instant configuration authority** &nbsp;&#91;[I-1](invariants.md#i-1), [I-3](invariants.md#i-3)&#93; — `GroveCompounderAprOracle.sol:86-100,135-175` gives one address immediate control over all pricing candidates and its own successor.

### Protocol-Type Concerns

**As a Yield Aggregator:**

- `GroveCompounder.sol:84-118` reports staked plus idle USDS after external reward realization; worth checking every external balance transition against imported TokenizedStrategy accounting.
- `GroveCompounder.sol:43-53` creates unlimited approvals for staking and the PSM wrapper, so dependency identity and upgrade assumptions are part of the custody model.

**As a DEX/AMM consumer:**

- `GroveCompounderAprOracle.sol:239-245` treats raw in-range liquidity and USDC pool balance as V3 usability gates; neither directly measures quote price impact.
- `GroveCompounderAprOracle.sol:307-335` selects the most liquid V4 quote within 10% of a median that can be formed from a management-sized candidate set.

**As a Stablecoin/PSM integrator:**

- `GroveCompounder.sol:98-105` requires zero `tin` only on the direct-swap route and assumes the wrapper converts the full strategy USDC balance to USDS.

### Temporal Risk Profile

**Deployment & Initialization:**

- `GroveCompounder.sol:19-22,38-54` deploys with `useAuction=true` and `auction=0`; G-6 fails closed until management completes sale-venue setup.
- `GroveCompounderAprOracle.sol:95-101` assigns the deployer as management and seeds four immutable IDs without validating live V4 state during construction.

**Market Stress:**

- `GroveCompounderAprOracle.sol:211-305` changes from V3 to V4 pricing when liquidity/balance gates or simulation fail, making transition behavior relevant during rapid liquidity changes.
- `GroveCompounder.sol:80-82,120-123` relies on Sky Rewards withdrawal behavior when staked liquidity or protocol pause conditions change.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **Sky Rewards staking** — via `GroveCompounder._deployFunds/_freeFunds/_harvestAndReport`
> - Assumes: exact USDS stake/withdraw accounting, valid reward rate, and callable reward claims
> - Validates: staking token equality and deployment/deposit pause state
> - Mutability: external protocol; governance and upgrade controls not established in scope
> - On failure: strategy operation reverts

> **PSM Wrapper** — via `GroveCompounder._harvestAndReport`
> - Assumes: USDC is converted to USDS for the specified receiver
> - Validates: wrapper USDS address at construction and `tin == 0` before direct-route conversion
> - Mutability: external protocol; controls not established in scope
> - On failure: report reverts

> **Auction** — via `GroveCompounder._kickAuction`
> - Assumes: transferred GROVE is sold and USDS proceeds return to the strategy
> - Validates: nonzero address, receiver equals strategy, and wanted token equals USDS at configuration
> - Mutability: auction behavior may change after configuration; controls not established in scope
> - On failure: kick reverts after the token transfer as part of the same transaction

> **Uniswap V3/V4** — via `GroveCompounderAprOracle._grovePrice` and inherited swapper logic
> - Assumes: live pool state and configured token orientation yield representative GROVE/USDC values
> - Validates: minimum V3 liquidity/USDC balance, V4 minimum liquidity, nonzero price, and 10% median deviation
> - Mutability: permissionless liquidity and governed protocol deployments
> - On failure: V3 falls back to V4; absence of both prices reverts

**Token Assumptions** *(unvalidated only)*:

- USDS/USDC/GROVE: assumes standard non-rebasing, exact-transfer ERC-20 balances; fixed 18/6-decimal normalization is embedded in pricing and conversion logic.

**Shared State Exposure:**

- Public Uniswap V3/V4 liquidity supplies both the APR oracle's observations and, for V3 mode, the strategy's realized reward-sale execution environment.

---

## 3. Invariants

> ### 📋 Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **25 Enforced Guards** (`G-1` … `G-25`) — per-call preconditions with check, location, and purpose
> - **5 Single-Contract Invariants** (`I-1` … `I-5`) — Bound properties derived from verified write sites
> - **0 Cross-Contract Invariants** — no caller/callee storage pair was wholly inside scope
> - **0 Economic Invariants** — no higher-order property met the derivation gate
>
> Every inferred block cites a concrete guard-lift plus write-site enumeration. The **On-chain=No** blocks are the high-signal orientation items.

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` is a generic Yearn strategy-development guide, not a Grove-specific design document |
| NatSpec | 14 annotations | Public configuration and helper functions are partly documented; system invariants and dependency assumptions are not |
| Spec/Whitepaper | Missing | No first-party protocol specification or architecture document detected |
| Inline Comments | Adequate | Core reward-sale and simulator steps are annotated, but operational/deployment sequencing is sparse |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 5 | File scan (always reliable) |
| Test functions | 26 | File scan (always reliable) |
| Line coverage | Unavailable — all four suites reverted in `setUp()` without a usable fork-backed environment | `forge coverage` |
| Branch coverage | Unavailable — all four suites reverted in `setUp()` without a usable fork-backed environment | `forge coverage` |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 26 | Strategy operation, shutdown, function signatures, and APR-oracle behavior |
| Stateless Fuzz | 0 by x-ray naming detector | none reported |
| Stateful Fuzz (Foundry) | 0 | none |
| Formal Verification (Certora) | 0 | none |

### Gaps

- No stateful invariant suite covers strategy accounting across reward-sale modes and external dependency transitions.
- No formal specification checks the replicated Uniswap V3 traversal or APR scaling/bounds.
- No Echidna, Medusa, Halmos, or HEVM properties were detected.
- The README describes fork execution, but the x-ray detector found no explicit first-party fork primitive and coverage could not establish runtime metrics without a usable environment.

---

## 6. Developer & Git History

> Repo shape: normal_dev — 18 source-touching commits across 21 total commits from 03/07/25 through 08/07/26; analyzed branch: detached `HEAD` at `f8f796d`.

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| dudesahn | 21 | +3179 / -891 | 100% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 1 | Single-developer history |
| Merge commits | 0 of 21 (0%) | No merge-commit review signal |
| Repo age | 03/07/25 → 08/07/26 | 370-day development span |
| Recent source activity (30d) | 8 commits | Late concentrated change set |
| Test co-change rate | 66.7% | File co-modification rate, not runtime coverage |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| `src/GroveCompounder.sol` | 6 | Strategy fund-flow and sale-routing churn |
| `src/periphery/GroveCompounderAprOracle.sol` | 4 | Pricing and configuration churn |
| `src/libraries/UniswapV3SwapSimulatorCore.sol` | 3 | Replicated swap-math churn |
| `src/interfaces/IStrategyInterface.sol` | 7 | ABI churn; interface only |

### Security-Relevant Commits

**Score** combines fix-like message, guard/accounting changes, security domains, focus, and test co-change; 10+ warrants a manual diff.

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| `334030f` | 08/07/26 | fix: harden grove reward pricing | 16 | Runtime guards, transfer/accounting changes, four security domains |
| `087c8aa` | 07/07/26 | fix: guard grove psm swaps | 14 | New runtime guard in fund-flow path |
| `872efb4` | 07/07/26 | feat: make grove oracle pools configurable | 9 | New guards and pricing/access-control changes |
| `94b7b58` | 07/07/26 | feat: add grove v4 oracle fallback | 8 | Oracle/fund-flow changes with tests |
| `2b20055` | 07/07/26 | feat: port compounder to grove | 8 | Multi-domain strategy/oracle feature change |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|---------------|--------:|-----------|
| fund_flows | 12 | `GroveCompounder.sol`, `GroveCompounderAprOracle.sol` |
| state_machines | 10 | `GroveCompounder.sol`, `UniswapV3SwapSimulatorCore.sol` |
| oracle_price | 8 | `GroveCompounderAprOracle.sol`, simulator libraries |
| access_control | 4 | `GroveCompounderAprOracle.sol` |

### Security Observations

- **Single-developer concentration** — all 21 commits and 100% of source-line changes are attributed to one author.
- **No merge-commit signal** — the reachable history has zero merge commits across 21 commits.
- **Late pricing churn** — V4 fallback, configurable pools, and reward-price hardening landed in the final two days (`94b7b58`, `872efb4`, `334030f`).
- **Fix/test coupling is incomplete** — 40% of fix-scored commits lacked same-commit test-file changes; this is co-modification, not coverage.
- **No technical-debt markers** — the git analyzer found no TODO/FIXME/HACK/XXX items in current first-party source.

### Cross-Reference Synthesis

- **Oracle pricing is both a late-change cluster and a top attack surface** — three final-day commits plus I-2/I-3/I-5 make pool selection the highest-leverage orientation target.
- **Strategy fund flows have the highest dangerous-area churn** — 12 commits align with the reward-sale asymmetry and external dependency boundaries in Section 2.
- **`GroveCompounder.sol` combines custody and configuration churn** — six modifications plus I-4 point reviewers to deployment and mode-transition traces first.

---

## X-Ray Verdict

**FRAGILE** — Unit tests and partial NatSpec exist, but no stateful fuzz/formal properties or first-party timelock protect a dependency-heavy strategy and freshly changed pricing subsystem.

**Structural facts:**
1. 737 production nSLOC across strategy, APR pricing, quote math, and integration interfaces.
2. 5 test files with 26 detected test functions; runtime coverage was unavailable because all suites reverted in setup.
3. 13 explicit first-party state-changing entry points: 1 keeper-gated and 12 management-gated.
4. One author produced 100% of reachable source changes across 21 commits, with eight source commits in the final 30-day window.
5. No stateful fuzz, formal verification, first-party timelock, or first-party specification was detected.
