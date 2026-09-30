# Boundary lane raw output

## Mental-tool trace

[Feynman: GroveCompounder] This component accepts USDS through its inherited vault interface, puts that USDS into the fixed Sky reward program, collects GROVE, and either sends GROVE to an auction or trades it through Uniswap and the PSM. Its accounting deliberately counts only staked and idle USDS; GROVE and USDC are pending conversion inventory, not principal.

[Feynman: GroveCompounder.constructor] Deployment asks the fixed PSM and staking program which tokens they use, refuses a paused or mismatched setup, learns the reward token, grants the fixed staking and PSM contracts spending permission, and configures the default GROVE-to-USDC route. The fuzzy point is that it selects auction mode before any auction has been supplied.

[Socratic: GroveCompounder.sol:22 — why?] Why is auction mode live before `auction` has a usable address? The implicit belief is that management will finish configuration before a profitable report can occur.

[Inversion: GroveCompounder.constructor] (1) Deposit before management calls `setAuction`; (2) let rewards grow to exactly 5,000e18 and then one wei above it; (3) make the first keeper report while `auction == address(0)`.

[Feynman: balanceOfAsset] It asks USDS how many loose tokens the strategy owns.

[Feynman: balanceOfStake] It asks Sky Rewards how much USDS is recorded as staked for the strategy.

[Feynman: balanceOfRewards] It asks GROVE how many reward tokens the strategy currently owns.

[Feynman: claimableRewards] It asks Sky Rewards how much GROVE the strategy could claim now.

[Feynman: _deployFunds] It sends the requested amount of loose USDS into Sky Rewards and attaches the configured referral number. It assumes the reward program credits exactly what left the strategy.

[Inversion: _deployFunds] (1) Call with zero; (2) call while Sky Rewards is paused after the earlier deposit-limit check; (3) make the staking token transfer less than the requested amount.

[Feynman: _freeFunds] It asks Sky Rewards to return the requested amount of staked USDS. The inherited vault checks the strategy's actual USDS balance afterward, so a short return is measured as withdrawal loss rather than trusted blindly.

[Inversion: _freeFunds] (1) Withdraw zero; (2) withdraw more than the recorded stake; (3) withdraw while deposits are paused or the external program is otherwise unable to transfer USDS.

[Feynman: _harvestAndReport] It claims GROVE, sells the entire GROVE balance once it exceeds the configured threshold, optionally converts all loose USDC to USDS, puts loose USDS back into Sky Rewards when not shut down, and finally reports staked plus loose USDS. In auction mode the sale is asynchronous, so GROVE leaves this contract before any USDS proceeds are reported.

[Socratic: GroveCompounder.sol:97 — why?] Why does the direct route accept zero minimum output? The implicit belief is that trusted keepers and surrounding operations protect execution price; the contract itself does not.

[Socratic: GroveCompounder.sol:101 — why?] Why is the PSM return value ignored? Because final accounting reads actual USDS balances, although a successful no-op wrapper would leave USDC unreported.

[Inversion: _harvestAndReport] (1) Sandwich the GROVE/USDC trade while preserving the pool; (2) make `tin` change from zero to nonzero; (3) let GROVE cross the threshold while auction mode still points to zero.

[Feynman: _emergencyWithdraw] It caps the requested rescue amount at the recorded stake and asks Sky Rewards to return that amount, including making a zero-sized call when there is no stake.

[Feynman: availableDepositLimit] It tells callers no more deposits are allowed whenever Sky Rewards reports itself paused; otherwise it delegates the limit calculation to the inherited strategy.

[Inversion: availableDepositLimit] (1) Have the pause query revert; (2) pause after the view but before a deposit transaction; (3) return false here but reject `stake` during execution.

[Feynman: _min] It returns the smaller of two numbers, choosing the second when they are equal.

[Feynman: claimRewards] It lets management ask Sky Rewards to pay the strategy's accrued GROVE immediately.

[Feynman: _claimRewards] It asks the fixed Sky Rewards contract to pay whatever reward is due and assumes a zero reward is accepted as a no-op.

[Feynman: kickAuction] It lets a keeper choose a token, optionally claims GROVE when that token is GROVE, reads the whole chosen-token balance, and sends it to the configured auction if it exceeds a threshold denominated in GROVE units.

[Socratic: GroveCompounder.sol:169 — why?] Why is every caller-selected token compared to `minAmountToSell[REWARDS_TOKEN]` rather than its own threshold? The implicit belief is that every auctionable token uses GROVE's 18-decimal denomination and economic scale.

