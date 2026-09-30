# Lane 8 — Asymmetry raw audit stream

[Feynman: GroveCompounder]
This contract takes USDS entrusted by the surrounding Yearn strategy, places that USDS into the Sky staking program, collects GROVE rewards, and converts those rewards back into USDS. It has two sale routes: transfer rewards to an auction for later settlement, or sell immediately through Uniswap into USDC and then turn every USDC held by the strategy into USDS through the PSM wrapper. The surrounding Yearn runtime, rather than this file, decides when users deposit or withdraw and when accounting is reported.

[Feynman: constructor]
At deployment, the contract checks that Sky staking is active and accepts the same USDS token that the PSM wrapper pays out. It grants the staking contract unlimited access to USDS and the PSM wrapper unlimited access to USDC, then configures a GROVE-to-USDC Uniswap fee and a GROVE sale floor. A fuzzy point is that it chooses auction mode immediately but does not install an auction at the same time.

[Feynman: balanceOfAsset]
This returns the amount of idle USDS held directly by the strategy.

[Feynman: balanceOfStake]
This returns the amount of USDS stake credited to the strategy by Sky staking.

[Feynman: balanceOfRewards]
This returns the amount of GROVE held directly by the strategy.

[Feynman: claimableRewards]
This returns the amount of GROVE Sky currently says the strategy can collect.

[Feynman: _deployFunds]
This hands a specified amount of idle USDS to Sky staking and attaches the current referral code.

[Feynman: _freeFunds]
This asks Sky staking to return a specified amount of USDS to the strategy.

[Feynman: _harvestAndReport]
This collects pending GROVE, sells it only when the held amount is strictly above the configured floor, and chooses either immediate Uniswap-plus-PSM conversion or an auction transfer. It then stakes idle USDS when the strategy is active and the idle balance exceeds one USDS, and finally reports direct plus staked USDS as assets. The fuzzy point is that the immediate route settles USDS in the same call while the auction route removes GROVE now and receives USDS only later.

[Inversion: _harvestAndReport]
1. Accumulate exactly the configured minimum GROVE so the strict `>` comparison leaves it unsold. 2. Force the direct route while the PSM charges a nonzero fee so every otherwise-valid report reverts. 3. Force the auction route before an auction address is configured so the first above-threshold reward report reverts.

[Feynman: _emergencyWithdraw]
This caps the requested rescue amount at the recorded stake and asks Sky to return that much USDS.

[Feynman: availableDepositLimit]
This refuses new deposits whenever Sky reports itself paused; otherwise it uses the surrounding strategy runtime's normal deposit limit.

[Inversion: availableDepositLimit]
1. Pause Sky after deposits already exist, making new deposits stop while withdrawals still depend on Sky behavior. 2. Toggle Sky pause state between a user's preview and execution. 3. Make Sky's pause getter succeed while its stake call still rejects deposits for another external reason.

[Feynman: _min]
This returns whichever of two numbers is smaller.

[Feynman: claimRewards]
This lets management collect the strategy's pending GROVE without selling it or updating strategy accounting.

[Feynman: _claimRewards]
This asks Sky staking to send all currently earned rewards to the strategy.

[Feynman: kickAuction]
This lets a keeper transfer the entire held balance of a chosen non-principal token to the configured auction when auction mode is active and the balance passes a sale floor. GROVE is first collected from Sky; other tokens are not. The fuzzy point is that the chosen token can be arbitrary but the comparison always uses the GROVE-specific floor.

[Socratic: src/GroveCompounder.sol:169 — why?]
Why is every `_token` balance compared against `minAmountToSell[REWARDS_TOKEN]` rather than the chosen token's threshold? The implicit belief is that every manually auctioned token shares GROVE's denomination and desired dust floor, although the public parameter explicitly permits non-GROVE tokens.

[Inversion: kickAuction]
1. Pass a six-decimal non-asset token whose economically meaningful balance can never exceed a 5,000e18 GROVE-denominated floor. 2. Pass an 18-decimal airdropped token worth nearly nothing whose numeric balance exceeds the GROVE floor and force a wasteful auction. 3. Pass GROVE at exactly the floor so the keeper cannot kick because the comparison is strict.

