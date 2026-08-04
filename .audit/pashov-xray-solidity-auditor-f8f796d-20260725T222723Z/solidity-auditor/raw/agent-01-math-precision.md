# Math / Precision Lane Raw Output

## Mandatory mental-tool trace

[Feynman: GroveCompounder] This contract receives USDS from the shared strategy machinery, parks it in the Sky staking program, collects GROVE rewards, and turns those rewards back into USDS either through an auction or through a GROVE-to-USDC trade followed by the PSM. Its own accounting is deliberately simple: staked USDS plus idle USDS.

[Feynman: GroveCompounder.constructor] The deployment binds the strategy to the USDS returned by the fixed PSM wrapper, confirms that Sky accepts the same token, learns the reward token, grants the two spending permissions needed for staking and conversion, and chooses default sale thresholds and the 1% GROVE/USDC market.

[Inversion: GroveCompounder.constructor] (1) Deploy while staking reports paused; deployment stops. (2) Make the PSM's USDS differ from the staking token; deployment stops. (3) Leave the auction address empty while the default sale mode is auction; deployment succeeds and later profitable reports can stop at the missing-auction check.

[Feynman: balanceOfAsset] This reports how much idle USDS the strategy itself currently holds.

[Feynman: balanceOfStake] This reports how much USDS the external staking program credits to the strategy.

[Feynman: balanceOfRewards] This reports how much GROVE is currently sitting in the strategy.

[Feynman: claimableRewards] This asks the staking program how much GROVE the strategy has earned but not yet collected.

[Feynman: _deployFunds] This sends a requested amount of idle USDS into the staking program and attaches the configured referral number.

[Feynman: _freeFunds] This asks the staking program to return a requested amount of USDS.

[Feynman: _harvestAndReport] This collects GROVE, sells it when its raw balance is above the configured threshold, puts idle USDS back into staking unless shutdown is active, and finally reports staked plus idle USDS as the strategy's assets. The direct-sale branch values no output itself; it accepts whatever the inherited trade returns and then converts the entire USDC balance through the PSM.

[Socratic: src/GroveCompounder.sol:94-109 — why?] Why is a raw GROVE threshold used to decide when to sell while the direct path later converts the entire raw USDC balance, and what unit guarantees that every threshold comparison is about the same token?

[Inversion: _harvestAndReport] (1) Accumulate exactly 5,000e18 GROVE so the strict greater-than test leaves it unsold. (2) Select auction mode with the deployment-default zero auction and accumulate 5,000e18+1 GROVE so reporting stops. (3) Select the direct route while the PSM fee becomes nonzero so reporting stops before any reward conversion.

[Feynman: _emergencyWithdraw] This limits an emergency request to the amount actually staked and asks Sky to return that much.

[Feynman: availableDepositLimit] This refuses new deposits while Sky is paused and otherwise preserves the inherited deposit limit.

[Feynman: _min] This returns the smaller of two whole-number amounts.

[Feynman: claimRewards] This lets management collect the strategy's accrued GROVE without selling it.

[Feynman: _claimRewards] This asks Sky to transfer all currently earned rewards to the strategy.

[Feynman: kickAuction] This lets a keeper collect GROVE when appropriate, inspect the entire balance of any requested non-USDS token, and send that balance to the configured auction only when it exceeds a threshold. The fuzzy point is that the threshold is always read from the GROVE entry even when the inspected token is not GROVE.

[Socratic: src/GroveCompounder.sol:169 — why?] Why does an arbitrary token's raw balance compare against `minAmountToSell[REWARDS_TOKEN]` instead of a threshold denominated in that arbitrary token?

[Inversion: kickAuction] (1) Ask to auction 10,000 USDC, whose 1e10 raw units remain below the default 5e21 GROVE-unit threshold. (2) Ask to auction an asset with 24 decimals, for which the same raw threshold represents only 0.005 token. (3) Ask to auction USDS itself; the later principal-token check stops the transfer.