[Inversion: kickAuction] (1) Pass USDC with 6 decimals; (2) pass an address with no code; (3) pass a contract that implements `balanceOf` but returns false or malformed data from `transfer`.

[Feynman: _kickAuction] It refuses to sell USDS, requires a nonzero auction, transfers the chosen token there, and asks that auction to start selling its current balance. If the second action fails, the first action is rolled back with it.

[Inversion: _kickAuction] (1) Use an unenabled auction token; (2) call while that token already has an active auction; (3) use a token that calls back during transfer.

[Feynman: setMinAmountToSell] It lets management replace the GROVE sale threshold without a range restriction.

[Feynman: setUniV3Fees] It lets management replace the pool fee used by actual GROVE-to-USDC swaps without first proving such a pool exists.

[Feynman: setAuction] It lets management replace the sale contract after checking that proceeds are addressed back here and paid in USDS; clearing it is allowed only outside auction mode.

[Inversion: setAuction] (1) Supply an address with no code; (2) supply a contract that lies once about receiver and wanted token; (3) replace the auction while the old one still holds an active sale.

[Feynman: setUseAuction] It switches between asynchronous auction sales and direct Uniswap/PSM sales, requiring an auction address before switching toward auctions.

[Feynman: setReferral] It lets management replace the small referral number attached to future stakes.

[Feynman: UniswapV3SwapSimulator] This library predicts a Uniswap V3 result by finding the factory pool and replaying its current ticks without moving any tokens.

[Feynman: simulateExactInputSingle] It decides direction from token address order, finds the requested fee-tier pool, treats the caller's unsigned input amount as a signed swap amount, replays the swap, and returns the predicted output side. The fuzzy point is the unsigned-to-signed conversion.

[Socratic: UniswapV3SwapSimulator.sol:38 — why?] Why is `params.amountIn` converted to a signed number without proving it is at most `int256.max`? The implicit belief is that an exact-input amount can never set the sign bit.

[Inversion: simulateExactInputSingle] (1) Set `amountIn = 0`; (2) set `amountIn = type(uint256).max`; (3) use equal tokens or a fee tier whose factory result is zero.

[Feynman: getPool] It asks the supplied router for its factory and asks that factory for the pool matching the two tokens and fee. It does not independently prove that the router, factory, or returned pool is genuine.

[Inversion: getPool] (1) Use a router with no code; (2) use a router returning a malicious factory; (3) make the factory return address zero.

[Feynman: Simulate] This library walks through the pool's current price ranges and calculates how much of each token a swap would consume or produce.

[Feynman: simulateSwap] It reads the current price, tick, liquidity, fee, and spacing; repeatedly advances toward the next relevant tick; changes liquidity when a position boundary is crossed; and stops when the requested amount or price limit is reached. A positive requested number means spend that much input, while a negative number means demand that much output.

[Socratic: UniswapV3SwapSimulatorCore.sol:109 — why?] Why are requested-amount updates unchecked? The copied Uniswap invariants are assumed to constrain each step so the remaining amount moves monotonically toward zero.

[Inversion: simulateSwap] (1) Supply `int256.min`; (2) return zero or malformed liquidity from a noncanonical pool; (3) return an invalid tick spacing or inconsistent tick bitmap from a malicious pool.

[Feynman: nextInitializedTickWithinOneWord] It looks in one 256-position bitmap word for the next active price boundary in the requested direction, or returns the edge of that word when none is active.

[Inversion: nextInitializedTickWithinOneWord] (1) Use a negative tick with a remainder; (2) start on bit zero or bit 255; (3) provide zero, negative, or extreme spacing from a noncanonical pool.

[Feynman: tickBitmapPosition] It splits a compressed tick number into the map word and the bit within that word, preserving the low eight bits even for negative numbers.

[Feynman: GroveCompounderAprOracle] This component estimates the annual GROVE reward value per staked USDS. It prefers one live Uniswap V3 quote, otherwise derives prices from configured V4 pools, and rejects estimates above 50%.

[Feynman: GroveCompounderAprOracle.constructor] It makes the deployer manager and seeds four V4 pool identifiers with GROVE treated as token one. It does not test those pools during deployment.

[Feynman: _onlyManagement] It rejects any configuration caller other than the stored manager.

[Feynman: aprAfterDebtChange] It reads the global stake and GROVE emission rate, returns zero after rewards expire, obtains a market price, applies the hypothetical stake change, computes annual reward value per remaining stake, and rejects zero denominator or an answer above 50%.