[Feynman: _kickAuction]
This rejects USDS, requires a configured auction, transfers the chosen token's full balance to it, and tells the auction to start selling that token.

[Inversion: _kickAuction]
1. Use a token with unusual transfer behavior so the auction receives less than the supplied balance. 2. Use a configured auction whose receiver or wanted token changed after setup. 3. Reenter through a malicious token transfer or auction call, subject to the trusted configuration boundary.

[Feynman: setMinAmountToSell]
This lets management replace the GROVE sale floor used by automated harvesting and manual auction kicks.

[Feynman: setUniV3Fees]
This lets management replace the Uniswap fee tier used for GROVE-to-USDC execution.

[Feynman: setAuction]
This lets management install an auction only if it promises to send proceeds to this strategy and pay them in USDS. Clearing the auction is allowed only after auction mode is turned off.

[Inversion: setAuction]
1. Install a contract whose `receiver` and `want` answers are correct during setup but whose later behavior changes. 2. Front-run the management change by manipulating external auction state if its getters are mutable. 3. Attempt to clear the address while auction mode remains selected; this correctly reverts.

[Feynman: setUseAuction]
This lets management choose between delayed auction settlement and immediate Uniswap-plus-PSM settlement, but refuses to select auctions if none is installed.

[Inversion: setUseAuction]
1. Select direct swaps immediately before the PSM begins charging a fee. 2. Select auction mode with a contract that passed setup checks but has since changed behavior. 3. Switch modes while rewards or an earlier auction remain unsettled.

[Feynman: setReferral]
This lets management replace the referral number sent with future stakes; it does not alter already staked funds.

## Paired-surface work plan — GroveCompounder

- `_deployFunds` (`src/GroveCompounder.sol:76`) ↔ `_freeFunds` (`:80`): external stake versus external withdrawal; neither writes first-party storage.
- ordinary `_freeFunds` (`:80`) ↔ `_emergencyWithdraw` (`:120`): the emergency side caps to live stake before using the same withdrawal helper.
- direct sale branch (`:96-106`) ↔ auction branch (`:107-109`): direct route validates PSM fee and synchronously realizes USDS; auction route validates auction configuration downstream and settles asynchronously.
- automated reward sale in `_harvestAndReport` (`:84-118`) ↔ keeper `kickAuction` (`:158-171`): automated path only sells GROVE; keeper path accepts arbitrary non-USDS tokens.
- `claimRewards` (`:143`) ↔ reward collection in harvest/kick (`:88`, `:162`): manual management path collects only, while operational paths may immediately sell.
- `setAuction` (`:209`) ↔ `setUseAuction` (`:223`): clearing and enabling checks mirror after deployment, but declaration defaults begin in the otherwise-forbidden `useAuction=true, auction=0` state.
- `availableDepositLimit` pause branch (`:125`) ↔ withdrawal/emergency paths (`:80`, `:120`): deposits are explicitly stopped by pause state; withdrawals are delegated to external staking behavior.

[Feynman: UniswapV3SwapSimulator]
This library estimates how much output a specified one-pool Uniswap trade would produce, without actually moving tokens. It finds the pool from the router's factory, derives trade direction from token address order, and asks the copied pool-walk logic to replay the trade against current pool data.

[Feynman: simulateExactInputSingle]
This looks up the requested token pair and fee tier, simulates selling the exact stated input amount toward either the caller's price boundary or Uniswap's extreme boundary, and returns the output-side quantity. The supplied recipient, deadline, and minimum output do not affect the estimate because no trade executes.

[Inversion: simulateExactInputSingle]
1. Supply a fee tier whose factory entry is zero so the first pool read reverts. 2. Supply an input above the largest positive signed integer so the signed interpretation changes direction semantics. 3. Use a pool whose current price or tick data changes immediately after this view quote and before the consumer acts.

[Feynman: getPool]
This asks the router which factory it uses and asks that factory for the pool matching two tokens and a fee tier.

## Paired-surface work plan — UniswapV3SwapSimulator

- requested `tokenIn/tokenOut` order ↔ canonical pool token order: direction is inferred by address ordering and the selected result component mirrors it.
- supplied price boundary zero ↔ nonzero: zero maps to the nearest valid extreme; nonzero is passed to the core validator.
- simulator quote parameters ↔ router execution parameters: amount, tokens, fee, and price boundary matter to simulation; recipient, deadline, and minimum output intentionally do not.