[Feynman: _kickAuction] This rejects USDS, requires a configured auction, sends the entire requested token amount there, and asks the auction to begin selling it.

[Feynman: setMinAmountToSell] This lets management replace the GROVE sale threshold, expressed in GROVE's smallest units.

[Feynman: setUniV3Fees] This lets management choose the fee-tier number the strategy will use for GROVE/USDC trades.

[Feynman: setAuction] This lets management choose an auction only if it promises to return proceeds to this strategy in USDS; clearing the address is allowed only after auction mode is disabled.

[Inversion: setAuction] (1) Supply zero while auction mode is still active; the change stops. (2) Supply an auction that returns proceeds elsewhere; the change stops. (3) Supply an auction that wants a non-USDS token; the change stops.

[Feynman: setUseAuction] This lets management choose the sale route and refuses to select auctions unless an auction address already exists.

[Feynman: setReferral] This lets management replace the small referral number passed into future stakes.

[Feynman: ISwapRouterWithFactory] This extends the trade-router description with a way to ask which factory lists its pools.

[Feynman: ISwapRouterWithFactory.factory] This returns the factory address that maps token pairs and fee tiers to pools.

[Feynman: UniswapV3SwapSimulator] This library estimates the output of a Uniswap V3 trade by reading the live pool and replaying the pool's step-by-step price movement without transferring tokens.

[Feynman: simulateExactInputSingle] This finds the requested pool, chooses trade direction from token ordering, treats the supplied input as a positive signed amount, replays the swap to the caller's price boundary or the protocol boundary, and returns the output-side amount as a positive whole number.

[Socratic: src/libraries/UniswapV3SwapSimulator.sol:41 — why?] Why is an unrestricted 256-bit input reinterpreted as a signed 256-bit amount when values above 2^255-1 change sign and therefore change the quoted trade from exact-input to exact-output?

[Inversion: simulateExactInputSingle] (1) Pass 0 and reach the simulator's nonzero guard. (2) Pass 2^255 so the signed interpretation becomes -2^255 and reverses quote semantics. (3) Choose a missing fee-tier pool so the first pool-state read fails.

[Feynman: getPool] This asks the router's factory for the pool corresponding to the two tokens and fee tier.

[Feynman: Simulate] This library mirrors the arithmetic a Uniswap V3 pool uses to walk prices, ticks, and active liquidity for a hypothetical trade.

[Feynman: simulateSwap] This starts from the pool's current price, tick, fee, spacing, and active depth; repeatedly spends the remaining input across the next price segment; updates active depth at initialized boundaries; and returns the input and output amounts that the real pool math would calculate.

[Socratic: src/libraries/UniswapV3SwapSimulatorCore.sol:128-140 — why?] Why are signed remaining amounts updated without checks? Because the copied swap-step routine guarantees each exact-input step consumes no more than remains, while the signed conversion itself rejects outputs above the signed maximum.

[Inversion: simulateSwap] (1) Supply zero and hit the amount guard. (2) Supply a boundary on the wrong side of the live price and hit the price-limit guard. (3) Cross an initialized negative-liquidity tick and test whether subtracting its magnitude can exceed the current active depth; the checked depth update stops inconsistent pool state.

[Feynman: nextInitializedTickWithinOneWord] This searches the current 256-tick word in the requested direction, finds the nearest flagged boundary when one exists, or returns that word's edge when none exists.

[Socratic: src/libraries/UniswapV3SwapSimulatorCore.sol:159 — why?] Why is one subtracted after dividing a negative tick with a remainder? Because signed division rounds toward zero, while tick-word lookup needs the lower whole spacing interval.

[Inversion: nextInitializedTickWithinOneWord] (1) Use a negative tick not divisible by spacing and verify the explicit decrement reaches the lower interval. (2) Put the current position at bit 255 and verify the leftward mask becomes all ones without overflowing. (3) Search beyond the minimum or maximum protocol tick and rely on the caller's clamp before price conversion.

