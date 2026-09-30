# Math Precision Lane

[Feynman: GroveCompounder] This contract keeps USDS deposited in the Sky staking contract, collects GROVE rewards, and either sends those rewards to an auction or swaps them to USDC and then USDS. The money-moving accounting is mostly "how much USDS is staked plus how much USDS is sitting here."
[Feynman: GroveCompounder.constructor] It checks the staking system is usable, confirms the staking token is the same USDS asset, remembers the reward token, approves the staking and PSM contracts, and configures GROVE-to-USDC selling.
[Feynman: balanceOfAsset] It reports how much unstaked USDS the strategy currently holds.
[Feynman: balanceOfStake] It reports how much USDS the staking contract says belongs to the strategy.
[Feynman: balanceOfRewards] It reports how many GROVE reward tokens are sitting in the strategy.
[Feynman: claimableRewards] It asks the staking contract how many GROVE rewards the strategy has earned but not yet collected.
[Feynman: _deployFunds] It sends newly available USDS into the staking contract.
[Feynman: _freeFunds] It pulls USDS back out of the staking contract.
[Feynman: _harvestAndReport] It collects rewards, sells or auctions them only above the configured threshold, restakes meaningful USDS idle balance, and reports staked plus idle USDS as total assets.
[Inversion: _harvestAndReport] 1. Set rewards exactly equal to `minAmountToSell[REWARDS_TOKEN]` so the strict `>` guard leaves them unsold. 2. Leave exactly `DUST` USDS idle so it is counted but not staked. 3. Force the UniV3 path while the PSM fee is nonzero and confirm it reverts before accepting a fee-bearing conversion.
[Socratic: src/GroveCompounder.sol:113 - why?] Why is idle USDS staked only when `balance > DUST`? The implicit belief is that leaving at most 1 USDS idle is acceptable dust and is still counted in total assets.
[Feynman: _emergencyWithdraw] It withdraws no more than the strategy actually has staked, even if a larger amount is requested.
[Feynman: availableDepositLimit] It closes deposits when staking is paused; otherwise it uses the inherited deposit limit rules.
[Feynman: _min] It returns the smaller of two numbers.
[Feynman: claimRewards] It lets management collect pending GROVE rewards into the strategy.
[Feynman: _claimRewards] It asks the staking contract to pay out pending rewards.
[Feynman: kickAuction] It lets a keeper collect reward tokens if needed, measures the chosen token balance, and sends that token to the configured auction only if the balance is above the reward-sale threshold.
[Socratic: src/GroveCompounder.sol:169 - why?] Why does the threshold always read `minAmountToSell[REWARDS_TOKEN]` even when `_token` is not the reward token? The implicit belief is that this function is practically used for the reward token, while non-reward tokens are only incidental recovery cases.
[Inversion: kickAuction] 1. Call with the asset token and rely on `_kickAuction` to reject it. 2. Call with a non-reward token whose decimals make the reward threshold inappropriate. 3. Call with a reward balance exactly equal to the threshold and observe no auction is kicked.
[Feynman: _kickAuction] It refuses to auction USDS, checks that an auction is configured, moves the chosen token there, and starts the auction.
[Feynman: setMinAmountToSell] It lets management change the minimum GROVE amount worth selling.
[Feynman: setUniV3Fees] It lets management change which UniV3 fee tier is used for GROVE-to-USDC quotes and swaps.
[Feynman: setAuction] It lets management choose an auction, but only one that sends proceeds back to this strategy and wants USDS.
[Feynman: setUseAuction] It lets management choose auction selling or UniV3 selling, while requiring an auction to exist before auction mode is enabled.
[Feynman: setReferral] It lets management change the referral code passed to staking deposits.