[Feynman: Simulate]
This library locally replays Uniswap V3's price movement across initialized price bands and returns the same signed token deltas a pool trade would produce. It reads rather than changes pool state.

[Feynman: simulateSwap]
This starts from a pool's current price, active range, and liquidity, then repeatedly advances toward the next initialized price boundary or the caller's stopping price. At each step it charges the pool fee, consumes input or accumulates the input needed for exact output, changes active liquidity when a boundary is crossed, and finally returns the two token balance changes. The fuzzy points are the unchecked signed updates and the deliberate tick decrement when moving toward lower-priced ranges.

[Socratic: src/libraries/UniswapV3SwapSimulatorCore.sol:109 — why?]
Why are remaining-amount updates unchecked? The implicit belief is that Uniswap's step math and the initial signed amount keep every intermediate delta within the same bounds as the audited upstream pool implementation.

[Inversion: simulateSwap]
1. Start exactly on an initialized lower tick and move token0 to token1 to exercise the `tickNext - 1` branch. 2. Cross a tick whose signed liquidity change removes nearly all active liquidity. 3. Ask for an amount or boundary that consumes all reachable liquidity before consuming the request.

[Feynman: nextInitializedTickWithinOneWord]
This searches the current 256-tick bitmap word in the requested direction, returning either the nearest marked price boundary or that word's edge when none is marked. It rounds negative ticks down before locating the word and bit.

[Inversion: nextInitializedTickWithinOneWord]
1. Use a negative tick that is not divisible by spacing to challenge rounding. 2. Search from bit zero or bit 255 to challenge masks and word transitions. 3. Search with no initialized bit in the word so the computed edge, rather than a marked tick, is returned.

[Feynman: tickBitmapPosition]
This splits a compressed tick number into the signed 256-tick word containing it and the bit within that word.

## Paired-surface work plan — Simulate

- exact-input (`amountSpecified > 0`) ↔ exact-output (`< 0`): remaining amount and calculated amount move in opposite directions, and final token deltas select mirrored tuple positions.
- zero-for-one ↔ one-for-zero: price-bound checks, next-tick search direction, liquidity sign, tick transition, and final tuple orientation must all mirror.
- initialized tick ↔ empty word edge: only initialized boundaries change active liquidity.
- negative nonmultiple tick ↔ nonnegative/multiple tick: only the former receives explicit floor rounding.

[Feynman: GroveCompounderAprOracle]
This contract estimates the annual GROVE reward value per staked USDS. It prefers a simulated sale against one configured Uniswap V3 fee tier when that pool passes basic liquidity checks; otherwise it builds V4 spot-price candidates, filters them around their median, and uses the most liquid surviving candidate. A separate management address can replace both V3 and V4 source configuration.

[Feynman: constructor]
This appoints the deployer as configuration manager and installs four preselected V4 pool identifiers, all interpreted as USDC first and GROVE second.

[Feynman: aprAfterDebtChange]
This reads the staking program's total USDS, reward speed, and reward end time, obtains a GROVE-to-USDS price, adjusts total stake by a hypothetical signed change, and annualizes reward value over the adjusted stake. It returns zero after rewards end and rejects a zero denominator or an answer above 50% APR. The fuzzy point is that expired rewards bypass price-source health while active rewards must obtain a usable price even if reward speed is zero.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:115 — why?]
Why does an expired program return before price resolution while an active program with `rewardRate == 0` still requires live market liquidity? The implicit belief is that active-period zero rewards should inherit price-source liveness requirements even though the mathematical APR is unconditionally zero.

[Inversion: aprAfterDebtChange]
1. Supply a negative delta larger than total stake so subtraction reverts. 2. Supply a positive delta large enough to overflow total stake. 3. Keep the reward period active but set reward rate to zero while all price sources are unusable, causing a zero-APR query to revert.

[Feynman: setManagement]
This immediately transfers configuration authority to a nonzero address, without a separate acceptance step.

[Feynman: setUniV3Fee]
This switches the preferred V3 fee tier only if the factory currently lists a pool for GROVE and USDC; it does not check that the pool meets the runtime liquidity and USDC-balance gates.

