# Numerical-gap lane raw output

## Mandatory mental-tool trace

[Feynman: GroveCompounder] This contract takes USDS from its vault, places it in the Grove rewards program, converts earned GROVE back into USDS, and reports only USDS principal as assets. Reward sales can go either to a configured auction or through GROVE/USDC and then the USDC-to-USDS wrapper.

[Feynman: GroveCompounder.constructor] Deployment confirms the rewards program is open and stakes the same USDS that the wrapper returns, grants the two spend permissions needed for operations, and fixes GROVE sale settings. The fuzzy point is that auction mode starts enabled even though no auction address is installed yet.

[Feynman: balanceOfAsset] This reports how much unstaked USDS the strategy currently holds.

[Feynman: balanceOfStake] This reports how much USDS principal the external rewards program attributes to the strategy.

[Feynman: balanceOfRewards] This reports how much GROVE the strategy currently holds.

[Feynman: claimableRewards] This asks the rewards program how much additional GROVE the strategy may collect.

[Feynman: _deployFunds] This sends the requested USDS into the rewards program under the current referral number.

[Feynman: _freeFunds] This asks the rewards program to return the requested USDS.

[Feynman: _harvestAndReport] This collects GROVE, conditionally sells all of it, converts all held USDC into USDS on the direct route, restakes idle USDS above one USDS, and values the strategy as staked plus idle USDS. Its numerical assumptions are that one reward threshold has the same meaning on every sale path and that balances left exactly on a boundary can safely wait.

[Inversion: _harvestAndReport] (1) Leave exactly `minAmountToSell` GROVE after the final reward period so the strict `>` check never sells it. (2) Make the V3 route produce an adversarially small output because `_minAmountOut` is zero. (3) Deliver a large USDC balance before the report so the wrapper conversion handles value unrelated to the just-completed swap.

[Socratic: src/GroveCompounder.sol:94 — why?] Why does the outer sale gate use strict `>` when the inherited swapper accepts `>=`, and what makes the exact terminal balance safe to leave forever?

[Feynman: _emergencyWithdraw] This returns no more USDS from staking than the strategy actually has staked, even when asked for more.

[Feynman: availableDepositLimit] This closes deposits whenever the external rewards program is paused; otherwise it uses the inherited vault limit.

[Inversion: availableDepositLimit] (1) Pause after a deposit-limit quote but before the deposit. (2) Leave staking unpaused while its stake call is otherwise disabled. (3) Pause only withdrawals and observe that this check knows only the single external flag.

[Feynman: _min] This returns the smaller of two whole-number amounts.

[Feynman: claimRewards] This lets management collect accumulated GROVE without selling it.

[Feynman: _claimRewards] This invokes the rewards program's collection operation.

[Feynman: kickAuction] This lets a keeper collect GROVE when the requested token is GROVE, otherwise inspect any requested token already held, and send the full balance to the auction when it clears a threshold. The fuzzy point is that the threshold is always read from GROVE's entry even for a token with another decimal scale.

[Socratic: src/GroveCompounder.sol:168 — why?] Why is an arbitrary `_token` balance compared to `minAmountToSell[REWARDS_TOKEN]` rather than to a threshold denominated in `_token`?

[Inversion: kickAuction] (1) Supply USDC with 6 decimals so an ordinary valuable balance can never exceed a GROVE-wei threshold. (2) Request the USDS asset and force the later principal guard to revert. (3) Request a token the auction has not enabled so the transfer-and-kick transaction fails closed.

[Feynman: _kickAuction] This refuses to sell principal, requires an installed auction, moves the entire requested token balance there, and starts that token's sale.

[Feynman: setMinAmountToSell] This lets management replace the minimum GROVE balance used before automatic sale.

[Feynman: setUniV3Fees] This lets management select which GROVE/USDC V3 fee-tier pool the direct sale route will use.

[Feynman: setAuction] This lets management install only an auction that returns USDS to this strategy, or clear the address only after auction mode is off.

[Inversion: setAuction] (1) Install a contract that reports the expected receiver and wanted token but later changes behavior. (2) Replace the auction immediately between keeper planning and execution. (3) Use a valid auction that has not enabled GROVE so kicks revert.