[Socratic: GroveCompounderAprOracle.sol:114 — why?] Why is expiration tested with `>` instead of `>=`? The implicit belief is that `rewardRate` remains economically active at the exact finish timestamp.

[Socratic: GroveCompounderAprOracle.sol:123 — why?] Why can caller-supplied negative debt be subtracted without bounding it by total staked assets? The implicit belief is that every caller already supplies a feasible strategy debt change.

[Inversion: aprAfterDebtChange] (1) Pass `int256.min`; (2) pass a negative magnitude one wei larger than total stake; (3) query exactly when `block.timestamp == periodFinish`.

[Feynman: setManagement] It immediately hands oracle configuration power to a nonzero replacement address.

[Feynman: setUniV3Fee] It selects another fee tier only when the fixed factory currently returns a nonzero pool address.

[Inversion: setUniV3Fee] (1) Select a factory-listed pool with no usable liquidity; (2) select a manipulable thin pool; (3) have the pool later lose all liquidity.

[Feynman: setUniV4Pool] It discards every V4 candidate and replaces them with one nonzero identifier plus a manager-supplied token direction.

[Feynman: setUniV4Pools] It forwards a new list of pool identifiers and matching direction flags to the shared replacement routine.

[Feynman: addUniV4Pool] It appends one nonzero pool identifier only if that identifier is not already present.

[Feynman: removeUniV4Pool] It removes one indexed candidate by replacing it with the last candidate, while refusing to remove the last remaining pool.

[Inversion: removeUniV4Pool] (1) Remove index equal to length; (2) remove from a one-element list; (3) remove the most honest observation and leave a single manipulable one.

[Feynman: uniV3Pool] It returns the current factory pool for GROVE, USDC, and the selected fee.

[Feynman: uniV4PoolCount] It returns how many V4 candidates are configured.

[Feynman: uniV4Pool] It returns the identifier and token direction at a caller-chosen list position; an out-of-range position fails.

[Feynman: groveUsdcV4PoolId] It returns the first configured V4 identifier, relying on configuration rules to keep at least one entry.

[Feynman: v4GroveIsToken0] It returns the first candidate's direction flag.

[Feynman: bestUniV4Pool] It returns the chosen V4 identifier, direction, and active-liquidity number while omitting the derived price.

[Feynman: selectedUniV4Pool] It returns the full selected V4 quote.

[Feynman: _grovePrice] It accepts the V3 quote whenever superficial liquidity checks pass and simulation returns any positive output; any V3 failure falls back to the selected V4 price; absence of both fails the request.

[Socratic: GroveCompounderAprOracle.sol:228 — why?] Why is any positive V3 output accepted without comparison to the V4 median or a time-weighted value? The implicit belief is that current V3 state plus the two liquidity gates makes one-block price manipulation uneconomic.

[Inversion: _grovePrice] (1) Move V3 price in the same transaction as a consuming call; (2) keep the forged APR just below the 50% cap; (3) force V3 simulation to fail and attack the weakest surviving V4 candidate.

[Feynman: _v3PoolHasUsableLiquidity] It considers a factory pool usable if its current active-liquidity number is at least 1e12 and the USDC contract says the pool address owns at least 1,000 USDC. The token balance includes unsolicited transfers and does not say how much output the active position can safely provide.

[Socratic: GroveCompounderAprOracle.sol:243 — why?] Why is an ERC-20 balance treated as pool liquidity? The implicit belief is that all USDC sitting at the pool address belongs to usable in-range positions rather than donations, fees, or unrelated balance.

[Inversion: _v3PoolHasUsableLiquidity] (1) Transfer exactly 1,000e6 USDC directly to the pool; (2) create narrowly concentrated active liquidity just above 1e12; (3) retain both thresholds while moving the current price sharply.

[Feynman: _v4GrovePrice] It converts the V4 square-root price into the amount of USDC represented by one GROVE and expands six USDC decimals to eighteen.

[Feynman: _selectedV4Pool] It queries each configured V4 pool, discards low-liquidity or zero-price entries, takes the median of surviving prices, and among prices within ten percent of that median selects the entry with the largest raw active-liquidity number.

[Socratic: GroveCompounderAprOracle.sol:274 — why?] Why is one surviving quote considered a median-confirmed quote? With `quoteCount == 1`, the reference is the quote itself and the deviation check is automatically true.