[Feynman: setUniV4Pool]
This discards every V4 candidate and stores one nonzero pool identifier plus the manager-provided statement of which side is GROVE.

[Feynman: setUniV4Pools]
This forwards complete replacement of the V4 candidate list to the shared bulk routine.

[Feynman: addUniV4Pool]
This adds one nonzero, not-already-listed V4 pool identifier and a manager-provided token orientation.

[Feynman: removeUniV4Pool]
This removes one indexed candidate while ensuring at least one remains; it fills the gap with the prior last entry, so order can change.

[Feynman: uniV3Pool]
This exposes the V3 pool currently resolved from the chosen fee tier.

[Feynman: uniV4PoolCount]
This exposes how many V4 pricing candidates are stored.

[Feynman: uniV4Pool]
This exposes one candidate's identifier and configured GROVE side.

[Feynman: groveUsdcV4PoolId]
This compatibility getter exposes the first candidate's identifier even though candidate selection may use another entry.

[Feynman: v4GroveIsToken0]
This compatibility getter exposes the first candidate's orientation even though candidate selection may use another entry.

[Feynman: bestUniV4Pool]
This exposes the candidate selected by median filtering and liquidity preference, without its price.

[Feynman: selectedUniV4Pool]
This exposes the same selected candidate together with its price.

[Feynman: _grovePrice]
This uses a simulated sale of one GROVE into USDC if the configured V3 pool passes minimum active-liquidity and USDC-balance checks and the simulation returns nonzero output. If any of that fails, it uses the selected V4 spot price; if neither route yields a price, it reverts. The fuzzy point is that the fallback route lacks the V3 route's USDC-balance check and obtains a spot ratio without simulating the sale size used by V3.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:218 — why?]
Why does V3 estimate the executable output of selling one GROVE while V4 converts the instantaneous square-root price for one GROVE without walking liquidity? The implicit belief is that the V4 liquidity floor makes spot price equally representative of executable one-GROVE output, despite the routes enforcing different reserve and price-impact evidence.

[Inversion: _grovePrice]
1. Drain the V3 pool's USDC below 1,000 USDC to force fallback even if V3 still has substantial GROVE-side liquidity. 2. Manipulate enough V4 candidates so their median moves and an attacker-controlled price survives the 10% filter. 3. Make V3 simulation revert while keeping the shallow V4 liquidity value barely at 1e12.

[Feynman: _v3PoolHasUsableLiquidity]
This accepts the preferred V3 pool only if it exists, its currently active liquidity reaches 1e12, and it physically holds at least 1,000 USDC.

[Inversion: _v3PoolHasUsableLiquidity]
1. Put exactly 1e12 active liquidity and exactly 1,000 USDC in the pool to pass both inclusive thresholds. 2. Donate 1,000 USDC to a pool whose active liquidity is cheaply positioned or one-sided. 3. Create adequate-looking active liquidity that still yields extreme impact for the one-GROVE direction.

[Feynman: _v4GrovePrice]
This turns a V4 pool's instantaneous price into the USDC value of one GROVE and scales the six-decimal USDC amount to eighteen decimals, using the configured statement of which pool side is GROVE.

[Feynman: _selectedV4Pool]
This gathers all configured V4 candidates whose active liquidity reaches 1e12 and whose price is nonzero, computes the median of those prices, ignores candidates more than 10% from that median, and returns the highest-liquidity survivor. External read failures are silently skipped. The fuzzy point is that with one or two usable candidates, each candidate helps define the reference that is meant to validate it.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:280 — why?]
Why is a median used even when only one or two pools produce quotes? The implicit belief is that a candidate set of size one or two provides independent corroboration, although one quote trivially equals its own median and two attacker-shifted quotes can center the allowed band on themselves.

[Inversion: _selectedV4Pool]
1. Leave only one usable configured pool so its own price becomes the median and always passes deviation. 2. With two usable pools, move both prices together so their average validates them. 3. Give the more manipulated in-band pool slightly more reported liquidity so selection prefers it.

[Feynman: _medianPrice]
This copies candidate prices, sorts them from low to high, returns the middle price for an odd count, and returns the floor of the average of the two middle prices for an even count.

