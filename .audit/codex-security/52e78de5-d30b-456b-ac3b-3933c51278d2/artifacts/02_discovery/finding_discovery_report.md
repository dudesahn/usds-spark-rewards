# Finding Discovery Report

## CAN-001 — Zero-minimum GROVE reward sale can be sandwiched

- Affected locations: `src/GroveCompounder.sol:84-118`, especially `96-105`.
- Source: public-mempool ordering and permissionless GROVE/USDC trading around an authorized report when direct-swap mode is enabled.
- Closest control: keeper authorization and a reward threshold exist, but no quote, TWAP, price-impact bound, or nonzero minimum output constrains execution.
- Sink: `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` forwards zero as the exact-input minimum output.
- Impact: an MEV searcher can extract accumulated reward value and reduce depositor yield; staked principal is not directly sold.
- Validation gap: quantify viable loss and costs on a representative fork; the source-to-sink parameter trace is statically complete.

## CAN-002 — Primary APR path trusts a manipulable V3 current-state quote

- Affected locations: `src/periphery/GroveCompounderAprOracle.sol:109-132,211-245`; `src/libraries/UniswapV3SwapSimulator.sol:23-46`; `src/libraries/UniswapV3SwapSimulatorCore.sol:61-100`.
- Source: permissionless V3 trading and temporary liquidity control the live pool state observed by the oracle.
- Closest control: current liquidity, raw USDC balance, and a final APR cap; no TWAP or independent-source check precedes acceptance.
- Sink: the first positive V3 simulation is returned as the price and annualized into APR before the V4 fallback is consulted.
- Impact: an integrating allocator can misallocate or revert on manipulated yet sub-cap APR; capital impact depends on downstream consumption.
- Validation gap: measure same-transaction manipulation cost and confirm an actual consumer's decision path.

## CAN-003 — V4 fallback accepts mutable spot pricing without a trustworthy quorum

- Affected locations: `src/periphery/GroveCompounderAprOracle.sol:147-163,211-236,247-335`; `src/interfaces/IUniswapV4StateView.sol:4-10`.
- Source: permissionless V4 trading controls current `sqrtPriceX96`; sibling quote failures or supported small configurations can leave one/few valid quotes.
- Closest control: minimum raw liquidity and a current-median deviation filter; there is no minimum quote quorum, TWAP, independent source, or value-depth check.
- Sink: one current quote can be its own passing median and become the fallback APR price.
- Impact: fallback APR can be biased below the cap or made unavailable, subject to V3 failure and downstream consumer action.
- Validation gap: establish deployed pool configuration, realistic cross-pool cost, and a downstream consumer path.

## CAN-004 — Unbounded V3 tick traversal can exhaust gas before fallback

- Affected locations: `src/libraries/UniswapV3SwapSimulator.sol:23-46`; `src/libraries/UniswapV3SwapSimulatorCore.sol:98-179`; `src/periphery/GroveCompounderAprOracle.sol:211-236`.
- Source: permissionless V3 LP/trader activity controls current price, active liquidity, and initialized tick topology.
- Closest control: the precheck does not bound tick traversal, iteration count, or subcall gas; `try/catch` does not guarantee useful gas remains after an out-of-gas subcall.
- Sink: repeated tick-bitmap and tick reads in the simulator loop consume the caller's transaction gas before the intended V4 fallback.
- Impact: APR-dependent transactions can revert and the fallback may not restore availability.
- Validation gap: construct a qualifying dense-tick state, measure gas, and compare it with downstream transaction budgets.

## CAN-005 — APR remains nonzero at the exact reward-expiry timestamp

- Affected locations: `src/periphery/GroveCompounderAprOracle.sol:109-132`, especially `114-116`; `src/interfaces/IStaking.sol:19-21`.
- Source: block timestamp exactly equals the staking reward period finish.
- Closest control: the expiry predicate uses strict `>` rather than `>=`.
- Sink: the function can annualize the stored reward rate despite zero remaining reward duration.
- Impact: a transient stale APR can misrank or misallocate capital if a consumer acts at the equality boundary.
- Validation gap: confirm the deployed staking contract's exact reward-rate semantics at equality and demonstrate a reachable consumer action in that block.

## CAN-006 — Late deposits can dilute unreported accrued reward value

- Affected locations: `src/GroveCompounder.sol:70-72,89-118`.
- Source: an open-mode or allowlisted depositor times entry after rewards accrue but before the strategy realizes them in a report.
- Closest control: health checks and profit locking govern realized profit but do not reserve pre-existing claimable GROVE or pending auction proceeds for pre-existing shares.
- Sink: share-price assets exclude pending reward value until a later report distributes realized proceeds across the enlarged share base.
- Impact: a late depositor can dilute incumbent reward yield and capture part of value accrued before entry.
- Validation gap: build a two-depositor economic PoC through reward realization and profit unlock; confirm the inherited strategy's deposit/report ordering and policy treatment.

## CAN-007 — Same-block staking supply changes can manipulate the APR denominator

- Affected locations: `src/periphery/GroveCompounderAprOracle.sol:109-132`, especially `111-125`; `src/interfaces/IStaking.sol:13-25`.
- Source: permissionless staking and withdrawal can change the live global staking `totalSupply` around an APR-dependent transaction.
- Closest control: the oracle adjusts supply only for the allocator-provided strategy `_delta`; it neither snapshots nor averages unrelated supply changes.
- Sink: instantaneous global `totalSupply` is the APR denominator.
- Impact: temporary supply expansion can suppress APR and removal can inflate it or trigger the cap, potentially denying or misdirecting downstream allocation.
- Validation gap: reproduce same-block stake/read/withdraw behavior, quantify required capital against deployed supply, and demonstrate a concrete consumer decision path.

## CAN-008 — Active reward auction can make later strategy reports revert

- Affected locations: `src/GroveCompounder.sol:84-118`, especially `107-109`; `src/GroveCompounder.sol:174-180`; directly relied-on auction implementation `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-520`.
- Source: a prior report has already kicked an auction for the reward token, or a public caller donates dust and pre-kicks a permissionless configured auction, while enough new rewards accrue for a report during the active interval.
- Closest control: the strategy checks only auction address and reward threshold before transferring and calling `kick`; it does not check whether that token's auction is already active.
- Sink: the pinned auction implementation rejects a second kick while the token auction remains active, reverting the whole report.
- Impact: keeper reports, reward recognition, and maintenance can be unavailable until the auction becomes inactive; the token transfer reverts atomically, so direct loss is not established.
- Validation gap: reproduce both the ordinary two-report sequence and permissionless donation/pre-kick griefing; confirm deployed kick permissions and quantify cadence, threshold, and auction-duration impact.

## CAN-009 — Oversized exact-input quote is reinterpreted as exact-output mode

- Affected locations: `src/libraries/UniswapV3SwapSimulator.sol:23-46`, especially the unsigned-to-signed conversion around line 37.
- Source: a downstream caller supplies `amountIn >= 2^255` to the exported library API.
- Closest control: no explicit `amountIn <= type(int256).max` check precedes the conversion.
- Sink: the converted negative value makes the simulator core select exact-output rather than exact-input semantics.
- Impact: a downstream integration can receive a semantically invalid quote or revert, potentially mispricing or under-protecting a transaction.
- Validation gap: the allowlisted first-party caller uses fixed `1e18`, so centralized validation must determine whether any directly relied-on deployed caller exposes attacker-controlled oversized input; absent that path this candidate should close as unreachable in scope.
