# First-Principles Lane

Validated FINDING blocks: none.

Primary surfaces reviewed:
- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

## Mental-tool trace

[Feynman: GroveCompounder] This contract accepts USDS, places it into the fixed Sky staking contract, collects GROVE rewards, and turns those rewards back into USDS either by sending them to an auction or by selling them through the configured Grove/USDC route and the PSM wrapper. Its accounting answer is only "USDS I have staked plus USDS I currently hold"; rewards not yet turned into USDS are outside that answer.
[Feynman: GroveCompounder.constructor] At creation, it checks the staking system is usable, confirms the staked token is the same USDS asset the strategy will use, remembers the reward token, grants the staking contract and PSM wrapper spending permission, and sets the default reward-sale parameters.
[Feynman: balanceOfAsset] This reports how much loose USDS is sitting in the strategy.
[Feynman: balanceOfStake] This reports how much USDS the staking contract says the strategy has deposited.
[Feynman: balanceOfRewards] This reports how much already-claimed GROVE is sitting in the strategy.
[Feynman: claimableRewards] This asks the staking contract how much GROVE the strategy could claim right now.
[Feynman: _deployFunds] This hands newly received USDS to the staking contract using the current referral code.
[Feynman: _freeFunds] This asks the staking contract to return a requested amount of USDS.
[Feynman: _harvestAndReport] This claims GROVE, decides whether enough GROVE exists to sell, either sells it for USDS or sends it to the auction, stakes any meaningful loose USDS if the strategy is still active, and then reports only staked USDS plus loose USDS.
[Socratic: src/GroveCompounder.sol:117 - why?] Why does the final asset answer omit both `STAKING.earned(address(this))` and claimed GROVE unless it has already become USDS? The implicit belief is that value should only enter share pricing after a report/sale boundary, which means a depositor can arrive before that boundary.
[Inversion: _harvestAndReport] 1) Deposit while `claimableRewards()` is high but before the keeper report. 2) Let the report claim and sell/kick rewards after the new shares exist. 3) Stay until the resulting profit unlocks, then redeem shares that were minted before the old reward value was priced.
[Feynman: _emergencyWithdraw] This pulls back at most the amount currently staked so shutdown or emergency handling can move funds out of the staking contract.
[Feynman: availableDepositLimit] This closes deposits while staking is paused, otherwise it defers to the strategy's open-list rules.
[Inversion: availableDepositLimit] 1) Try depositing when staking pauses between preview and deposit. 2) Try depositing through an allowed receiver while global deposits are closed. 3) Try depositing before rewards are reported so the limit check passes while reward value remains unpriced.
[Feynman: _min] This chooses the smaller of two numbers.
[Feynman: claimRewards] This lets management pull the strategy's pending GROVE into the strategy.
[Feynman: _claimRewards] This asks the staking contract to send owed GROVE to the strategy.
[Feynman: kickAuction] This lets a keeper move a token balance from the strategy into the auction, claiming fresh GROVE first when the token is the reward token.
[Socratic: src/GroveCompounder.sol:169 - why?] Why is every token's kick threshold compared to the reward-token threshold? The implicit belief is that this path is practically only for GROVE even though the function accepts any non-asset token.
[Feynman: _kickAuction] This refuses to auction USDS, requires an auction address, moves the token balance to that auction, and starts that token's sale there.
[Inversion: _kickAuction] 1) Send reward tokens directly to the auction before a kick so the auction snapshots more than the strategy transferred. 2) Try a non-reward token enabled in the auction but with a different unit scale than GROVE. 3) Try a zero auction address while auction mode is still enabled.
[Feynman: setMinAmountToSell] This lets management change how much GROVE must build up before the strategy tries to sell it.
[Feynman: setUniV3Fees] This lets management choose the Grove/USDC fee tier used by the direct sale route.
[Feynman: setAuction] This lets management choose the auction contract, after checking that auction sends USDS proceeds back to this strategy.
[Inversion: setAuction] 1) Set a zero auction while auction mode is still on. 2) Set an auction whose receiver is someone else. 3) Set an auction that wants a token other than USDS.
[Feynman: setUseAuction] This lets management choose between delayed auction sales and immediate Grove-to-USDS sales.
[Feynman: setReferral] This lets management change the referral number sent with future stakes.