[Inversion: _medianPrice]
1. Provide one quote so it certifies itself. 2. Provide two far-apart quotes so their average can be more than 10% from both, yielding no selection. 3. Provide even middle prices near the largest integer to challenge subtraction and averaging; subtraction-first avoids addition overflow.

[Feynman: _withinV4PriceDeviation]
This accepts a price when its absolute difference from the reference is no more than one tenth of the reference.

[Inversion: _withinV4PriceDeviation]
1. Place a quote exactly on the 10% boundary because equality passes. 2. Use a tiny reference so integer rounding makes the permitted difference zero. 3. Make the attacker price become the reference itself through a one-candidate set.

[Feynman: _setUniV4Pools]
This replaces the entire candidate list with matching nonempty arrays, rejecting zero identifiers and duplicate identifiers.

[Inversion: _setUniV4Pools]
1. Supply one candidate, which is valid configuration but eliminates cross-pool corroboration. 2. Supply correct identifiers with deliberately wrong GROVE-side flags. 3. Supply a very large unique list to make price queries expensive or exceed practical gas limits, subject to trusted management.

[Feynman: _hasUniV4Pool]
This checks whether a pool identifier already appears in the current candidate list.

[Feynman: _uniV3Pool]
This resolves the preferred V3 pool using the currently configured fee tier.

[Feynman: _uniV3PoolForFee]
This gets the router's factory and asks it for the GROVE/USDC pool at a chosen fee tier.

[Feynman: _quoteToken1ForToken0]
This computes how many units of token1 correspond to a specified token0 amount at a square-root price, choosing one of two arithmetic arrangements to avoid overflow.

[Feynman: _quoteToken0ForToken1]
This computes how many units of token0 correspond to a specified token1 amount at a square-root price, choosing the reciprocal arithmetic arrangement that avoids overflow.

## Paired-surface work plan — GroveCompounderAprOracle

- expired-reward branch (`src/periphery/GroveCompounderAprOracle.sol:115`) ↔ active-reward branch (`:119-132`): expired returns zero before price lookup and delta validation; active zero-rate rewards still require both.
- negative delta (`:122-124`) ↔ nonnegative delta (`:125-126`): subtraction can fail when withdrawal exceeds global stake; addition can fail at integer maximum, and both converge on denominator checks.
- V3 preferred quote (`:211-229`, `:235-245`) ↔ V4 fallback quote (`:232-233`, `:247-305`): V3 requires a pool, raw liquidity, 1,000 USDC balance, and a simulated one-GROVE output; V4 requires raw liquidity and a nonzero spot price, then relative agreement among available candidates.
- single V4 setter (`:147-152`) ↔ bulk setter (`:338-354`) ↔ incremental add (`:158-164`): all ensure nonzero identifiers; bulk/add ensure uniqueness, while single replacement is unique by construction.
- add (`:158-164`) ↔ remove (`:166-175`): add preserves order; remove uses swap-and-pop and guarantees a nonempty list.
- `bestUniV4Pool` (`:193-195`) ↔ `selectedUniV4Pool` (`:197-204`): same selection walk; only the latter exposes selected price.
- `_quoteToken1ForToken0` (`:374-382`) ↔ `_quoteToken0ForToken1` (`:384-392`): multiplication and reciprocal paths mirror across small/large square-root values.

## Targeted dependency and test-context checks

[Feynman: BaseSwapper]
This dependency owns one sale-floor number per token so inheriting strategies can decide whether a particular token balance is worth selling.

[Feynman: BaseSwapper._setMinAmountToSell]
This records the sale floor under the exact token address supplied by the inheriting contract.

[Feynman: UniswapV3Swapper]
This dependency executes exact-input or exact-output Uniswap V3 trades, choosing one hop when either side is the configured base token and two hops otherwise.

[Feynman: UniswapV3Swapper._setUniFees]
This records the same fee tier in both token-order directions.

[Feynman: UniswapV3Swapper._swapFrom]
This sells an exact input only when that input reaches the sale floor stored for the input token, grants the router enough allowance, and forwards the caller's minimum-output protection. In GroveCompounder the supplied minimum output is zero.

[Inversion: UniswapV3Swapper._swapFrom]
1. Use an input exactly at its floor, which this helper accepts even though GroveCompounder's caller excludes equality. 2. Configure a nonexistent fee tier so the router call fails. 3. Set minimum output to zero and manipulate the pool immediately before execution.