[Feynman: tickBitmapPosition] This splits a compressed tick into a signed word number and a wrapping position from zero to 255 inside that word.

[Feynman: GroveCompounderAprOracle] This contract estimates annual GROVE yield in USDS terms by combining Sky's global emission rate and total stake with either a simulated V3 sale price or a selected V4 spot price.

[Feynman: _onlyManagement] This allows an oracle configuration change only from the currently recorded manager.

[Feynman: GroveCompounderAprOracle.constructor] This makes the deployer manager and seeds four candidate V4 pool identifiers, all oriented with USDC first and GROVE second.

[Feynman: aprAfterDebtChange] This reads Sky's total stake and reward flow, returns zero after rewards finish, obtains a live GROVE price, adds or subtracts a hypothetical USDS debt change from the global stake, divides annual USDS-denominated rewards by that adjusted stake, and refuses results above 50%.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:130 — why?] Why is the annual numerator multiplied in plain 256-bit arithmetic before dividing by assets? Under realistic USDS supply and the 50% cap a successful value is far below overflow, so overflow occurs only on already-invalid extreme oracle inputs; it is not an extraction path here.

[Inversion: aprAfterDebtChange] (1) Pass a negative delta larger than global stake and make the subtraction stop. (2) Pass the minimum signed integer and make negation stop. (3) Manipulate the live GROVE spot price while leaving adjusted assets nonzero, then keep the computed APR below 50% so both arithmetic guards accept it.

[Feynman: setManagement] This transfers sole configuration authority to a nonzero replacement address.

[Feynman: setUniV3Fee] This changes the V3 fee tier only if the fixed factory currently lists a GROVE/USDC pool for it.

[Feynman: setUniV4Pool] This replaces all fallback candidates with one manager-chosen pool identifier and a manager-supplied token orientation.

[Feynman: setUniV4Pools] This hands a manager-supplied list of pool identifiers and orientations to the shared list replacement routine.

[Feynman: addUniV4Pool] This appends one nonzero pool identifier if that identifier is not already listed.

[Feynman: removeUniV4Pool] This removes a chosen candidate by replacing it with the last candidate, while refusing to remove the final remaining pool.

[Feynman: uniV3Pool] This reports the factory-listed V3 pool for the currently selected fee tier.

[Feynman: uniV4PoolCount] This reports how many V4 fallback candidates are configured.

[Feynman: uniV4Pool] This reports one configured candidate's identifier and stored token orientation.

[Feynman: groveUsdcV4PoolId] This reports the first configured V4 pool identifier for compatibility with older callers.

[Feynman: v4GroveIsToken0] This reports whether the first configured pool is recorded as having GROVE first.

[Feynman: bestUniV4Pool] This runs fallback selection and returns the chosen pool's identity, orientation, and raw active depth without its price.

[Feynman: selectedUniV4Pool] This runs fallback selection and returns the chosen pool's identity, orientation, raw active depth, and calculated GROVE price.

[Feynman: _grovePrice] This prefers a live V3 quote when the V3 pool passes two raw-balance gates; if V3 is missing, shallow, or cannot be simulated, it returns the selected V4 spot quote; if neither route yields a positive result, it stops.

[Inversion: _grovePrice] (1) Leave 1,000 USDC out of active range while placing only the minimum active V3 depth at a manipulated spot. (2) Make V3 unusable so the code falls back to V4. (3) Leave only one V4 candidate above its raw depth threshold so that candidate becomes its own median and deviation reference.

[Feynman: _v3PoolHasUsableLiquidity] This calls a V3 pool usable when its current active depth is at least 1e12 and its total USDC balance is at least 1,000 USDC; it does not prove that the USDC balance is active near the current price or that moving the price is expensive.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:239-245 — why?] Why should 1e12 raw liquidity plus a total token balance imply manipulation resistance when Uniswap liquidity is a square-root-price coefficient and out-of-range balances do not support the current price?