[Feynman: setUseAuction] This switches sale routes and refuses to enter auction mode until some auction address is installed.

[Feynman: setReferral] This replaces the small referral number passed on later stakes.

[Feynman: UniswapV3SwapSimulator] This helper estimates what a V3 exact-input swap would return by replaying the pool's current price and liquidity rather than moving tokens.

[Feynman: simulateExactInputSingle] This finds the ordered GROVE/USDC pool, chooses swap direction from token addresses, replays the requested input to the caller's price limit, and turns the pool's signed output into an unsigned quantity. The fuzzy point is that an unrestricted unsigned input is first reinterpreted as a signed amount.

[Socratic: src/libraries/UniswapV3SwapSimulator.sol:30 — why?] What guarantees `params.amountIn <= type(int256).max` before the unsigned input is reinterpreted as signed?

[Inversion: simulateExactInputSingle] (1) Pass `amountIn = 2^255` so it becomes a negative exact-output request. (2) Configure a fee with no pool so calls target address zero. (3) choose a price limit on the wrong side of the current price so the replay rejects it.

[Feynman: UniswapV3SwapSimulator.getPool] This asks the router's factory for the pool matching the two tokens and fee.

[Feynman: Simulate] This library walks the V3 price curve and initialized price bands in memory to reproduce the input and output amounts a live swap would calculate.

[Feynman: simulateSwap] This starts from the pool's current price and active liquidity, repeatedly consumes input or fills requested output until the request or price limit is reached, updates liquidity at crossed bands, and returns the two token balance changes.

[Inversion: simulateSwap] (1) Start with zero active liquidity and force traversal across empty words. (2) Cross the minimum price-band boundary in the downward direction. (3) supply a negative amount at the signed minimum and stress every negation and signed-delta update.

[Feynman: nextInitializedTickWithinOneWord] This searches one 256-position bitmap word in the chosen direction and returns either the nearest marked price band or that word's boundary.

[Feynman: tickBitmapPosition] This turns a compressed signed price-band number into its bitmap word and position, preserving the low eight bits for negative numbers.

[Feynman: GroveCompounderAprOracle] This contract estimates annual Grove rewards per staked USDS using a GROVE price from V3 when usable and otherwise from configured V4 pools. It exposes the result on a 1e18 scale and refuses results above 50%.

[Feynman: GroveCompounderAprOracle.constructor] This gives the deployer price-source authority and installs four default V4 pool identifiers, all interpreted as pools where GROVE is the second token.

[Feynman: _onlyManagement] This refuses configuration changes from every address except the stored manager.

[Feynman: aprAfterDebtChange] This reads the total USDS in the external rewards program and its GROVE-per-second rate, returns zero after the reward period, prices GROVE, adds or subtracts the hypothetical strategy debt change from global staked USDS, and divides annual reward value by that adjusted amount. The fuzzy point is that it never checks how much of the named strategy's debt change would actually enter or leave staking.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:109 — why?] Why is `_strategy` unused when the amount of idle USDS at that strategy determines whether a negative debt change reduces the global staking denominator at all?

[Socratic: src/periphery/GroveCompounderAprOracle.sol:115 — why?] Why is the reward period considered active at `block.timestamp == periodFinish` when reward accrual conventionally stops at that exact time?

[Inversion: aprAfterDebtChange] (1) Withdraw only idle strategy USDS so the code subtracts debt from staking even though staking does not change. (2) choose `_delta = -totalSupply` to hit the zero-denominator rejection. (3) move the spot price just below the 50% cap so an extreme but accepted APR is returned.

[Feynman: setManagement] This transfers price-source authority in one step to a nonzero address.

[Feynman: setUniV3Fee] This selects a V3 fee tier only when the factory currently lists a GROVE/USDC pool for it.

[Feynman: setUniV4Pool] This replaces every V4 candidate with one nonzero pool identifier and a caller-supplied token orientation.

[Feynman: setUniV4Pools] This replaces the V4 candidate set with the paired list of pool identifiers and token orientations after internal validation.

[Feynman: addUniV4Pool] This appends one nonzero V4 pool identifier if that identifier is not already listed.