[Inversion: _selectedV4Pool] (1) Wait until only one configured pool clears 1e12; (2) manipulate that pool and let it validate itself; (3) with three survivors manipulate two so their price becomes the median.

[Feynman: _medianPrice] It copies and sorts the surviving prices, returns the middle one for an odd count, and returns the overflow-safe average of the two middle values for an even count.

[Inversion: _medianPrice] (1) Supply one quote; (2) supply two quotes separated by more than 22.22%; (3) supply a majority of identical manipulated quotes.

[Feynman: _withinV4PriceDeviation] It measures absolute price distance and allows it when no more than ten percent of the reference.

[Inversion: _withinV4PriceDeviation] (1) Test exactly ten percent; (2) use a one-quote reference equal to the tested value; (3) form the even-count reference halfway between adversarial and honest values.

[Feynman: _setUniV4Pools] It requires a nonempty one-to-one list, discards the old candidates, rejects zero or duplicate identifiers, and stores every new identifier with its direction.

[Inversion: _setUniV4Pools] (1) Pass empty lists; (2) pass unequal lengths; (3) pass a very large unique list that makes duplicate checking quadratic.

[Feynman: _hasUniV4Pool] It scans the current list and answers whether an identifier is already present.

[Feynman: _uniV3Pool] It delegates current fee-tier lookup to the factory helper.

[Feynman: _uniV3PoolForFee] It asks the fixed Uniswap router for its factory and asks that factory for the GROVE/USDC pool at a selected fee.

[Inversion: _uniV3PoolForFee] (1) Have the router query revert; (2) return address zero; (3) return a pool that later becomes unusable.

[Feynman: _quoteToken1ForToken0] It squares the encoded square-root price and multiplies it by one token-zero unit, using two arithmetic routes so the square itself does not overflow.

[Inversion: _quoteToken1ForToken0] (1) Use square-root price zero; (2) use the exact 128-bit branch boundary; (3) use the largest 160-bit value.

[Feynman: _quoteToken0ForToken1] It performs the reciprocal conversion, again using two arithmetic routes to avoid overflowing the square.

[Inversion: _quoteToken0ForToken1] (1) Use square-root price zero; (2) use value one, which makes an enormous reciprocal; (3) use the exact 128-bit branch boundary.

## Boundary enumeration

- `GroveCompounder.constructor`: external reads at `STAKING.paused`, `PSM_WRAPPER.usds` (twice), `STAKING.stakingToken`, `STAKING.rewardsToken`, and `PSM_WRAPPER.gem`; token approval calls to the selected USDS and fixed USDC. All are fixed-address dependencies. Deployment fails closed on absent code/malformed returns, and the bundled OpenZeppelin `SafeERC20` implementation rejects no-code approval targets through `Address.functionCall`.
- `balanceOfAsset`, `balanceOfStake`, `balanceOfRewards`, `claimableRewards`: direct external balance/earned reads. Fixed asset/reward/staking identities make caller-selected no-code and nonstandard-token cases unreachable after successful construction.
- `_deployFunds`, `_freeFunds`, `_claimRewards`: void-return calls to fixed Sky Rewards. Return values cannot be checked; inherited withdrawal accounting re-reads the actual USDS balance, while staking credit correctness remains a dependency assumption.
- `_harvestAndReport`: external reward claim, GROVE balance, PSM fee read, inherited router call, USDC balance, PSM conversion, auction transfer/kick, shutdown read, staking calls, and final balance reads. Router output and PSM return are ignored, but final USDS accounting is balance-based. The direct swap deliberately supplies zero minimum output.
- `_emergencyWithdraw`: zero/max inputs are capped against the external staking balance, but zero still reaches the external `withdraw(0)` boundary.
- `availableDepositLimit`: the external pause read can itself revert; otherwise a later state change is caught by the stake call in the actual deposit transaction.
- `kickAuction`: `_token` is a keeper-supplied contract address. GROVE triggers an external claim; any token triggers `balanceOf`, then optionally a checked token transfer and auction call. No-code, false-return, void-return, and malformed-return cases fail closed under high-level decoding or the actual SafeERC20 implementation. The threshold is nevertheless taken from GROVE for every token.
- `_kickAuction`: `address(asset)` is the only token sentinel and is rejected. `auction == address(0)` is rejected before transfer. The token transfer plus `Auction.kick` are atomic.
- `setAuction`: the zero-address branch can clear only outside auction mode. The nonzero branch makes two typed external calls; no-code/malformed return fails closed, but the values are only point-in-time attestations.
- `simulateExactInputSingle`: caller supplies router, token addresses, fee, amount, and limit. This crosses router to factory, factory to pool, and then every pool-state boundary in the core. Zero amount reverts; values above `int256.max` change sign at the conversion.
- `simulateSwap`: external pool reads are `slot0`, `liquidity`, `fee`, `tickSpacing`, repeated `tickBitmap`, and initialized `ticks`. Canonical pools uphold the copied arithmetic invariants; caller-selected malicious routers/pools can make the generic library revert or quote nonsense, but this is a view-only surface.
- `aprAfterDebtChange`: fixed staking calls provide supply, reward rate, and finish time. `_strategy` is unused by design because yield is global to the shared staking program. `_delta` is unbounded signed caller input; impossible negative changes revert instead of returning a bounded result.
- `_grovePrice` / `_v3PoolHasUsableLiquidity`: fixed router/factory/pool and USDC calls. The V3 simulation is caught on failure; the preliminary pool-liquidity and USDC-balance calls are not caught. Any positive live quote is consumed without a time window or cross-source check.
- `_selectedV4Pool`: repeated fixed-StateView `getLiquidity` and `getSlot0` calls are individually caught. A success response is consumed as authentic pool state, with direction supplied by management. One surviving quote validates against itself.
- `_uniV3PoolForFee`: fixed router/factory external calls are not caught in getters/configuration. The factory's nonzero result is treated as a pool identity.
- No in-scope payable entry point exists. No in-scope `bytes` input, `abi.decode`, low-level custody call, native-token placeholder, ERC165 dispatch, or ERC721 hook exists.