[Inversion: _v3PoolHasUsableLiquidity] (1) Keep 1,000 USDC in an out-of-range position and place 1e12 active liquidity at the manipulated tick. (2) Flash-add active liquidity, read the quote, then remove it in one transaction. (3) Move the spot immediately before an on-chain consumer reads the oracle; neither gate remembers an earlier price.

[Feynman: _v4GrovePrice] This converts one GROVE, expressed with 18 decimal places, into raw USDC using the pool's square-root spot price and then adds twelve decimal places so the result looks like an 18-decimal USDS price.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:247-253 — why?] Why is a spot conversion multiplied by 1e12? Because GROVE and USDS use 18 decimal places while USDC uses 6, so one raw USDC unit must become 1e12 units in the returned 18-decimal price.

[Feynman: _selectedV4Pool] This reads every configured pool, keeps pools whose raw active depth is at least 1e12 and whose spot price is positive, computes the median of only those survivors, rejects survivors more than 10% from that median, and chooses the greatest raw active depth among the remainder. If only one pool survives, its distance from its own median is exactly zero.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:307-335 — why?] Why does a candidate set configured with four entries remain acceptable when three entries have no usable liquidity, leaving one public spot market to authenticate itself?

[Inversion: _selectedV4Pool] (1) Make three of four pools fail the 1e12 raw depth threshold so the remaining pool is its own median. (2) Temporarily move that pool's square-root price and add enough active depth to remain above 1e12. (3) With two survivors, move both together so their midpoint and both 10% checks follow the manipulated prices.

[Feynman: _medianPrice] This sorts the surviving whole-number prices, returns the middle price for an odd count, and returns the lower middle plus half the gap for an even count, rounding a half-unit downward.

[Inversion: _medianPrice] (1) Use one quote so the median equals that quote. (2) Use two attacker-controlled quotes so their midpoint follows them. (3) Place even-count middle quotes far apart so every quote can fall outside 10% and make selection return no pool.

[Feynman: _withinV4PriceDeviation] This measures the absolute whole-number price difference and accepts it when it is no more than 10% of the reference price, with the allowed difference rounded down.

[Inversion: _withinV4PriceDeviation] (1) Use a quote equal to its reference so deviation is zero. (2) Place a quote exactly at the rounded 10% boundary so it passes. (3) Quantize a low USDC price to 1e12 steps and test values immediately around the rounded boundary.

[Feynman: _setUniV4Pools] This replaces the candidate list with a nonempty manager-supplied list after checking matching lengths, nonzero identifiers, and no duplicate identifiers.

[Feynman: _hasUniV4Pool] This scans the candidate list and reports whether a given identifier already appears.

[Feynman: _uniV3Pool] This resolves the V3 pool belonging to the currently stored fee tier.

[Feynman: _uniV3PoolForFee] This asks the router's factory for the fixed GROVE/USDC pair at a requested fee tier.

[Feynman: _quoteToken1ForToken0] This squares the pool's square-root price and multiplies it by one token0 amount to obtain token1 units, changing fixed-point form above the point where a direct square would no longer fit. It always rounds the result down.

[Inversion: _quoteToken1ForToken0] (1) Use the largest square root that still fits the direct-square branch. (2) Use the next value and compare continuity across the Q192-to-Q128 branch. (3) Use the protocol maximum square root and verify the later 1e12 decimal scaling remains below the whole-number limit.

[Feynman: _quoteToken0ForToken1] This squares the pool's square-root price and divides one token1 amount by that ratio to obtain token0 units, changing fixed-point form when a direct square would be too large. It rounds the result down in raw USDC units before the caller adds twelve decimal places.