[Feynman: removeUniV4Pool] This removes one selected candidate by replacing it with the last candidate, while always leaving at least one.

[Feynman: uniV3Pool] This reveals the factory pool selected by the current V3 fee.

[Feynman: uniV4PoolCount] This reveals how many V4 candidates are configured.

[Feynman: uniV4Pool] This reveals one candidate's identifier and whether GROVE is its first token.

[Feynman: groveUsdcV4PoolId] This reveals the first configured V4 identifier for compatibility with older single-pool callers.

[Feynman: v4GroveIsToken0] This reveals the first configured pool's GROVE orientation for compatibility with older callers.

[Feynman: bestUniV4Pool] This reveals the identifier, orientation, and raw active-liquidity number of the candidate selected by the internal filter.

[Feynman: selectedUniV4Pool] This reveals the complete selected V4 quote, including the integer-scaled price.

[Feynman: _grovePrice] This prefers a one-GROVE V3 swap estimate whenever two raw V3 liquidity checks pass; otherwise it takes the selected V4 spot price and refuses to return when every source produces zero.

[Inversion: _grovePrice] (1) Donate USDC to the V3 pool so its token-balance gate no longer reflects usable depth. (2) leave V3 just below either gate and manipulate the V4 fallback in the same block. (3) make the true one-GROVE quote less than one raw USDC unit so integer conversion turns a positive price into zero and the function reverts.

[Feynman: _v3PoolHasUsableLiquidity] This calls a V3 pool usable when its raw active-liquidity number is at least 1e12 and the pool address holds at least 1,000 USDC, regardless of how that liquidity is distributed around the current price.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:239 — why?] Why does a raw concentrated-liquidity number plus the contract's total USDC balance prove that a one-GROVE quote has economically meaningful depth?

[Inversion: _v3PoolHasUsableLiquidity] (1) Donate 1,000 USDC without making it swappable at the current range. (2) place 1e12 liquidity in a razor-thin range at a manipulated spot. (3) leave large out-of-range reserves while current active liquidity barely meets the threshold.

[Feynman: _v4GrovePrice] This converts the pool's square-root token ratio into the raw USDC received for one whole GROVE and then expands six-decimal USDC into the oracle's 18-decimal scale.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:247 — why?] What protects a positive sub-micro-USDC quote from first truncating to zero and then being treated as if the pool had no price?

[Feynman: _selectedV4Pool] This gathers every candidate with raw active liquidity of at least 1e12 and a nonzero whole-micro-USDC price, sorts their prices to form a median reference, rejects quotes more than 10% from that reference, and returns the qualifying quote with the largest raw liquidity. The fuzzy point is that an even-sized median may not equal any quote, so every quote can be rejected.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:258 — why?] Why is the same raw `liquidity >= 1e12` boundary meaningful across concentrated ranges and price levels without considering range width or a fixed-size executable quote?

[Socratic: src/periphery/GroveCompounderAprOracle.sol:282 — why?] What guarantees at least one quote is within 10% of the arithmetic midpoint when an even candidate count has a wide middle gap?

[Inversion: _selectedV4Pool] (1) Activate exactly one dormant configured pool at `liquidity = 1e12` so quote count changes from one to two. (2) activate three dust-funded pools at the same false price so they become the median majority. (3) give a narrow false-price position one more raw liquidity unit than the honest pool so the selector chooses it.

[Feynman: _medianPrice] This copies and sorts the collected prices, returns the middle observation for an odd count, and returns the rounded-down midpoint of the two middle observations for an even count.

[Inversion: _medianPrice] (1) Provide two prices in a ratio above 11:9 so their midpoint is more than 10% from both. (2) split four observations into two low and two high clusters. (3) choose adjacent middle prices whose odd sum exercises the one-unit downward midpoint rounding.

[Feynman: _withinV4PriceDeviation] This measures absolute distance from the reference and accepts it when the distance does not exceed a rounded-down 10% of the reference.

[Feynman: _setUniV4Pools] This checks for a nonempty one-to-one list, rejects empty or repeated identifiers, and replaces the stored candidate list.

[Feynman: _hasUniV4Pool] This scans the current candidates and reports whether one identifier is already present.

[Feynman: _uniV3Pool] This resolves the current V3 fee tier to a factory pool address.