## Structured results

FINDING | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: manipulable-spot-oracle | group_key: GroveCompounderAprOracle | _grovePrice | manipulable-spot-oracle
path: attacker moves the current GROVE/USDC V3 price while retaining `liquidity() >= 1e12` and `USDC.balanceOf(pool) >= 1_000e6` → a consumer calls `aprAfterDebtChange` in that state → `_grovePrice` accepts the first positive one-GROVE spot-simulation output without a TWAP or V4 comparison → the consumer receives an attacker-selected APR (up to the 50% cap)
boundary: the V3 pool's live `liquidity`, ERC-20 balance, tick/price state, and simulated return value consumed by `_v3PoolHasUsableLiquidity` and `_grovePrice`
assumption: an in-range liquidity number of 1e12 plus 1,000 USDC held at the pool address makes the instantaneous one-GROVE V3 quote representative and manipulation-resistant
actual: both predicates can remain true during a one-block price move, and the USDC predicate can be satisfied by a plain token donation that creates no usable liquidity; any positive simulated output is then accepted as the GROVE price
proof: with staking `assets = 100_000_000e18` and `rewardRate = 1e18`, a normal one-GROVE output of `25_000` USDC units becomes `price = 0.025e18` and APR `7.884e15` (0.7884%). If the same pool is moved so one GROVE simulates to `1_500_000` USDC units while the two gates still hold, the function computes `price = 1.5e18` and APR `473_040_000_000_000_000` (47.304%), which passes `MAX_EXPECTED_APR = 0.5e18`. Directly transferring `1_000e6` USDC to the pool is sufficient to satisfy the balance half of the gate without changing active liquidity. The public Yearn `AprOracle.getStrategyApr` dependency forwards this value without catching or normalizing it.
description: The APR oracle treats a manipulable V3 spot quote as authoritative after two superficial, independently satisfiable liquidity checks.
fix: Use a manipulation-resistant TWAP with observation/cardinality and minimum-window checks, and either compare V3 against independently derived V4/reference prices or reject material deviation; do not use raw token balance as a liquidity proof.

LEAD | contract: GroveCompounderAprOracle | function: _selectedV4Pool | bug_class: single-source-self-validation | group_key: GroveCompounderAprOracle | _selectedV4Pool | single-source-self-validation
code_smells: when only one configured V4 pool returns liquidity at least 1e12 and a nonzero price, `_medianPrice` returns that same price and `_withinV4PriceDeviation(price, price)` is necessarily true; two manipulated pools likewise form the median majority among three survivors
boundary: caught `StateView.getLiquidity/getSlot0` results from the surviving V4 candidate set
assumption: the median/deviation procedure independently corroborates the selected live V4 price
actual: at `quoteCount == 1` it performs no corroboration, so the sole surviving pool selects and validates its own instantaneous price
description: A naturally thin/unavailable default pool set may collapse the fallback to one manipulable spot source; current live conditions and the downstream economic action were not established from the bundle.

