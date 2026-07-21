# Flow Gap Lane

Scope reviewed: `src/GroveCompounder.sol` and `src/periphery/GroveCompounderAprOracle.sol`.

No validated FINDING blocks.

## Mental-tool trace

[Feynman: GroveCompounder] This contract takes USDS from users through the strategy wrapper, puts that USDS into the Sky staking contract, collects GROVE rewards, and tries to turn those rewards back into more USDS. It can sell rewards either by sending them to an auction or by swapping them through Uniswap and then converting USDC through the PSM wrapper. Its reported value is the USDS still sitting in the contract plus the USDS currently staked.

[Feynman: GroveCompounder.constructor] Deployment checks that the staking system is usable and that the staking token matches the USDS asset. It records the reward token, approves the staking and PSM wrapper contracts, chooses USDC as the intermediate sale token, and installs the default reward-sale threshold and Uniswap fee.

[Feynman: balanceOfAsset] This tells how much loose USDS is currently sitting in the strategy.

[Feynman: balanceOfStake] This tells how much USDS the strategy has placed in the staking contract.

[Feynman: balanceOfRewards] This tells how much unsold GROVE is currently sitting in the strategy.

[Feynman: claimableRewards] This asks the staking contract how much GROVE the strategy could claim right now.

[Feynman: _deployFunds] This sends newly available USDS into the staking contract with the current referral code.

[Feynman: _freeFunds] This pulls USDS back out of the staking contract.

[Feynman: _harvestAndReport] This claims GROVE rewards, optionally sells or auctions them, stakes any loose USDS above the dust threshold, and returns the strategy's current USDS value.

[Socratic: src/GroveCompounder.sol:98 - why?] Why is a zero PSM fee checked before the Uniswap swap rather than right before the PSM conversion? The path assumes the wrapper fee cannot change inside the same report after the swap boundary.

[Socratic: src/GroveCompounder.sol:102 - why?] Why sell the entire USDC balance instead of only the swap output? The implicit belief is that any USDC held by the strategy is accidental or donated value that should become USDS.

[Inversion: _harvestAndReport] 1. Put the strategy in UniV3 mode, move the GROVE/USDC spot price just before report, and let `_swapFrom(..., 0)` accept the bad output. 2. Keep the auction path active while a prior auction is still active, then let new rewards above threshold make `_kickAuction` revert. 3. Leave only dust-sized USDS after reward conversion so it is counted as idle value but not restaked.

[Feynman: _emergencyWithdraw] This withdraws up to the requested amount from staking, capped by what the strategy actually has staked.

[Feynman: availableDepositLimit] This closes deposits while staking is paused and otherwise defers to the strategy wrapper's deposit rules.

[Feynman: _min] This returns the smaller of two numbers.

[Feynman: claimRewards] Management can manually pull the strategy's accrued GROVE out of staking.

[Feynman: _claimRewards] This asks the staking contract to send the strategy its earned GROVE.

[Feynman: kickAuction] A keeper can claim rewards when the requested token is GROVE, or use the current balance for another token, then start an auction if the balance is above the reward threshold.

[Socratic: src/GroveCompounder.sol:169 - why?] Why is every token compared against `minAmountToSell[REWARDS_TOKEN]`? The path assumes this public auction kick function is effectively a reward-token path even though `_token` is arbitrary.

[Feynman: _kickAuction] This refuses to auction USDS, checks that an auction address exists, moves the token to the auction, and starts the auction for that token.

[Inversion: _kickAuction] 1. Pass the asset address and hit the explicit `!asset` guard. 2. Pass a token that the auction has not enabled and rely on the auction call to revert the whole transfer. 3. Pass the reward token while a previous reward auction is active and block the kick with the auction's active-auction check.

[Feynman: setMinAmountToSell] Management changes the minimum GROVE amount worth selling.

[Feynman: setUniV3Fees] Management changes the Uniswap fee tier used for GROVE to USDC reward sales.

[Feynman: setAuction] Management points the strategy at an auction, but only if that auction returns USDS to this strategy; clearing the auction is only allowed while auction mode is off.

[Feynman: setUseAuction] Management chooses auction sales or Uniswap plus PSM sales, and auction mode cannot be turned on without an auction address.

[Feynman: setReferral] Management changes the referral code used when staking.