[Feynman: GroveCompounderAprOracle] This contract estimates the staking APR by reading the global staked USDS amount and GROVE emission speed, pricing one GROVE in USDS, applying a requested debt change, and rejecting outputs above a 50% APR sanity cap.
[Feynman: _onlyManagement] This rejects callers other than the stored management address.
[Feynman: GroveCompounderAprOracle.constructor] This records the deployer as management and installs four default Grove/USDC v4 pool candidates.
[Feynman: aprAfterDebtChange] This reads the staking system's total USDS and GROVE-per-second speed, returns zero if the reward period has ended, gets a current GROVE price, adjusts the total USDS by the requested increase or decrease, and returns the yearly reward value divided by the adjusted USDS total.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:118 - why?] Why is a token price required before checking whether `rewardRate` is zero? The implicit belief is that the reward period being active implies reward value exists.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:121 - why?] Why does a negative debt change subtract without a floor? The implicit belief is that callers will never ask about removing more USDS than exists in the global staking total.
[Inversion: aprAfterDebtChange] 1) Ask with a negative change equal to the full staking supply. 2) Move the Grove/USDC spot price just before the call while keeping the pool above the liquidity checks. 3) Query while rewards are zero but the reward period has not technically ended and pricing is unavailable.
[Feynman: setManagement] This moves management to a nonzero new address.
[Feynman: setUniV3Fee] This lets management choose a Grove/USDC v3 fee tier if the real v3 factory says such a pool exists.
[Feynman: setUniV4Pool] This replaces all fallback v4 pools with one nonzero pool identifier and its Grove side.
[Feynman: setUniV4Pools] This replaces all fallback v4 pools with a nonempty duplicate-free list.
[Feynman: addUniV4Pool] This adds one new nonzero fallback pool that is not already configured.
[Feynman: removeUniV4Pool] This removes one fallback pool while keeping at least one configured.
[Feynman: uniV3Pool] This reports the current v3 pool for the chosen fee tier.
[Feynman: uniV4PoolCount] This reports how many fallback v4 pools are configured.
[Feynman: uniV4Pool] This reports one configured fallback v4 pool and which side Grove is on.
[Feynman: groveUsdcV4PoolId] This reports the first configured v4 pool identifier.
[Feynman: v4GroveIsToken0] This reports whether Grove is the first token in the first configured v4 pool.
[Feynman: bestUniV4Pool] This reports the selected v4 pool and its liquidity without returning the price.
[Feynman: selectedUniV4Pool] This reports the selected v4 pool, its liquidity, and its computed price.
[Feynman: _grovePrice] This first tries the v3 Grove/USDC pool if it passes minimal balance checks, returning that spot sale quote immediately; only if that path is unusable does it ask the v4 fallback selector.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:212 - why?] Why does a usable v3 pool bypass every v4 pool and any cross-check? The implicit belief is that minimum liquidity plus a USDC balance floor makes the current v3 spot quote safe enough.
[Inversion: _grovePrice] 1) Push the v3 spot price up but below the APR cap. 2) Push the v3 spot price down to suppress APR. 3) Keep v3 barely above the liquidity and USDC thresholds so v4 median pricing is never consulted.
[Feynman: _v3PoolHasUsableLiquidity] This accepts the v3 pool if it exists, has enough active pool liquidity, and holds at least 1,000 USDC.
[Feynman: _v4GrovePrice] This turns a v4 square-root price into a USDS-per-GROVE number, choosing the direction from the configured Grove side.
[Feynman: _selectedV4Pool] This gathers usable v4 pool quotes, computes their middle price, and picks the highest-liquidity quote that is close enough to that middle price.
[Inversion: _selectedV4Pool] 1) Manipulate a majority of configured v4 pool prices so the median moves. 2) Make a single large-liquidity pool sit within 10% of a shifted median. 3) Split two valid pools far enough apart that neither sits near their average.
[Feynman: _medianPrice] This sorts collected prices and returns the middle one, or the average of the two middle prices.
[Feynman: _withinV4PriceDeviation] This checks whether a price is within 10% of a reference price.
[Feynman: _setUniV4Pools] This deletes the old pool list, rejects empty/mismatched/duplicate entries, and stores the new list.
[Feynman: _hasUniV4Pool] This scans the stored v4 pool list for a pool identifier.
[Feynman: _uniV3Pool] This reports the v3 pool for the stored fee tier.
[Feynman: _uniV3PoolForFee] This asks the real v3 factory for the Grove/USDC pool at a given fee tier.
[Feynman: _quoteToken1ForToken0] This computes how much token1 one unit amount of token0 is worth at the given price.
[Feynman: _quoteToken0ForToken1] This computes how much token0 one unit amount of token1 is worth at the given price.

## LEADs