LEAD | contract: UniswapV3SwapSimulator | function: simulateExactInputSingle | bug_class: unsigned-to-signed-mode-confusion | group_key: UniswapV3SwapSimulator | simulateExactInputSingle | unsigned-to-signed-mode-confusion
code_smells: `int256(params.amountIn)` is not range-checked, so amounts above `int256.max` become negative and `simulateSwap` interprets them as exact-output swaps despite the public API promising exact input
boundary: caller-supplied `uint256 amountIn` converted into the signed `amountSpecified` that selects exact-input versus exact-output mode
assumption: every unsigned exact-input amount remains positive after conversion
actual: `int256(type(uint256).max) == -1`, so a maximum exact-input request is simulated as a request for exactly one unit of output; for a sufficiently liquid pool the outer function returns `1`, not the output from spending `type(uint256).max`
description: The generic public quote surface deterministically changes swap modes for high-bit inputs, but the only in-scope caller supplies fixed `1e18`, so an exploitable in-scope fund path is absent.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: unbounded-signed-delta-revert | group_key: GroveCompounderAprOracle | aprAfterDebtChange | unbounded-signed-delta-revert
code_smells: caller-supplied `_delta` is negated and subtracted without checking `type(int256).min` or bounding a negative change by `assets`; positive addition is also unbounded
boundary: caller-supplied signed hypothetical debt change
assumption: every caller supplies a mathematically feasible debt change
actual: `_delta = type(int256).min` reverts at `-_delta`, `_delta = -int256(assets + 1)` underflows at subtraction, and a sufficiently large positive delta overflows addition
description: Malformed boundary values turn the public oracle into a revert surface propagated by the dependency `AprOracle.getStrategyApr`, but no untrusted-to-state-changing caller was found in scope.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: expiry-boundary-stale-apr | group_key: GroveCompounderAprOracle | aprAfterDebtChange | expiry-boundary-stale-apr
code_smells: expiration returns zero only when `block.timestamp > periodFinish`, so the exact finish timestamp proceeds with the still-stored nonzero `rewardRate`
boundary: equality at the external staking program's reward-period timestamp
assumption: rewards are still economically emitted at `block.timestamp == periodFinish`
actual: standard staking reward accrual is capped at `periodFinish`, yet the oracle computes one final nonzero annualized APR at equality and returns zero one second later
description: Consumers can observe a stale nonzero APR for the exact expiry block; no material state-changing consumer or exploitable allocation window was proven from the bundle.

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: cross-token-threshold-unit-mismatch | group_key: GroveCompounder | kickAuction | cross-token-threshold-unit-mismatch
code_smells: a keeper may pass any non-asset token, but its balance is always compared with `minAmountToSell[REWARDS_TOKEN]`; the default `5_000e18` GROVE threshold corresponds to 5 quadrillion whole units for a 6-decimal token such as USDC
boundary: keeper-supplied token address and that token's balance/decimal domain
assumption: every caller-selected token can be meaningfully compared against a GROVE-denominated threshold
actual: a 6-decimal token balance must exceed `5_000e18` raw units before it can be kicked, while a token with more decimals may be kicked at negligible economic size
description: Manual auction support for non-GROVE tokens has denomination-dependent liveness; the bundle does not prove an attacker can force valuable non-asset inventory into this path.

LEAD | contract: GroveCompounder | function: _harvestAndReport | bug_class: incomplete-default-auction-configuration | group_key: GroveCompounder | _harvestAndReport | incomplete-default-auction-configuration
code_smells: storage defaults leave `auction == address(0)` while declaration sets `useAuction = true`; deposits are not conditioned on completing auction setup
boundary: the zero-address auction sentinel reached by the default auction branch
assumption: management supplies an auction before claimable GROVE grows above the threshold
actual: after any deposit and enough elapsed rewards to produce `toSwap > 5_000e18`, the first report calls `_kickAuction`, hits `require(_auction != address(0), "!auction")`, and atomically reverts; at exactly `5_000e18` it does not kick because comparison is strict
description: A valid post-deployment sequence can make reporting unavailable until management configures a venue, but withdrawals remain available and this is operational misconfiguration rather than an untrusted exploit.

## Result count

- FINDING: 1
- LEAD: 6
- Feynman markers: 57
- Socratic markers: 11
- Inversion markers: 24