[Feynman: UniswapV3Swapper._swapTo]
This buys an exact output while limiting input consumption, provided the maximum possible input reaches the input token's sale floor.

[Feynman: Auction._kick]
This requires that the selected sale token was enabled and has no currently active sale, measures the auction contract's entire token balance, and records that balance as the new sale inventory. A failed enablement or active-auction check rolls back GroveCompounder's preceding transfer in the same transaction.

[Inversion: Auction._kick]
1. Kick a token that was never enabled. 2. Kick while an earlier sale of the same token is active. 3. Transfer a token whose balance accounting does not match the transferred amount.

[Feynman: OracleTest]
This fork-based test contract exercises oracle administration, configured V4 selection, V3-to-V4 fallback, the APR cap, and APR movement after hypothetical debt changes. Its single-pool V4 checks deliberately show that one usable candidate is accepted; it contains no manipulation-resistance test.

[Feynman: Setup]
This shared fork setup deploys the strategy, immediately installs and enables an auction, lowers the GROVE sale floor for tests, and exposes helpers that call a V4 pool usable solely when raw active liquidity reaches 1e12. Thus setup masks the constructor's initial auction-address mismatch and mirrors the oracle's V4 gate without adding reserve or execution-quality evidence.

### Storage-variable lifecycle and symmetry diff

- `GroveCompounder.referral`: written at declaration and by `setReferral`; read only by `_deployFunds`. Writer validation is intentionally unrestricted `uint16`; lifecycle is complete.
- `GroveCompounder.auction`: zero by default and written only by `setAuction`; read by `_kickAuction`, `setUseAuction`, and the clearing guard in `setAuction`. Post-deployment writers preserve `useAuction => auction != 0`, but declaration defaults violate that pair.
- `GroveCompounder.useAuction`: true at declaration and written only by `setUseAuction`; read by both harvest branches, keeper `kickAuction`, and `setAuction`. Its initial write is not paired with the nonzero-auction validation enforced by later writes.
- `GroveCompounder.REWARDS_TOKEN`: written once in construction; read by all reward balance, sale, and configuration paths.
- inherited `base`: written to USDC in construction; read by direct swaps, PSM settlement, and fee configuration.
- inherited `minAmountToSell`: only the `REWARDS_TOKEN` slot is written, in construction and `setMinAmountToSell`. Automated sale reads that same slot for GROVE, but keeper `kickAuction(_token)` reads the GROVE slot even when `_token` differs; the token-specific slot expected by `BaseSwapper` is never used for that variant.
- `GroveCompounderAprOracle.management`: written in construction and `setManagement`; read by `onlyManagement`; all later writes reject zero.
- `rewardToBaseUniV3Fee`: written at declaration and by `setUniV3Fee`; read by pool resolution and V3 quoting. The setter checks pool existence while the declaration relies on the hardcoded deployment.
- `v4Pools`: written by construction, single/bulk replacement, add, and swap-and-pop removal; read by legacy first-entry getters and by selection over all entries. All post-construction writers preserve nonempty/nonzero/unique IDs. Legacy getters read entry zero while operational selection can read and return a different entry.
- Both simulator libraries are stateless; their exact-input/exact-output and direction branches only mutate memory mirrors of pool state.

### Side-by-side branch diffs

- Reward sale, direct side: requires `toSwap > GROVE floor`, requires `PSM.tin()==0`, simulates no minimum output at the Grove caller, executes GROVE→USDC, and converts the strategy's full USDC balance synchronously to USDS. Auction side: uses the same GROVE floor, transfers GROVE to the auction, checks nonzero auction and non-USDS token downstream, and receives no USDS synchronously. The delayed accounting is intentional; the zero-slippage direct execution is outside this lane's asymmetry focus.
- Keeper auction, GROVE side: claims pending rewards, reads GROVE balance, compares it with the GROVE floor. Non-GROVE side: does not claim, reads the supplied token balance, but still compares with the GROVE floor. This is a real unit/slot mismatch.
- Oracle, V3 side: requires a factory-listed pool, active liquidity of at least `1e12`, actual pool USDC balance of at least `1_000e6`, and a simulated exact sale of `1e18` GROVE. V4 side: requires only active liquidity of at least `1e12`, a nonzero instantaneous square-root price, and agreement with the median of however many candidates happen to be usable; it never checks executable one-GROVE output or per-pool reserves.
- Oracle, expired reward side: returns zero before price lookup, delta adjustment, or denominator checks. Active side: always performs all of those operations even when `rewardRate == 0`, although the final mathematical APR must be zero.
- V4 candidate loop, failing external getter side: skips the candidate through `catch`. Valid getter but zero-liquidity/zero-price side: skips through `continue`. Valid single-candidate side: uses that candidate to create its own median, so deviation is identically zero.