[Feynman: _uniV3PoolForFee] This asks the router's factory which GROVE/USDC pool belongs to a specific fee.

[Feynman: _quoteToken1ForToken0] This squares the encoded square-root ratio without losing the high half and uses it to calculate how much second-token quantity corresponds to a first-token quantity.

[Inversion: _quoteToken1ForToken0] (1) test a square-root price exactly at the 128-bit branch boundary. (2) test the smallest valid square-root price where the result may round to zero. (3) test the largest valid square-root price where the final 1e12 expansion is largest.

[Feynman: _quoteToken0ForToken1] This squares the encoded square-root ratio and divides into the inverse ratio to calculate how much first-token quantity corresponds to a second-token quantity.

[Inversion: _quoteToken0ForToken1] (1) pass zero and force a zero denominator, noting the caller filters it. (2) test one unit above the 128-bit branch boundary for branch consistency. (3) test the smallest protocol-valid square-root price for the largest inverse quote.

[Feynman: UniswapV3Swapper._swapFrom] The inherited helper sells the input only when its amount reaches that input token's own minimum and sends either a one-pool or two-pool exact-input order with the caller's minimum output.

[Feynman: Auction._kick] The configured auction snapshots the token amount it currently holds into a 128-bit sale size after checking that token was enabled and no prior sale is active.

[Feynman: TokenizedStrategy._withdraw] The vault pays a withdrawal entirely from idle USDS when possible and asks the strategy to unstake only the shortfall, proving that a debt decrease need not equal a staking-supply decrease.

## Findings and leads

FINDING | contract: GroveCompounderAprOracle | function: _selectedV4Pool | bug_class: raw-liquidity-scale-oracle-manipulation | group_key: GroveCompounderAprOracle | _selectedV4Pool | raw-liquidity-scale-oracle-manipulation
seam: three-way (boundary × precision/scale × invariant)
path: permissionless V4 liquidity provider → concentrate cheap liquidity in three configured pools at a chosen spot price → each raw `getLiquidity` value clears `MIN_REWARD_POOL_LIQUIDITY` → attacker prices form the median and the largest raw-liquidity attacker pool is selected → `aprAfterDebtChange` returns an attacker-chosen APR below the hard cap
proof: The selection compares raw Uniswap liquidity rather than executable value or reserves. At the audit snapshot the only qualifying default pool had `liquidity = 2,234,678,351,511,442`, `sqrtPriceX96 = 693136446531199880837452956973944644`, and price `13,065 * 1e12 = 0.013065e18`. An attacker can activate the other three already-configured pools at price `0.08e18` and give one `2,235,000,000,000,000` raw liquidity. Sorted prices are `[0.013065, 0.08, 0.08, 0.08]e18`, so the median is exactly `0.08e18`; all three attacker quotes have zero deviation, the honest quote is rejected, and the attacker pool wins by raw liquidity. With observed staking values `assets = 211216803151519410736161325` and `rewardRate = 38844495180111618467`, the returned APR is `38844495180111618467 * 31536000 * 0.08e18 / assets = 463978237231903803` (46.3978%), below the `0.5e18` cap, whereas the honest price yields `75773445867935289` (7.5773%). The raw boundary is economically tiny because liquidity can be concentrated: at the 0.08 price, a 200-tick-wide position with `L = 2.235e15` contains only about $6.29 of USDC and $6.29 of GROVE per side-equivalent, roughly $12.58 per attacker pool; neither range width nor a one-GROVE executable quote is checked.
description: Raw concentrated-liquidity units are treated as price weight and depth, letting very low-capital narrow positions become a median majority and inflate the Grove APR up to just below the accepted 50% boundary.
fix: Replace raw-liquidity ranking/gating with a fixed-size executable quote or manipulation-resistant TWAP plus economically normalized depth, and require an independent quorum before accepting V4 fallback prices.