LEAD | contract: GroveCompounder | function: _harvestAndReport | bug_class: report-boundary-reward-dilution | group_key: GroveCompounder | _harvestAndReport | report-boundary-reward-dilution
code_smells: `claimableRewards()` exposes pending GROVE at `src/GroveCompounder.sol:70-71`, but `_harvestAndReport()` only prices rewards after `_claimRewards()` and sale/kick at `src/GroveCompounder.sol:89-108`, then reports only `balanceOfStake() + balanceOfAsset()` at `src/GroveCompounder.sol:111-117`. The scoped strategy does not override the base live-asset estimate, so deposits accrue against `lastTotalAssets` via `BaseStrategy._strategyTotalAssets()` at `lib/tokenized-strategy/src/BaseStrategy.sol:237-244`; deposits call `_accrue()` and mint shares before adding only the new deposited assets at `lib/tokenized-strategy/src/TokenizedStrategy.sol:522-540` and `lib/tokenized-strategy/src/TokenizedStrategy.sol:1114`.
description: A depositor who can enter while rewards are accrued but before the keeper report can receive shares priced without those rewards, then share in the eventual reported/auction-settled profit after it unlocks.
trace: Example with zero fees: existing holders have 100 shares against `lastTotalAssets = 100 USDS`, while `STAKING.earned(address(this))` is worth 10 USDS but unreported. An attacker deposits 100 USDS before report, so `_convertToShares` mints 100 shares against the 100-accounted-asset base, then `lastTotalAssets` becomes 200. If direct-sale mode is used, the keeper report claims and converts the 10 USDS-equivalent reward and reports 210 total assets; if auction mode is used, the first report kicks rewards and a later report realizes the 10 USDS proceeds. Profit locking delays withdrawal value at `lib/tokenized-strategy/src/TokenizedStrategy.sol:1436-1464`, but after unlock the attacker owns half of the 210 assets and can redeem 100 shares for about 105 USDS, capturing about 5 USDS of rewards accrued before entry.
remaining_verification: Confirm production deposit openness/whitelist policy, keeper/report timing, and whether the intended deployment accepts this as a Yearn report-boundary accounting tradeoff.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: spot-price-assumption | group_key: GroveCompounderAprOracle | _grovePrice | spot-price-assumption
code_smells: `_grovePrice()` returns the v3 simulated one-GROVE spot sale quote as soon as `_v3PoolHasUsableLiquidity()` passes at `src/periphery/GroveCompounderAprOracle.sol:211-229`; the usability check only requires pool existence, active liquidity, and a 1,000 USDC pool balance at `src/periphery/GroveCompounderAprOracle.sol:239-245`. The v4 median fallback at `src/periphery/GroveCompounderAprOracle.sol:232-236` and `src/periphery/GroveCompounderAprOracle.sol:255-304` is skipped whenever the v3 quote returns a positive number, even if v4 prices disagree.
description: The APR can be moved by temporarily moving the v3 Grove/USDC spot price while keeping the pool above the minimal liquidity/balance gates, because the oracle does not use a TWAP or cross-check v3 against the v4 pool set.
trace: If the honest Grove price is 0.025 USDS and a given staking state implies a 5% APR, moving the v3 one-GROVE quote to 0.050 USDC makes `_grovePrice()` return `0.050e18` and doubles `aprAfterDebtChange()` at `src/periphery/GroveCompounderAprOracle.sol:130-132` to about 10%, as long as the result remains below `MAX_EXPECTED_APR` at `src/periphery/GroveCompounderAprOracle.sol:75` and `src/periphery/GroveCompounderAprOracle.sol:132`. Moving the spot quote downward similarly suppresses APR; neither case consults the configured v4 median while v3 remains "usable."
remaining_verification: Confirm the exact on-chain consumer of `aprAfterDebtChange()` and whether an attacker can profitably pair pool manipulation with that consumer's debt/allocation action in the same block.

## Rejected / Notes

- `src/GroveCompounder.sol:100` passes `0` as the direct Uniswap sale minimum. This is a real slippage/MEV exposure only when management disables the default auction route, and the run instructions exclude generic standard MEV tradeoffs, so I did not promote it separately.
- `src/GroveCompounder.sol:169` uses the reward-token minimum for non-reward token auction kicks. This can make odd-token rescue awkward because units may not match GROVE, but I did not find a source-backed value-loss path: the auction must have the token enabled and proceeds are paid back to the strategy.
- `src/periphery/GroveCompounderAprOracle.sol:121-128` reverts for negative deltas that reduce adjusted staking assets to zero or below. I treated this as an invalid-query boundary unless a consumer is shown to pass such deltas during normal operation.
- `src/GroveCompounder.sol:98` checks the PSM fee before direct reward sale. A fee flip before the transaction makes the report revert rather than silently accepting a fee; I did not identify a bypass inside the scoped code.