## Results

FINDING | contract: GroveCompounderAprOracle | function: _grovePrice/_selectedV4Pool | bug_class: manipulable-single-source-v4-fallback | group_key: GroveCompounderAprOracle | _grovePrice | manipulable-single-source-v4-fallback
file: `src/periphery/GroveCompounderAprOracle.sol:211-305`
path: public Uniswap V4 trader → move the only currently usable V4 pool's spot price → consumer calls `aprAfterDebtChange` while V3 is unusable → manipulated spot becomes its own median and determines the reported APR → allocator can be induced to misallocate capital
pair_or_branch: preferred V3 quote versus V4 fallback quote; multiple configured V4 candidates versus one usable candidate
asymmetry: the V3 branch requires both `liquidity >= 1e12` and at least 1,000 USDC held by the pool, then simulates selling one full GROVE; the V4 branch requires only raw `liquidity >= 1e12` and reads `slot0`, and when just one candidate is usable `_medianPrice` returns that same quote so `_withinV4PriceDeviation` always passes with zero deviation.
root_cause: V4 source admission is based on dimensionless active liquidity and self-referential spot-price agreement, with no executable-quote check and no minimum-source quorum.
proof: At Ethereum block 25,612,668, direct StateView reads for the four hardcoded V4 IDs returned liquidity `[0, 2,234,678,351,511,442, 0, 0]`, while the hardcoded V3 pool returned liquidity `0` and only `71` raw USDC units. Therefore `_v3PoolHasUsableLiquidity()` is false, `quoteCount == 1`, `medianPrice == quotes[0].price`, and the sole V4 pool is unconditionally selected. Its observed `sqrtPriceX96 = 693136446531199880837452956973944644` produces price `13,065,000,000,000,000` and the existing fork test returned APR `75,773,445,867,935,289` (7.577%). If a public swap moves that instantaneous square-root price to half while leaving reported liquidity above the very low floor, the reciprocal-square price becomes `52,261,000,000,000,000` and APR becomes `303,099,583,199,706,558` (30.31%), still below `MAX_EXPECTED_APR = 50%`; because it remains the sole quote, deviation remains exactly zero. An attacker can independently keep the gate live by adding a wide-range position with liquidity exactly `1e12`: at the observed price that threshold corresponds to only about `114,303` raw USDC (0.114303 USDC) and `8.7486` GROVE of active-liquidity virtual inventory. In contrast, V3 would need the explicit 1,000-USDC balance evidence and would quote an executable one-GROVE sale rather than accepting `slot0` directly. The live V4 pool's full active liquidity has virtual balances of about 255.43 USDC and 19,550 GROVE at the observed point, illustrating that raw `liquidity` alone is not a dollar-depth guarantee; the pool is publicly swappable and the spot move can be reversed after the consumer observation.
description: The oracle's supposedly corroborated V4 fallback silently degrades to a single manipulable spot quote and applies substantially weaker depth evidence than the V3 path, allowing temporary pool-price manipulation to produce a plausible, under-cap but false APR.
fix: Quote the same exact one-GROVE trade through a V4 quoter/TWAP with explicit impact bounds, require a minimum number of independent usable sources before median filtering, and fall back/revert when quorum is lost rather than allowing one quote to validate itself.

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: wrong-token-sale-threshold | group_key: GroveCompounder | kickAuction | wrong-token-sale-threshold
code_smells: `kickAuction(_token)` explicitly accepts any non-USDS token and reads `ERC20(_token).balanceOf`, but its only threshold check is `rewardsBalance > minAmountToSell[REWARDS_TOKEN]`; `BaseSwapper` stores thresholds per token, and the only public setter can write only the GROVE slot.
pair_or_branch: GROVE branch versus arbitrary-token branch in keeper `kickAuction`
asymmetry: both branches compare against the GROVE-denominated floor even though only one branch's balance is denominated in GROVE.
proof: With the production default floor `5_000e18`, 1,000,000 USDC is represented as `1e12` and fails `1e12 > 5e21`, so a keeper cannot auction even a million accidentally held USDC; conversely, `5_001e18` units of a worthless 18-decimal airdrop pass. `_kickAuction` only excludes USDS and there is no general sweep/recovery function in the strategy runtime found by the targeted dependency search.
description: Non-reward tokens can be permanently impractical to recover through the advertised arbitrary-token auction path, or can be kicked at economically nonsensical amounts, because the wrong token's threshold is used.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: zero-reward-liveness-asymmetry | group_key: GroveCompounderAprOracle | aprAfterDebtChange | zero-reward-liveness-asymmetry
code_smells: an expired reward period returns zero before market-price and delta validation, but an active period with `rewardRate == 0` still calls `_grovePrice`, adjusts `_delta`, and can revert for missing liquidity even though its numerator is provably zero.
pair_or_branch: expired-reward zero-APR branch versus active-but-zero-rate zero-APR branch
asymmetry: only the timestamp-derived zero case bypasses irrelevant price-source liveness; the reward-rate-derived zero case does not.
proof: Set `periodFinish = block.timestamp + 1`, `rewardRate = 0`, and make V3/V4 liquidity unavailable: the active branch reaches `_grovePrice()` and reverts `insufficient pool liquidity`; one second later the otherwise identical call returns `0` at the early timestamp check. No price or denominator can change `0 * SECONDS_PER_YEAR * price / assets` away from zero.
description: A valid zero APR can be unavailable solely because the reward program has not yet expired, creating avoidable oracle-consumer denial of service during zero-emission intervals.