[Feynman: GroveCompounderAprOracle] This contract estimates the annual return from staking USDS for GROVE rewards. It reads the staking reward rate, prices one GROVE in USDS terms from UniV3 or UniV4, adjusts the staked-asset denominator for a proposed debt change, and returns an APR scaled to 1e18.
[Feynman: GroveCompounderAprOracle.constructor] It sets the initial manager and seeds four default UniV4 pool candidates, all configured as USDC token0 and GROVE token1.
[Feynman: aprAfterDebtChange] It reads total staked USDS and GROVE paid per second, returns zero if rewards have ended, prices GROVE, adjusts total staked assets by the proposed change, divides yearly reward value by adjusted assets, and rejects APRs above 50%.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:122 - why?] Why subtract a negative debt change without an explicit bound first? The implicit belief is that callers only ask about withdrawals no larger than assets represented in staking.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:131 - why?] Why is there no extra division by 1e18? Because reward amount is in GROVE wei, price is USDS wei per 1 GROVE, and assets are USDS wei, leaving a 1e18 APR ratio.
[Inversion: aprAfterDebtChange] 1. Pass `_delta = -int256(assets + 1)` to force the checked subtraction to revert. 2. Pass `_delta = type(int256).min` to test signed negation overflow. 3. Use tiny adjusted assets with nonzero rewards to ensure the 50% cap rejects the result.
[Feynman: setManagement] It lets the current manager hand control to a nonzero new manager.
[Feynman: setUniV3Fee] It lets management choose a UniV3 fee tier only if a GROVE/USDC pool exists for that tier.
[Feynman: setUniV4Pool] It replaces the whole UniV4 candidate list with one nonzero pool id and its token direction.
[Feynman: setUniV4Pools] It replaces the whole UniV4 candidate list with a provided nonempty, same-length, duplicate-free set.
[Feynman: addUniV4Pool] It adds one nonzero, not-yet-configured UniV4 pool candidate.
[Feynman: removeUniV4Pool] It removes one UniV4 pool candidate while ensuring at least one remains configured.
[Feynman: uniV3Pool] It reports the current UniV3 pool for the configured fee tier.
[Feynman: uniV4PoolCount] It reports how many UniV4 candidate pools are configured.
[Feynman: uniV4Pool] It reports one configured UniV4 pool id and whether GROVE is token0 in that pool.
[Feynman: groveUsdcV4PoolId] It reports the first configured UniV4 pool id for backward-compatible callers.
[Feynman: v4GroveIsToken0] It reports the first configured UniV4 pool direction for backward-compatible callers.
[Feynman: bestUniV4Pool] It reports the selected UniV4 pool and liquidity without exposing its price.
[Feynman: selectedUniV4Pool] It reports the selected UniV4 pool, liquidity, and price.
[Feynman: _grovePrice] It first tries to quote selling exactly one GROVE through a usable UniV3 pool, scales the USDC result to 18 decimals, and otherwise falls back to the selected UniV4 spot price.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:228 - why?] Why multiply UniV3 output by `1e12`? The implicit belief is fixed USDC has 6 decimals while APR accounting wants an 18-decimal USDS price.
[Inversion: _grovePrice] 1. Make the V3 pool fail the liquidity or USDC-balance gate and force V4 fallback. 2. Make the V3 simulation return zero and confirm it does not accept a zero price. 3. Push both V3 and V4 to unusable states and confirm the oracle reverts rather than returning a misleading APR.
[Feynman: _v3PoolHasUsableLiquidity] It checks the configured UniV3 pool exists, has enough active liquidity, and holds at least 1,000 USDC.
[Feynman: _v4GrovePrice] It turns a UniV4 square-root price into an 18-decimal USDS price for one GROVE, using the configured token direction to choose the direct or inverse quote.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:249 - why?] Why scale the direct V4 quote by `1e12` after quoting one 18-decimal token? Because the quote is in 6-decimal USDC units and must be represented like 18-decimal USDS.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:252 - why?] Why use the inverse quote when GROVE is not token0? Because the pool price is token1 per token0, while the oracle needs token0 USDC per token1 GROVE.
[Feynman: _selectedV4Pool] It gathers usable V4 pool quotes, finds their median price, ignores quotes more than 10% away from that median, and chooses the most liquid remaining pool.
[Inversion: _selectedV4Pool] 1. Configure one extreme-price pool and confirm median deviation rejects it when other pools anchor the median. 2. Configure only unusable pools and confirm the caller receives no selected pool. 3. Configure two close prices with different liquidity and confirm the larger-liquidity pool wins.
[Feynman: _medianPrice] It copies prices, sorts them from low to high, and returns the middle price or the average of the two middle prices.
[Feynman: _withinV4PriceDeviation] It measures absolute distance from the reference price and allows only prices within 10%.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:335 - why?] Why use `FullMath.mulDiv` for a simple basis-point threshold? The implicit belief is that even price-threshold multiplication should not overflow before division.
[Feynman: _setUniV4Pools] It validates the replacement pool list, rejects zero ids and duplicates, then stores the new candidates.
[Feynman: _hasUniV4Pool] It searches the configured candidate list for a pool id.
[Feynman: _uniV3Pool] It reports the pool for the currently configured UniV3 fee.
[Feynman: _uniV3PoolForFee] It asks the UniV3 factory for the GROVE/USDC pool at a specific fee tier.
[Feynman: _quoteToken1ForToken0] It quotes how much token1 one receives for a token0 amount using the square-root price, switching formulas to avoid overflow at large prices.
[Feynman: _quoteToken0ForToken1] It quotes how much token0 one receives for a token1 amount using the square-root price, switching formulas to avoid overflow at large prices.
[Inversion: _quoteToken0ForToken1/_quoteToken1ForToken0] 1. Use the smallest nonzero square-root price and verify division-by-zero is avoided by the upstream zero check. 2. Use prices around the `uint128` branch boundary and compare direct versus high-price formulas. 3. Use tiny output prices and confirm zero quotes are rejected by `_selectedV4Pool`.