[Feynman: GroveCompounderAprOracle] This contract estimates the strategy APR by reading the Sky staking reward speed and total staked USDS, pricing one GROVE in USDS through a V3 quote or V4 pool state, and dividing yearly reward value by staking supply.

[Feynman: _onlyManagement] This only lets the stored management address continue.

[Feynman: GroveCompounderAprOracle.constructor] Deployment assigns management to the deployer and installs four default V4 GROVE/USDC pool ids.

[Feynman: aprAfterDebtChange] This reads staking supply and reward speed, returns zero if the reward period is over, prices GROVE, adjusts supply by the requested debt change, and returns the yearly reward value per staked USDS capped at 50%.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:118 - why?] Why is GROVE priced before checking whether `rewardRate` is zero? The path assumes an active reward period means the price is needed, but zero emissions make the APR zero regardless of price.

[Inversion: aprAfterDebtChange] 1. Use a negative `_delta` equal to current supply so the adjusted supply becomes zero after external price reads. 2. Keep V3 liquidity and USDC balance above the gate while moving the V3 spot price to distort the accepted APR. 3. Set the staking state to `rewardRate == 0` and `periodFinish > block.timestamp` while all price sources are unusable, making a zero-APR case revert.

[Feynman: setManagement] Management hands control to a nonzero new management address.

[Feynman: setUniV3Fee] Management selects a V3 fee tier only if a GROVE/USDC pool exists for that tier.

[Feynman: setUniV4Pool] Management replaces the V4 pool list with one nonzero pool id and its token-order flag.

[Feynman: setUniV4Pools] Management replaces the whole V4 pool list through the internal list setter.

[Feynman: addUniV4Pool] Management appends a new nonzero, non-duplicate V4 pool id.

[Feynman: removeUniV4Pool] Management removes one V4 pool by index while keeping at least one pool configured.

[Feynman: uniV3Pool] This returns the V3 pool selected by the current fee tier.

[Feynman: uniV4PoolCount] This returns how many V4 pools are configured.

[Feynman: uniV4Pool] This returns one configured V4 pool id and whether GROVE is the first token for that pool.

[Feynman: groveUsdcV4PoolId] This returns the first configured V4 pool id.

[Feynman: v4GroveIsToken0] This returns the first configured V4 pool's token-order flag.

[Feynman: bestUniV4Pool] This returns the selected V4 pool and its active liquidity.

[Feynman: selectedUniV4Pool] This returns the selected V4 pool, token-order flag, active liquidity, and computed price.

[Feynman: _grovePrice] This first tries a V3 quote for selling one GROVE into USDC when the V3 pool passes shallow liquidity checks. If that does not produce a positive output, it asks the V4 pool selector for a price and otherwise reverts.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:212 - why?] Why should any V3 pool that clears the liquidity and USDC-balance gates suppress all V4 median checks? The implicit belief is that those two gates are enough to trust the current V3 spot quote.

[Inversion: _grovePrice] 1. Keep the V3 pool above `1e12` liquidity and `1_000e6` USDC while moving its spot price so the V3 branch returns before V4. 2. Make the V3 simulation revert and force the oracle into the V4 fallback. 3. Make every price source return zero or fail so the APR query reverts.

[Feynman: _v3PoolHasUsableLiquidity] This checks that the selected V3 pool exists, has at least the configured active liquidity, and holds at least 1,000 USDC.

[Feynman: _v4GrovePrice] This converts a V4 square-root price into a USDC value for one GROVE using the configured token order.

[Feynman: _selectedV4Pool] This collects usable V4 pool prices, computes the median, discards prices more than 10% away from that median, and chooses the highest-liquidity remaining pool.

[Inversion: _selectedV4Pool] 1. Leave only one configured pool with usable liquidity so it becomes both median and selected price. 2. With two usable pools, move one price up to roughly 22% away from the other so both can still sit within 10% of their average median. 3. Put the largest active liquidity on a manipulated pool that remains barely inside the deviation window.

[Feynman: _medianPrice] This copies the collected prices, sorts them, and returns the middle price or the average of the two middle prices.

[Feynman: _withinV4PriceDeviation] This checks whether a price is within 10% of the reference price.

[Feynman: _setUniV4Pools] This replaces the configured V4 pool list after checking nonempty matching arrays, nonzero pool ids, and no duplicates.