LEAD | contract: GroveCompounder | function: _harvestAndReport | bug_class: staking-pause-redeployment-asymmetry | group_key: GroveCompounder | _harvestAndReport | staking-pause-redeployment-asymmetry
code_smells: `availableDepositLimit` explicitly blocks staking while the external staking contract is paused, but `_harvestAndReport` checks only strategy shutdown before staking any idle USDS above `DUST`; the deployed Sky staking pause is documented/implemented as a stake pause while withdrawals remain available.
pair_or_branch: paused deposit path versus report-time redeployment path
asymmetry: user deposits consult `STAKING.paused()` before reaching `stake`, while report-time redeployment does not.
proof: After an auction settles 100 USDS to the strategy, let Sky set `paused = true` while the strategy itself remains active. `availableDepositLimit` returns zero, yet keeper `report()` reaches `balance = 100e18`, satisfies `balance > DUST`, calls `_deployFunds(100e18)`, and the paused staking call reverts. The report cannot recognize the settled profit until Sky unpauses or management first shuts down the strategy, even though simply retaining the 100 USDS idle would produce correct `_totalAssets`.
description: External staking pause can unnecessarily block reporting and profit recognition because the internal redeposit variant omits the pause guard used by ordinary deposits.

LEAD | contract: GroveCompounderAprOracle | function: groveUsdcV4PoolId/v4GroveIsToken0 | bug_class: stale-compatibility-getter-view | group_key: GroveCompounderAprOracle | groveUsdcV4PoolId | stale-compatibility-getter-view
code_smells: the singularly named compatibility getters always expose `v4Pools[0]`, while `bestUniV4Pool`, `selectedUniV4Pool`, and `_grovePrice` can select any other candidate based on usability and liquidity.
pair_or_branch: legacy first-entry getters versus operational selected-pool getters
asymmetry: the legacy reader exposes configuration slot zero, not the state source actually used for APR.
proof: Configure three candidates A/B/C with valid prices, give A liquidity `3e12`, B `5e12`, and C `4e12`, all inside 10% of their median. `groveUsdcV4PoolId()` reports A while `_selectedV4Pool()` and APR pricing use B. An external monitor or integration that treats the singular getter as the active source validates the wrong pool.
description: Legacy getters can misrepresent the active V4 source to downstream monitoring or integrations; direct on-chain consumer impact was not found in this repository.