[Inversion: _quoteToken0ForToken1] (1) Use a square root of one and observe that a non-pool value could make the later 1e12 multiplication overflow. (2) Use the genuine protocol minimum square root and verify the scaled result still fits. (3) Use a GROVE price below one micro-USDC so the raw USDC quote rounds to zero and the pool is discarded.

## Structured output

FINDING | contract: GroveCompounderAprOracle | function: _selectedV4Pool | bug_class: spot-price-manipulation | group_key: GroveCompounderAprOracle | _selectedV4Pool | spot-price-manipulation
path: attacker swaps the only qualifying configured V4 GROVE/USDC pool immediately before an oracle read → the attacker-controlled `sqrtPriceX96` is converted directly into `price` → `quoteCount == 1` makes `medianPrice == price` and `_withinV4PriceDeviation` sees zero deviation → `aprAfterDebtChange` returns the manipulated APR to its consumer
proof: At Ethereum block 25,612,594, the preferred V3 pool reports active liquidity 0 and holds only 71 raw USDC, so it fails both usability gates. The four default V4 pool IDs report liquidity `[0, 2,234,678,351,511,442, 0, 0]`; only pool `0x9fe7...441f` exceeds `MIN_REWARD_POOL_LIQUIDITY = 1e12`. Its `sqrtPriceX96` is 693,136,446,531,199,880,837,452,956,973,944,644, so the code computes `floor(1e18 * 2^192 / sqrtPriceX96^2) = 13,065` raw USDC and returns price `13,065 * 1e12 = 13,065,000,000,000,000`. With observed `rewardRate = 38,844,495,180,111,618,467` and `assets = 209,216,803,145,709,085,130,056,726`, APR is `76,497,799,217,654,500` (7.6498%). If a swap moves the live square root down by `sqrt(1.1)` to 660,879,671,010,126,892,483,917,157,627,753,782, the same code returns 14,371 raw USDC and APR `84,144,651,554,298,723` (8.4145%); because this sole survivor is its own median, deviation remains exactly 0 and every first-party check passes. At the observed price, even the minimum accepted liquidity of 1e12 represents only about 0.00558 USDC of constant-range token0 depth for a 10% price increase (`L * (sqrt(1.1)-1) / (sqrtPriceX96/2^96)`), illustrating that the raw threshold is not an economic manipulation bound.
description: The V4 fallback treats a single surviving public spot pool as a fully corroborated median, allowing a swap to control the GROVE price and any APR below the 50% cap.
fix: Require a minimum number of independently liquid agreeing sources and use a time-weighted/manipulation-resistant price (with depth measured in normalized notional value) instead of accepting a one-pool spot median.

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: decimal-threshold-mismatch | group_key: GroveCompounder | kickAuction | decimal-threshold-mismatch
code_smells: For every `_token != REWARDS_TOKEN`, the function reads that token's raw balance but compares it against `minAmountToSell[REWARDS_TOKEN]`; the default threshold is 5,000e18 = 5e21 raw GROVE units, so even 10,000 USDC is only 10,000e6 = 1e10 raw units and silently fails the comparison, while a 24-decimal token crosses the same threshold at only 0.005 token.
description: The arbitrary-token auction branch mixes token units and can leave low-decimal ancillary balances unsellable through the keeper path, but no recurring non-GROVE token source or permissionless profit path was established and management can temporarily change the GROVE threshold.

LEAD | contract: UniswapV3SwapSimulator | function: simulateExactInputSingle | bug_class: signed-cast-semantic-flip | group_key: UniswapV3SwapSimulator | simulateExactInputSingle | signed-cast-semantic-flip
code_smells: `params.amountIn` is an unrestricted `uint256` but is converted directly to `int256`; `amountIn = 2^255` becomes `-2^255`, making `simulateSwap` set `exactInput = false` and interpret an advertised exact-input quote as an exact-output quote.
description: The generic quote helper has incorrect semantics above the signed maximum, but the only in-scope caller hardcodes `amountIn = 1e18`, so no in-scope value-impacting path was found.
