# 🔐 Security Review — Grove USDS Compounder

## Scope & Method

| Item | Value |
|---|---|
| Repository | `dudesahn/usds-spark-rewards` |
| Commit | `f8f796db93c52432cca0ed26861e94f5aaf20975` |
| Review date | 2026-07-25 |
| In-scope contracts | `GroveCompounder`, `GroveCompounderAprOracle`, `UniswapV3SwapSimulator`, `UniswapV3SwapSimulatorCore` |
| Orientation | Fresh x-ray run at the target commit; artifacts were frozen and used only as orientation |
| Discovery | Solidity-auditor, all 12 specialties, two isolated waves of six lanes |
| Validation | Source/dependency traces plus two passing mainnet-fork proofs at fork block 25,612,756 |

The twelve independent lanes emitted 18 raw findings and 35 raw leads. Cross-lane deduplication and the Solidity-auditor execution, reachability, unprivileged-trigger, and material-harm gates reduced them to two validated findings and six validated leads. Findings that depended only on privileged misconfiguration, ordinary MEV, malformed view inputs, or an unproven downstream consumer were rejected or demoted in the validation ledger.

## Findings

### [MEDIUM] Auction callbacks let buyers mint before sale proceeds enter accounting [90]

`GroveCompounder` keeps the inherited report-boundary `_strategyTotalAssets`, so deposits price shares using `lastTotalAssets`. The configured Auction sends GROVE to a buyer and invokes its arbitrary callback before it transfers the buyer's USDS payment to the strategy. A buyer can therefore deposit during that callback, receive shares at the pre-proceeds price, let the Auction pay USDS immediately afterward, and participate in those already-earned proceeds when a later report unlocks them.

The fork proof starts with 1,000,000 USDS from incumbent holders, kicks a 100,000 GROVE auction, and has the buyer deposit another 1,000,000 USDS from `auctionTakeCallback`. The buyer receives 1,000,000 shares while `totalAssets()` still excludes the pending payment; the next report recognizes the payment as profit, and after profit unlock the buyer redeems more than its 1,000,000 USDS deposit. In the illustrative 100,000-USDS-proceeds case from the converged lane trace, the buyer captures roughly 44,776 USDS after the default 10% performance fee, while incumbents lose roughly 44,332 USDS of historical yield.

Relevant code: `src/GroveCompounder.sol:84-118`, `lib/tokenized-strategy/src/BaseStrategy.sol:225-244`, `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540`, and `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:565-604`.

**Impact:** An unprivileged auction buyer can transfer a material fraction of reward proceeds earned by incumbent holders to newly minted shares. The extraction is repeatable for later auctions and scales with both pending proceeds and attacker deposit size.

**Fix:**

- **Option A — pending-auction deposit lock (recommended):** Track auction-pending state from kick through the first report after settlement. Return zero from `availableDepositLimit` and block minting while it is set; clear it only after received proceeds are included in recorded assets.
- **Option B — accounting-atomic settlement:** Route settlement through a strategy hook that records the USDS proceeds before any buyer-controlled callback or share conversion. A live staked-plus-idle `_strategyTotalAssets` override is useful defense-in-depth, but it must explicitly account for TokenizedStrategy's same-block accrual latch; a live view alone does not close every callback ordering.

### [MEDIUM] Permissionless dust auctions can indefinitely block above-threshold reports [90]

The shipped Auction defaults `governanceOnlyKick` to false. Any account can send one wei of GROVE to the configured Auction and call `kick`. When the strategy later holds more than its reward-sale threshold, `_harvestAndReport` transfers those rewards to the already-active Auction and unconditionally calls `kick` again. The Auction reverts with `too soon`, rolling back the entire report.

The fork proof performs this sequence with an arbitrary griefer, confirms the keeper report reverts, advances beyond the one-day auction length, re-kicks the same unsold one-wei balance, and confirms the next report reverts again. The attacker does not need to replenish the dust balance.

Relevant code: `src/GroveCompounder.sol:84-118` and `src/GroveCompounder.sol:174-180`; dependency behavior is at `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:80-82` and `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-522`.

**Impact:** Reports can be delayed indefinitely at negligible token cost. Rewards remain outside recorded assets while the attack persists, and holders who exit before a successful report can forfeit accrued yield.

**Fix:** Query `Auction.isActive(REWARDS_TOKEN)` before transferring or kicking. If active, leave newly accrued GROVE in the strategy and complete the report without attempting a nested kick. Also configure governance-only kicks as defense-in-depth; the strategy-side active-auction handling is still needed for legitimate overlapping reward accrual.

## Findings List

| Severity | Finding | Confidence |
|---|---|---:|
| Medium | Auction callbacks let buyers mint before sale proceeds enter accounting | 90 |
| Medium | Permissionless dust auctions can indefinitely block above-threshold reports | 90 |

No Critical, High, or validated Low-severity findings were identified.

## Leads

The following behaviors are source-backed, but no complete in-scope value-extraction or material-harm path was established. They should be investigated with the production allocator and deployment configuration in scope.

1. **`GroveCompounderAprOracle._grovePrice` — V3 spot price has unconditional priority.** A V3 pool that passes raw liquidity and USDC-balance gates supplies an instantaneous one-GROVE quote and bypasses all V4 comparisons. The USDC gate can be satisfied by donation and neither gate establishes manipulation cost. Missing proof: a state-changing consumer and attacker position that monetizes the corrupted APR.

2. **`GroveCompounderAprOracle._selectedV4Pool` — a singleton V4 quote validates itself.** One surviving quote is its own median, necessarily passes the 10% deviation test, and can win based on raw Uniswap liquidity rather than normalized economic depth. Missing proof: an in-scope consumer that turns same-block quote control into material harm.

3. **`GroveCompounderAprOracle._medianPrice` — even-count medians can reject every pool.** For prices `[1, 2]`, the arithmetic midpoint is `1.5`; each observed price is 33.3% away, so both fail the 10% filter and the oracle returns no pool. The same occurs for `[1, 1, 2, 2]`. Missing proof: a material downstream liveness impact in scope.

4. **`GroveCompounderAprOracle.aprAfterDebtChange` — forecasted debt changes diverge from execution.** The function ignores `_strategy` and applies the full signed delta directly to global staking supply. Actual deposits stake the strategy's existing idle USDS as well, while withdrawals use idle USDS before reducing stake. The one-GROVE quote also does not model threshold-sized bulk sales. Missing proof: the allocator policy and resulting user loss.

5. **`GroveCompounder.kickAuction` — arbitrary-token sales reuse a GROVE-denominated threshold.** Non-GROVE balances are compared to `minAmountToSell[REWARDS_TOKEN]`, mixing token units, and the keeper path accepts any non-asset token enabled by Auction governance. Missing proof: a recurring valuable ancillary-token balance and unprivileged extraction path.

6. **`UniswapV3SwapSimulator.simulateExactInputSingle` — large inputs flip signed semantics.** `uint256 amountIn` is cast directly to `int256`; values above `type(int256).max` become negative and are interpreted by the simulator as exact-output swaps. The only in-scope caller hardcodes `1e18`, so the defect is a latent integration hazard rather than a current exploit.

## Disclaimer

This review is a time-bounded security assessment of the listed source at the exact commit. It does not prove the absence of vulnerabilities, and it does not cover production governance, allocator logic, deployments, or code outside the stated scope except where a dependency was required to validate an in-scope path.
