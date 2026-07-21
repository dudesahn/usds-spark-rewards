# Grove USDS Compounder X-Ray + Solidity Auditor Report

Target: `f8f796db93c52432cca0ed26861e94f5aaf20975`

Scope:

- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

Method:

- Ran Pashov x-ray first for orientation only.
- Ran all 12 Pashov Solidity Auditor lanes in two clean waves of six.
- Promoted only source-backed findings and leads.
- Validated the highest-impact accounting candidate with a focused Foundry PoC.

## Summary

| ID | Type | Severity | Title |
|---|---|---:|---|
| G-01 | Finding | Medium | Auction-returned rewards can be diluted by just-in-time deposits before accounting sync |
| G-02 | Finding | Low/Medium conditional | Direct UniV3 reward-sale mode accepts zero minimum output |
| L-01 | Lead | Needs downstream validation | APR oracle prefers V3 spot quote before V4 median checks |
| L-02 | Lead | Needs feasibility validation | V4 fallback median can collapse to one surviving pool |
| L-03 | Lead | Operational | Reports can revert when a reward auction is still active |
| L-04 | Lead | Deployment-dependent | Accepted auction receiver can change after `setAuction()` validation |

## Confirmed Findings

### G-01: Auction-returned rewards can be diluted by just-in-time deposits before accounting sync

Contracts: `src/GroveCompounder.sol`, Yearn Tokenized Strategy dependency, Yearn Auction dependency.

Severity: Medium.

`GroveCompounder._harvestAndReport()` claims GROVE, kicks it to auction in auction mode, and reports only `balanceOfStake() + balanceOfAsset()` as total assets. Once the auction returns USDS to the strategy receiver, that returned USDS is not reflected in Tokenized Strategy accounting until the next report. Deposits before that next report mint shares from the stale `lastTotalAssets` baseline, while `_deposit()` deploys the full loose USDS balance and increments `lastTotalAssets` only by the depositor's stated `assets`.

Relevant code:

- `src/GroveCompounder.sol:89-109`: claims rewards and sends rewards to auction when `useAuction == true`.
- `src/GroveCompounder.sol:111-117`: reports only idle USDS plus staked USDS.
- `src/GroveCompounder.sol:174-179`: transfers reward token to auction and calls `Auction.kick()`.
- `src/GroveCompounder.sol:209-213`: accepts only auctions whose receiver is the strategy and want is the asset.
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:600-604`: auction settlement pays `want` directly to `receiver`.
- `lib/tokenized-strategy/src/BaseStrategy.sol:237-244`: default `_strategyTotalAssets()` returns `lastTotalAssets()`.
- `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540`: deposit mints shares from current accounting.
- `lib/tokenized-strategy/src/TokenizedStrategy.sol:1108-1114`: deposit deploys full loose balance but adds only `assets` to accounting.
- `lib/tokenized-strategy/src/TokenizedStrategy.sol:1417-1464`: next report locks the newly observed profit across the enlarged supply.

Validated PoC:

`validation/CodexAuctionDilution.t.sol` shows:

1. Incumbent deposits `10_000e18` USDS.
2. Keeper report kicks GROVE to auction with zero profit.
3. `1_000e18` USDS is returned to the strategy, modeling `Auction.take()`.
4. Attacker deposits `10_000e18` USDS before the next report and receives `10_000e18` shares.
5. The deposit stakes the full loose `11_000e18` USDS while adding only `10_000e18` to `lastTotalAssets`.
6. Next report books `1_000e18` profit.
7. After profit unlock, the attacker captures about `500e18` USDS of proceeds generated before entry.

Impact:

Existing shareholders can be diluted out of auction proceeds earned before new capital entered. The issue affects reward/profit allocation, not principal custody, but the extractable amount can approach most of the returned auction proceeds if the just-in-time deposit is large relative to incumbent supply.

Fix direction:

Close or limit deposits while rewards are in an active auction or while auction proceeds are unreported. Also consider overriding `_strategyTotalAssets()` to a read-only live estimate such as `balanceOfStake() + balanceOfAsset()` so returned idle USDS is accrued before minting new shares. A live estimate alone does not fully cover the pre-settlement auction receivable window, so the active-auction deposit gate is the more complete mitigation.

### G-02: Direct UniV3 reward-sale mode accepts zero minimum output

Contracts: `src/GroveCompounder.sol`, Yearn `UniswapV3Swapper`.

Severity: Low/Medium conditional.

This issue is inactive by default because `useAuction = true`, but it becomes active if management switches the strategy to direct UniV3 reward sales with `setUseAuction(false)`.

When direct mode is enabled and rewards exceed the sale floor, `_harvestAndReport()` calls `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)`. The inherited swapper forwards that literal zero as Uniswap's `amountOutMinimum`. A keeper-triggered report can therefore sell all accrued GROVE at a manipulated current spot price, after which the strategy converts whatever USDC it received through the PSM.

Relevant code:

- `src/GroveCompounder.sol:96-105`: direct sale branch, PSM fee guard, `_swapFrom(..., 0)`, and PSM conversion.
- `src/GroveCompounder.sol:224-226`: management can disable auction mode.
- `lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:72-86`: `_minAmountOut` becomes Uniswap `amountOutMinimum`.

Impact:

Shareholders can lose reward upside to sandwich/price manipulation whenever the direct swap path is enabled. The loss is accrued reward value rather than already-reported principal.

Fix direction:

Prefer keeping auction mode as the only reward sale path. If direct swaps remain supported, require a nonzero min-out derived from a manipulation-resistant quote, TWAP, or keeper-supplied value checked against the APR oracle.

## Leads

### L-01: APR oracle prefers V3 spot quote before V4 median checks

Contracts: `src/periphery/GroveCompounderAprOracle.sol`, `src/libraries/UniswapV3SwapSimulator*.sol`.

`_grovePrice()` uses V3 first when `_v3PoolHasUsableLiquidity()` passes, returning the current one-GROVE simulated output immediately. The V3 gate checks only pool existence, active liquidity, and at least `1_000e6` USDC held by the pool. If V3 returns any positive output, the configured V4 pool set and median/deviation filter are skipped entirely.

Relevant code:

- `src/periphery/GroveCompounderAprOracle.sol:211-229`: V3 branch returns before V4 fallback.
- `src/periphery/GroveCompounderAprOracle.sol:239-245`: V3 usability gate.
- `src/periphery/GroveCompounderAprOracle.sol:255-304`: V4 median and liquidity selection.
- `src/libraries/UniswapV3SwapSimulatorCore.sol:69-86`: simulator reads current pool state.

Why it remains a lead:

The oracle itself is view-only in scope. Exploitability depends on the downstream APR consumer and whether an attacker can profitably pair pool manipulation with a debt/allocation decision. Still, this is the most repeated oracle lead across the lanes.

Fix direction:

Compare V3 output against the V4 median when V4 quotes exist, add TWAP/deviation checks, or make V4 multi-pool median the primary source while V3 is only one candidate.

### L-02: V4 fallback median can collapse to one surviving pool

Contract: `src/periphery/GroveCompounderAprOracle.sol`.

`_selectedV4Pool()` silently skips pools with low liquidity, failing StateView calls, zero sqrt price, or zero converted price. If only one configured pool survives, that quote becomes the median and passes the deviation check against itself.

Relevant code:

- `src/periphery/GroveCompounderAprOracle.sol:264-288`: gather and skip quotes.
- `src/periphery/GroveCompounderAprOracle.sol:290-304`: compute median and select most liquid in-band quote.
- `src/periphery/GroveCompounderAprOracle.sol:333-335`: deviation check.

Why it remains a lead:

The source behavior is clear, but feasibility depends on live pool states or an attacker making all but one configured pool unusable. The current design may intentionally prefer liveness with one quote, but that should be an explicit risk choice.

Fix direction:

Require at least two or three valid independent V4 quotes for median validation, or add absolute price/depth sanity bounds for singleton fallback operation.

### L-03: Reports can revert when a reward auction is still active

Contract: `src/GroveCompounder.sol`, Yearn Auction dependency.

In auction mode, `_harvestAndReport()` unconditionally calls `_kickAuction()` whenever newly claimed rewards exceed `minAmountToSell[REWARDS_TOKEN]`. If the previous reward auction is still active, `Auction.kick()` reverts with `too soon`, reverting the entire report.

Relevant code:

- `src/GroveCompounder.sol:107-109`: report kicks auction when rewards exceed threshold.
- `src/GroveCompounder.sol:174-180`: transfer then `Auction.kick()`.
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:507-520`: active-auction guard and new auction initialization.