FINDING | contract: GroveCompounderAprOracle | function: _medianPrice/_selectedV4Pool | bug_class: even-median-empty-selection-dos | group_key: GroveCompounderAprOracle | _selectedV4Pool | even-median-empty-selection-dos
seam: three-way (boundary × precision × invariant)
path: permissionless V4 liquidity provider → add exactly the minimum active liquidity to one dormant configured pool while V3 is unavailable → quote count crosses from one to two → arithmetic midpoint is more than 10% from both real observations → no index is selected → `_grovePrice` receives zero and `aprAfterDebtChange` reverts
proof: For two sorted prices `p < q`, the code uses `m = floor((p+q)/2)` and admits a quote only when its distance from `m` is at most `0.1m`; ignoring the final one-wei floor, both middle quotes fail whenever `q/p > 11/9 = 1.222...`. The audit snapshot supplies an immediately concrete trace: V3 had `liquidity = 0` and only `71` raw USDC, the one active V4 quote was `p = 13,065e12`, and configured pool `0x2e53...1ad5` retained nonzero slot0 price `q = 21,608e12` with zero liquidity. Adding exactly `1e12` active liquidity to that dormant pool makes `m = 17,336.5e12` and tolerance `1,733.65e12`; each quote's distance is `4,271.5e12`, so both fail, `selectedIndex` stays at `uint256.max`, and the function returns zero. At that pool's stored square-root price, `L = 1e12` over one tick corresponds to only about `7.349` raw USDC plus `0.00034011` GROVE (about $0.0000147 total); even a 200-tick example is about $0.00293, demonstrating the threshold boundary is cheap to cross.
description: Averaging the two middle V4 prices creates a reference that need not be near any observation, so activating one divergent pool can make every otherwise usable fallback quote disappear and deterministically deny the APR oracle.
fix: For even counts use a lower or upper order-statistic median (which is itself an observation), or always select the closest sufficiently deep quote after the sanity check so a nonempty candidate set cannot collapse to no selection.

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: cross-token-threshold-scale-mismatch | group_key: GroveCompounder | kickAuction | cross-token-threshold-scale-mismatch
seam: boundary × precision/scale
code_smells: The function explicitly accepts non-GROVE `_token` values but always compares their raw balance against `minAmountToSell[REWARDS_TOKEN]`. With the default `5_000e18` GROVE threshold, a 6-decimal token such as USDC must exceed `5e21` raw units, i.e. more than `5e15` whole USDC, before it can be kicked; even 1,000,000 USDC is only `1e12` raw and fails. The inherited swapper's own gate is keyed by the actual input token, showing the intended per-token invariant.
description: Valuable incidental or secondary tokens with fewer decimals can be operationally stranded because the arbitrary-token auction path applies a boundary denominated in GROVE wei.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: idle-debt-denominator-mismatch | group_key: GroveCompounderAprOracle | aprAfterDebtChange | idle-debt-denominator-mismatch
seam: boundary × invariant
code_smells: The function ignores `_strategy` and subtracts the entire negative debt delta from global staking `totalSupply`, but TokenizedStrategy withdrawals consume idle asset first and call `_freeFunds` only for `withdrawal - idle`. At the piecewise boundary `withdrawal <= idle`, actual staking supply changes by zero while the oracle subtracts the full withdrawal. For example, with global stake `200m USDS`, strategy idle auction proceeds `10m USDS`, and `_delta = -10m USDS`, execution pays entirely from idle and leaves staking at `200m`, while the oracle divides by `190m` and overstates APR by `200/190 - 1 = 5.263%` relative.
description: Negative debt quotes can diverge from the debt-change execution exactly when idle assets cover some or all of the withdrawal, but the downstream consumer impact and realistic maximum pre-report idle balance remain to be established.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: terminal-period-boundary-stale-apr | group_key: GroveCompounderAprOracle | aprAfterDebtChange | terminal-period-boundary-stale-apr
seam: boundary × invariant
code_smells: The early return is `block.timestamp > periodFinish` rather than `>=`. At `block.timestamp == periodFinish`, conventional staking accrual has reached its terminal time but this oracle still annualizes the stored nonzero rate. Using the audit snapshot's `rewardRate`, `assets`, and `0.013065e18` price, the boundary quote remains `75773445867935289` (7.5773%) for that timestamp instead of zero.
description: The oracle has a one-timestamp stale-reward window at the exact finish boundary; practical exploitability depends on a consumer acting in a block whose timestamp equals the externally chosen finish time.