[Feynman: _hasUniV4Pool] This scans the configured V4 list for a pool id.

[Feynman: _uniV3Pool] This returns the V3 pool for the current fee.

[Feynman: _uniV3PoolForFee] This asks the V3 factory for the GROVE/USDC pool at a fee tier.

[Feynman: _quoteToken1ForToken0] This computes how much token1 one unit of token0 is worth at a V4 square-root price.

[Feynman: _quoteToken0ForToken1] This computes how much token0 one unit of token1 is worth at a V4 square-root price.

## Leads

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: spot-price-priority-bypasses-median | group_key: GroveCompounderAprOracle | _grovePrice | spot-price-priority-bypasses-median
seam: three-way
trace: external caller -> `aprAfterDebtChange` reads staking supply and reward speed at `src/periphery/GroveCompounderAprOracle.sol:111-118` -> `_grovePrice` checks V3 usability at `src/periphery/GroveCompounderAprOracle.sol:211-212` -> a positive V3 simulator output returns immediately at `src/periphery/GroveCompounderAprOracle.sol:213-229` -> V4 median selection at `src/periphery/GroveCompounderAprOracle.sol:232` and `src/periphery/GroveCompounderAprOracle.sol:255-304` is skipped -> APR is accepted if it remains below the 50% cap at `src/periphery/GroveCompounderAprOracle.sol:131-132`.
violated_principle: The APR oracle should price rewards from a durable market signal because external allocators may treat the returned APR as the strategy's economic yield.
code_smells: The V3 branch uses the current V3 swap simulation for exactly `1e18` GROVE with no TWAP or cross-check, and `_v3PoolHasUsableLiquidity` only requires active liquidity plus `1_000e6` USDC at `src/periphery/GroveCompounderAprOracle.sol:239-245`; any positive V3 quote returns before the configured V4 median/deviation machinery can sanity-check it.
description: A temporarily distorted but still "usable" V3 pool can dominate the oracle price and bypass the V4 fallback's median filter; the remaining unverified piece is the downstream allocator behavior and manipulation cost for the live GROVE/USDC pools.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: zero-reward-price-dependency | group_key: GroveCompounderAprOracle | aprAfterDebtChange | zero-reward-price-dependency
seam: execution x periphery x first-principles
trace: caller -> `aprAfterDebtChange` reads `rewardRate` at `src/periphery/GroveCompounderAprOracle.sol:112` -> if `periodFinish` is still in the future the function continues at `src/periphery/GroveCompounderAprOracle.sol:114-118` -> `_grovePrice` may revert on insufficient V3/V4 liquidity at `src/periphery/GroveCompounderAprOracle.sol:211-236` -> the zero reward-rate multiplication that would produce `oracleApr == 0` at `src/periphery/GroveCompounderAprOracle.sol:131` is never reached.
violated_principle: If no GROVE is emitted per second, the strategy APR is zero and should not depend on external price-source availability.
code_smells: There is no early `if (rewardRate == 0) return 0;` before the periphery price path, so a zero-emission but not-yet-finished reward period can turn a deterministic zero APR into an oracle revert if price liquidity is unavailable.
description: The source path can make a zero-reward APR query fail due to unrelated price-source liveness; the remaining unverified piece is whether the live staking contract can expose `rewardRate == 0` while `periodFinish > block.timestamp`.

## Rejected / Notes

- `GroveCompounder._harvestAndReport` passes `_minAmountOut = 0` into `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` at `src/GroveCompounder.sol:96-105`, then converts the full USDC balance through the PSM wrapper. This is a direct swap-slippage/periphery trail in management-selected UniV3 mode, not a flow-gap-specific item.
- `GroveCompounder.kickAuction` compares every `_token` balance against `minAmountToSell[REWARDS_TOKEN]` at `src/GroveCompounder.sol:158-170`. This is inconsistent for non-reward tokens, but no concrete primary reward-flow impact was established because `_kickAuction` still rejects the asset, requires an auction, and relies on the auction token being enabled at `src/GroveCompounder.sol:174-180`.
- The auction path can make reports revert while a previous reward auction is active, because `_harvestAndReport` calls `_kickAuction` whenever new rewards exceed the threshold at `src/GroveCompounder.sol:107-109`. I treated this as expected auction liveness/keeper coordination rather than a source-backed vulnerability.