No FINDING or LEAD items identified for this lane.

## Rejected / Notes

- `src/GroveCompounder.sol:111-117` leaves balances `<= DUST` unstaked, but those idle USDS remain in the strategy and are included in `_totalAssets`; this is an intentional dust threshold, not a rounding loss or extraction path.
- `src/GroveCompounder.sol:169` uses the reward-token sale threshold even when `kickAuction()` is called for another token. That can make non-reward token recovery awkward for tokens with different decimals, but the strategy's asset is rejected at `src/GroveCompounder.sol:175`, unsupported auctions revert atomically through `Auction(_auction).kick(_token)` at `src/GroveCompounder.sol:179`, and no in-scope user funds are misaccounted.
- `src/periphery/GroveCompounderAprOracle.sol:121-124` can revert for invalid extreme `_delta` values, including a negative delta larger than total staked assets, but this is checked-arithmetic rejection of an impossible debt-change query rather than an exploitable rounding direction. No source-backed in-scope state-changing path passes arbitrary unbounded deltas into the oracle.
- `src/periphery/GroveCompounderAprOracle.sol:228`, `src/periphery/GroveCompounderAprOracle.sol:249`, and `src/periphery/GroveCompounderAprOracle.sol:252` hardcode the `1e12` USDC-to-18-decimal scale factor. The token constants are fixed to GROVE, USDS, and mainnet USDC at `src/periphery/GroveCompounderAprOracle.sol:37-43`, so this is not a variable-decimal mismatch in the scoped deployment.
- `src/periphery/GroveCompounderAprOracle.sol:307-335` sorts V4 prices, averages the two middle values with floor rounding, and floors the 10% deviation threshold. The rounding error is at most one wei of 18-decimal price and only affects quote selection at an exact boundary; I did not find a concrete extraction or misaccounting path.
- `src/periphery/GroveCompounderAprOracle.sol:374-391` uses the standard split formula with `FullMath.mulDiv` for both direct and inverse square-root-price quotes, avoiding the intermediate-overflow class that would exist with plain `sqrtPriceX96 * sqrtPriceX96 * amount / Q192` across the full `uint160` range.

Reviewed surfaces: strategy reward-sale thresholds, USDS dust restaking, total-asset summation, emergency withdrawal min logic, APR signed-delta adjustment, yearly reward-value scaling, UniV3 USDC-to-USDS scale conversion, UniV4 direct/inverse quote math, V4 median/deviation filtering, and overflow-prone multiplication/division sites.