Why it remains a lead:

The path is keeper/management-triggered and depends on reward accrual crossing the threshold before the current auction expires. It is an availability/keeper coordination issue rather than an unpermissioned exploit.

Fix direction:

Check auction active/kickable state before transferring and kicking. If active, leave rewards in the strategy for a later report or accumulate them through an auction-aware path.

### L-04: Accepted auction receiver can change after `setAuction()` validation

Contract: `src/GroveCompounder.sol`, Yearn Auction dependency.

`setAuction()` validates `receiver() == address(this)` and `want() == address(asset)` only when the auction is configured. The auction dependency allows governance to update `receiver` when no auction is active. If auction governance can diverge from strategy management, a previously accepted auction can later redirect sale proceeds.

Relevant code:

- `src/GroveCompounder.sol:209-216`: one-time receiver/want validation.
- `src/GroveCompounder.sol:174-179`: future kicks trust the stored auction.
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:421-428`: auction receiver setter.
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:600-604`: settlement pays current receiver.

Why it remains a lead:

Deployment governance may be the same trusted management, which would make this a configuration/trust assumption rather than a vulnerability. It should be checked at deployment time.

Fix direction:

Either require the auction governance to be the same trusted authority as the strategy or re-check receiver/want before every kick/take-sensitive flow.

## Rejected / Not Promoted

- Negative APR `_delta` larger than total staking supply reverts by checked arithmetic; this is an invalid view query without an in-scope state-changing exploit.
- Exact `block.timestamp == periodFinish` can report nonzero APR for one timestamp, but exploitability depends on an allocator acting exactly at that boundary.
- `rewardRate == 0` while price sources are unavailable can make an otherwise zero APR query revert, but live staking feasibility was not proven.
- `kickAuction()` compares non-reward tokens against the reward-token threshold; this is awkward recovery behavior but not a proven asset-loss path because the function is keeper-gated, rejects the asset, and unsupported auction tokens revert atomically.

## Verification

- Full fork suite: `forge test -vv --fork-url https://ethereum.publicnode.com` passed 26 tests.
- Focused PoC: `test_jitDepositCapturesUnreportedAuctionProceeds` passed once live and is preserved in `validation/`.
- Current APR observed in the fork test log: `72021778685172846`, approximately 7.20% as a 1e18 APR.
