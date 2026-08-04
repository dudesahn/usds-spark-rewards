# Execution-trace lane raw output

The source bundle was read in full before the orientation file. Orientation statements below were independently checked against the bundled source and, where execution depended on imported code, against the relevant out-of-scope interface/library/test only. The orientation's attack-surface and invariant labels are not treated as findings. Git-history, coverage, contributor, and nSLOC metadata are not execution claims and were not used as vulnerability evidence.

## Mental-tool stream

[Feynman: GroveCompounder] This contract accepts USDS through an imported vault runtime, sends it to the Sky staking program, collects GROVE rewards, sells those rewards through one of two routes, and counts only staked plus idle USDS as investor assets. Its correctness therefore depends on each external venue being callable in the exact state in which the strategy invokes it.

[Feynman: GroveCompounder.constructor] Deployment fixes the staking and PSM dependencies, confirms that the staking program is presently open and uses the same USDS asset, grants long-lived spending permission, and selects USDC plus a GROVE/USDC market for sales. The fuzzy spot is that the contract also starts in auction mode even though no auction exists yet.

[Socratic: GroveCompounder.sol:22 — why?] Why is auction mode live before a target is configured? The implicit belief is that no report with more than the reward threshold will occur between deployment and management setup.

[Feynman: balanceOfAsset] This reports how much loose USDS the strategy currently holds.

[Feynman: balanceOfStake] This reports how much USDS the external staking program credits to the strategy.

[Feynman: balanceOfRewards] This reports how much GROVE is already sitting in the strategy.

[Feynman: claimableRewards] This asks the staking program how much additional GROVE the strategy can collect.

[Feynman: _deployFunds] This sends a requested amount of loose USDS into the staking program and attaches the current referral number.

[Feynman: _freeFunds] This asks the staking program to return a requested amount of USDS.

[Feynman: _harvestAndReport] A report first collects all earned GROVE. If enough GROVE exists, it either sends all of it into the auction or trades all of it for USDC and converts the strategy's entire USDC balance to USDS. It then stakes loose USDS when the strategy is live and finally reports staked plus loose USDS.

[Socratic: GroveCompounder.sol:100 — why?] Why does the direct sale pass a zero minimum output? The implicit belief is that the public pool cannot be moved against this known transaction, or that losing unaccounted rewards will be caught elsewhere; neither belief is enforced.

[Socratic: GroveCompounder.sol:107 — why?] Why is an auction kicked unconditionally whenever the strategy's GROVE balance is large enough? The implicit belief is that the configured auction is not already active, although the auction itself permits unrelated callers to create that state.

[Inversion: _harvestAndReport] (1) Front-run the direct GROVE sale by moving the 1% pool price, let the zero-floor sale execute, then back-run it. (2) Put the configured auction into an active state with one unit of GROVE just before report so the nested kick rejects the call. (3) Pause staking while the strategy has more than 1 USDS idle so the final restake rejects and rolls back the whole report.

[Feynman: _emergencyWithdraw] During shutdown, this asks the staking program for no more USDS than the strategy is recorded as having there.

[Feynman: availableDepositLimit] This closes new deposits while the external staking program says it is paused; otherwise it uses the inherited limit and allowlist rules.

[Inversion: availableDepositLimit] (1) Query while unpaused and pause before deposit; the eventual stake reverts atomically. (2) Pause after USDS is already idle; deposits close but report may still attempt a stake. (3) Make the receiver fail the inherited allowlist even while staking is open; the inherited limit still closes the deposit.

[Feynman: _min] This returns the smaller of two numbers.

[Feynman: claimRewards] Management can collect earned GROVE without selling or reporting it.

[Feynman: _claimRewards] This asks the staking program to transfer all presently earned rewards to the strategy.

[Feynman: kickAuction] A keeper chooses a non-principal token. For GROVE, the function first collects newly earned rewards; for any other token it only inspects the current balance. If that balance beats the GROVE sale threshold, it forwards the entire balance to the auction and asks the auction to start selling it.

[Socratic: GroveCompounder.sol:168 — why?] Why is every keeper-selected token compared with `minAmountToSell[REWARDS_TOKEN]`? The implicit belief is that the threshold's units are meaningful for every token, which is false for tokens with other decimals or values.

[Inversion: kickAuction] (1) Supply GROVE while an auction is already active so the nested kick fails. (2) Choose a 6-decimal token and observe that an 18-decimal GROVE threshold makes its sale practically unreachable. (3) Choose a malicious non-asset token whose balance and transfer functions call arbitrary code; role checks and the tokenized runtime's report guard limit the reachable impact, so this did not become a separate finding.

[Feynman: _kickAuction] This rejects principal and a missing auction, moves the entire chosen-token balance to the configured auction, and then asks that auction to start a sale. Transfer and start happen in one transaction, so a failed start rolls the transfer back; the problem is that it also rolls the enclosing report back.

[Feynman: setMinAmountToSell] Management changes the minimum GROVE inventory that triggers a sale.

[Feynman: setUniV3Fees] Management chooses which GROVE/USDC fee-tier market the direct route uses, without checking here that the market exists or is liquid.

[Feynman: setAuction] Management installs an auction only after its current receiver is the strategy and its requested payment token is USDS, or clears it only after leaving auction mode. These are snapshots of mutable external state, not continuing guarantees.

[Inversion: setAuction] (1) Configure a correct auction and later change its receiver through auction governance. (2) Configure an auction whose GROVE market is not enabled, causing kicks to fail closed. (3) Configure a permissionless-kick auction and let anyone create an active dust auction before report. The third move is reachable with the shipped auction implementation and is reported below.

[Feynman: setUseAuction] Management switches reward sales between the installed auction and the fixed direct Uniswap/PSM route; entering auction mode requires only a nonzero stored address.

[Inversion: setUseAuction] (1) Enter auction mode with an externally active auction. (2) Enter direct mode while the chosen V3 fee tier has no liquidity. (3) Switch routes immediately before a keeper report, causing the report to consume the new route; these are management-controlled, while the first two can still expose liveness failures after configuration.

[Feynman: setReferral] Management changes the small referral label supplied with future stakes; it does not move or reattribute already staked funds.

[Feynman: UniswapV3SwapSimulator] This library estimates what the canonical router's single-pool trade would return by reading the corresponding pool and replaying its price movement without transferring tokens.

[Feynman: simulateExactInputSingle] This finds the requested fee-tier pool, decides the token order from the addresses, replays a trade using the supplied amount and price boundary, and returns the simulated received-token amount. Although the name promises an input-sized trade, a very large unsigned amount changes sign when converted for the replay.

[Socratic: UniswapV3SwapSimulator.sol:35 — why?] Why is an arbitrary unsigned input converted directly to a signed number? The implicit belief is that callers always supply at most `type(int256).max`, but the library does not enforce it.

[Feynman: getPool] This asks the router for its factory and asks that factory for the unique pool for the two tokens and fee. A missing pool becomes an address with no pool behavior and the caller may catch that failure.

[Feynman: Simulate] This library locally reproduces the price and liquidity traversal of a Uniswap V3 trade using live pool observations.

[Feynman: simulateSwap] This begins at the pool's current price and active liquidity, repeatedly moves toward the next initialized price boundary while charging the pool fee, changes active liquidity when positions start or end, and returns the two token balance changes when the requested amount or limit is reached.

[Inversion: simulateSwap] (1) Supply zero and hit the explicit guard. (2) Supply a boundary on the wrong side and hit the explicit price guard. (3) Supply an amount whose signed interpretation is negative through the wrapper and make an exact-input API replay an exact-output trade; this survives both guards and is retained as a lead because the in-scope oracle always supplies `1e18`.

[Feynman: nextInitializedTickWithinOneWord] This examines one 256-tick bitmap word in the direction of travel, returning either the nearest initialized position or that word's outer boundary.

[Feynman: tickBitmapPosition] This maps a compressed tick number to the bitmap word and the bit inside that word.

[Feynman: GroveCompounderAprOracle] This contract estimates system-wide Sky staking APR from current reward emissions, hypothetical total stake after a signed change, and a current GROVE price obtained from public Uniswap state. It prefers one V3 market and uses configured V4 observations only when that path is unusable.

[Feynman: _onlyManagement] This allows only the currently stored oracle manager to change price-source configuration.

[Feynman: GroveCompounderAprOracle.constructor] Deployment gives the deployer sole configuration power and seeds four fixed V4 pool identifiers, all marked as USDC-first/GROVE-second.

[Feynman: aprAfterDebtChange] This reads total Sky stake and the current GROVE emission rate, returns zero after emissions have ended, gets a market price, applies the hypothetical stake change to the system-wide total, and annualizes reward value over the adjusted stake while rejecting zero stake or more than 50% APR.

[Socratic: GroveCompounderAprOracle.sol:115 — why?] Why does expiry use `>` rather than `>=`? The implicit belief is that the configured reward rate still represents future emissions at the exact finish timestamp.

[Inversion: aprAfterDebtChange] (1) Move GROVE spot price upward only far enough to return `0.49e18`, passing the upper cap. (2) Move price downward arbitrarily; there is no lower sanity check. (3) Call exactly at `periodFinish`; the stale reward rate is annualized for one boundary timestamp. Moves one and two are enabled by the pricing path and are reported together below.

[Feynman: setManagement] The current oracle manager immediately hands all configuration power to a nonzero replacement.

[Feynman: setUniV3Fee] Management chooses a V3 fee tier only if the router's factory presently returns a pool address for GROVE and USDC.

[Feynman: setUniV4Pool] Management replaces every V4 candidate with one nonzero identifier and a manually supplied token direction.

[Feynman: setUniV4Pools] Management replaces all V4 candidates with parallel identifier and direction lists after length, nonzero, and duplicate checks.

[Feynman: addUniV4Pool] Management appends one nonzero pool identifier that is not already stored, together with a manually supplied token direction.

[Feynman: removeUniV4Pool] Management removes a chosen candidate by replacing it with the last entry, but refuses to remove the final remaining pool.

[Feynman: uniV3Pool] This reveals the current factory pool selected by the stored V3 fee.

[Feynman: uniV4PoolCount] This reveals how many V4 candidate identifiers are configured.

[Feynman: uniV4Pool] This reveals one configured V4 identifier and its manually stated GROVE direction.

[Feynman: groveUsdcV4PoolId] This compatibility view reveals the first configured V4 identifier.

[Feynman: v4GroveIsToken0] This compatibility view reveals the first configured V4 direction flag.

[Feynman: bestUniV4Pool] This reveals the identifier, direction, and active-liquidity number of the candidate the selection routine currently prefers.

[Feynman: selectedUniV4Pool] This reveals the same selected V4 candidate together with its computed current GROVE price.

[Feynman: _grovePrice] This first accepts the simulated one-GROVE output of the selected V3 pool whenever basic pool gates pass and the replay returns anything positive. Only if that fails does it take the selected V4 spot price; it never compares V3 with V4 or with a prior observation.

[Inversion: _grovePrice] (1) Keep V3 just above the raw-liquidity and USDC-balance gates while setting a manipulated current price. (2) Make V3 unusable so the function falls to a single surviving V4 quote. (3) Move the chosen price to the largest value that keeps calculated APR immediately below 50%, defeating the final cap.

[Feynman: _v3PoolHasUsableLiquidity] This calls the current V3 pool usable when it exists, its active-liquidity number is at least `1e12`, and at least 1,000 raw USDC units are present at the pool address. It does not measure the cost to move the price, the width of the active positions, or the relationship between spot and a time-weighted price.

[Socratic: GroveCompounderAprOracle.sol:242 — why?] Why does raw active liquidity plus an easily changed token balance prove price integrity? The implicit belief is that these quantities make a one-block price manipulation uneconomic, which is not enforced and is especially weak for narrowly concentrated liquidity.

[Inversion: _v3PoolHasUsableLiquidity] (1) Add exactly `1e12` narrow active liquidity around an attacker-set price. (2) Donate or route exactly `1_000e6` USDC to the pool address. (3) Manipulate an already deep pool with flash liquidity and unwind after the consuming call; all three satisfy the boolean gate without producing a time-weighted price.

[Feynman: _v4GrovePrice] This turns the pool's current square-root price into the USDC received for one GROVE and rescales six-decimal USDC into an 18-decimal USDS-denominated value, using the manager-supplied token direction.

[Feynman: _selectedV4Pool] This collects current spot prices from candidates whose active-liquidity number meets the threshold, computes the median of however many survived, discards prices more than 10% from that median, and returns the surviving quote with the largest raw liquidity number. A one-element candidate set compares the observation only with itself.

[Socratic: GroveCompounderAprOracle.sol:274 — why?] Why is one surviving quote enough to define its own median and pass with zero deviation? The implicit belief is that configuration count implies multiple live independent observations; current state and the code's skip behavior disprove that belief.

[Inversion: _selectedV4Pool] (1) Leave only one candidate above `1e12`; its manipulated price is the median and passes with zero deviation. (2) With two candidates, move both sides of their arithmetic midpoint so the reference itself moves. (3) Add narrow liquidity to a manipulated candidate so its raw liquidity number wins selection even with little capital at risk outside the active range.

[Feynman: _medianPrice] This sorts the collected prices and returns the middle one, or the midpoint of the two middle prices when the count is even.

[Feynman: _withinV4PriceDeviation] This accepts a price whose absolute difference from the selected reference is no more than 10% of that reference.

[Inversion: _withinV4PriceDeviation] (1) With one quote, deviation is exactly zero. (2) With two prices of 100 and 121, median 110 accepts both even though they differ by 21%. (3) Control a majority of usable observations so the median itself is adversarial; unique pool identifiers do not prove independent liquidity or control.

[Feynman: _setUniV4Pools] This atomically clears the old list, checks that a nonempty parallel configuration has no zero or repeated identifiers, stores each pair, and announces the new list. A later failure rolls the whole call back, so the early clear does not leave partial state.

[Feynman: _hasUniV4Pool] This scans the current list to report whether an identifier is already present.

[Feynman: _uniV3Pool] This resolves the currently configured V3 fee through the router's factory.

[Feynman: _uniV3PoolForFee] This asks the canonical router's factory for the GROVE/USDC pool at one fee tier.

[Feynman: _quoteToken1ForToken0] This squares the current price representation and calculates how much token 1 corresponds to a chosen amount of token 0, selecting an intermediate scale that avoids overflowing for valid pool prices.

[Feynman: _quoteToken0ForToken1] This performs the inverse calculation, returning how much token 0 corresponds to a chosen amount of token 1.

[Feynman: UniswapV3Swapper (external context)] This inherited helper turns an in-scope reward-sale request into a canonical router trade after arranging token allowance.

[Feynman: UniswapV3Swapper._swapFrom (external context)] This spends the requested input through one or two V3 pools whenever it meets the stored threshold and lets the caller choose the least acceptable output; the in-scope caller chooses zero.

[Feynman: UniswapV3Swapper._checkAllowance (external context)] This grants the router exactly the requested spending permission only when its present allowance is too small.

[Feynman: Auction (external context)] This is a one-day declining-price sale venue. Enabled tokens can be kicked by anyone unless governance opts into restricted kicking, and one token cannot have two live sales at once.

[Feynman: Auction.price/_price (external context)] This computes the current sale price solely from the stored kick time, original lot size, and decay configuration; it returns zero only after expiry or when a configured price floor is crossed.

[Feynman: Auction.available (external context)] This reports at most the original lot size and returns zero when the stored sale is no longer active.

[Feynman: Auction.isActive (external context)] This labels a token's sale active whenever its computed price is positive, even if unrelated new tokens have since been transferred to the auction.

[Feynman: Auction.kickable (external context)] This returns zero during an active sale and otherwise exposes the auction's entire current token balance as the next possible lot.

[Feynman: Auction.kick/_kick (external context)] This optionally checks governance, rejects an already active token sale, snapshots the contract's full token balance as the new lot, and records the current timestamp. With the default permission setting, any account can kick donated dust.

[Inversion: Auction._kick (external context)] (1) Donate 1 wei and publicly kick to occupy the token's active slot. (2) Let the sale expire without taking the dust and kick the same balance again. (3) Front-run a strategy report with a dust kick so the strategy's later nested kick reverts.

[Feynman: Auction._take (external context)] This sends up to the stored lot to a buyer, collects the current USDS price from that buyer, and clears the kick timestamp only when the full available lot is taken.

[Feynman: Auction.forceKick (external context)] Governance can clear the old timestamp and immediately snapshot the current balance as a replacement sale.

[Feynman: Auction.settle (external context)] Anyone can clear the timestamp after all of the sale token has left the auction.

[Feynman: Auction.sweep (external context)] Governance can transfer the auction's entire balance of a chosen token to itself.

[Feynman: Auction.setGovernanceOnlyKick (external context)] Governance can decide whether future kicks are public or restricted.

[Feynman: TokenizedStrategy.report (external context)] A keeper-protected, reentrancy-protected report asks the strategy for its real USDS total, compares it with the prior stored total, applies fees or losses, updates profit locking, and stores the new total only if the whole call succeeds.

[Feynman: BaseHealthCheck.harvestAndReport (external context)] The strategy calls itself to run the in-scope harvest and then rejects the returned USDS total if it lies outside configured loss/profit bounds.

[Feynman: BaseHealthCheck._executeHealthCheck (external context)] This either consumes a one-report bypass or requires the new USDS total to remain within bounds derived from the prior report.

[Feynman: Setup.setUpAuction/defaultToAuction (test context)] The tests create an Auction with strategy management as auction governance, enable GROVE, install it on the strategy, and leave the Auction's default public-kick setting unchanged.

## Structured results

FINDING | contract: GroveCompounder | function: _harvestAndReport/_kickAuction | bug_class: permissionless-active-auction-report-dos | group_key: GroveCompounder | _harvestAndReport | permissionless-active-auction-report-dos
file: src/GroveCompounder.sol
path: arbitrary account -> transfer dust GROVE to configured Auction -> permissionless `Auction.kick(GROVE)` creates active sale -> keeper `report()` -> `_harvestAndReport()` -> `_kickAuction()` -> nested `Auction.kick()` reverts `too soon` -> complete report and reward claim roll back
input: The attacker controls the configured Auction's public `kick` timing and supplies only 1 wei of GROVE; the strategy merely needs more than `minAmountToSell[GROVE]` after claiming rewards.
assumption: The strategy assumes the Auction is idle whenever its own reward threshold is met, but `setAuction` checks only receiver/want and the shipped Auction defaults `governanceOnlyKick` to false.
proof: Start from a configured, GROVE-enabled Auction with no active sale and strategy claimable plus held rewards of `5_001e18` against the default `5_000e18` threshold. The attacker transfers 1 wei GROVE directly to Auction and calls its public `kick(GROVE)`; imported `Auction._kick` records `initialAvailable=1` and a nonzero `kicked` time. A keeper then calls `report()`. The strategy claims rewards, sees `toSwap=5_001e18`, transfers that amount to Auction, and calls `Auction.kick(GROVE)`. `Auction._kick` executes `require(!isActive(GROVE), "too soon")` and reverts, atomically undoing the transfer, claim, and TokenizedStrategy report. The attacker can front-run every report with this dust kick and, after expiry, re-kick the still-held dust, so reports remain unavailable without privileged reconfiguration. While reports are blocked, GROVE yield stays outside reported assets, so exiting holders can forfeit their share of accrued yield to holders remaining for a later report.
description: A permissionless dust auction can keep the external Auction active and make every above-threshold strategy report revert at the unconditional nested kick.
fix: Before transferring rewards, query the auction and skip/defer the kick while that token's auction is active (and preferably require governance-only kicking when an auction is configured).

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: zero-minimum-reward-swap | group_key: GroveCompounder | _harvestAndReport | zero-minimum-reward-swap
file: src/GroveCompounder.sol
path: searcher -> front-run GROVE/USDC price -> keeper `report()` -> `_harvestAndReport()` -> `_swapFrom(GROVE, USDC, fullRewardBalance, 0)` -> router accepts adversarial output -> PSM converts diminished USDC -> searcher back-runs and captures reward value
input: The attacker controls public-pool state and transaction ordering around a known keeper report; `useAuction` is false and the strategy has an above-threshold GROVE balance.
assumption: The direct route assumes any router output is acceptable and that generic report protection will detect a bad reward sale, even though the reward inventory was never included in the prior USDS asset total.
proof: Let the strategy hold `1_000_000e18` GROVE worth `13_065e18` USDS at a `0.013065` fair price. A searcher front-runs the report, moves the selected 1% pool price down, and arranges that the strategy's exact-input sale returns only `100e6` USDC. The in-scope call passes `_minAmountOut=0`, so the inherited router call accepts that output; `sellGem` turns it into about `100e18` USDS and the strategy reports that balance. Because the old report counted only staked and idle USDS, not the pending GROVE, the health check sees a small profit rather than the roughly `12,965e18` reward-value destruction. The searcher then reverses its price-moving trade and realizes the strategy's surrendered GROVE value.
description: Direct-mode reports sell the entire reward inventory with no minimum output, allowing transaction-ordering attacks to capture nearly all accrued yield without tripping asset-loss checks.
fix: Derive a nonzero minimum output from a manipulation-resistant quote with bounded slippage (or require a keeper-supplied checked minimum) and validate the USDC/USDS balance increase before completing the report.

FINDING | contract: GroveCompounderAprOracle | function: _grovePrice/_selectedV4Pool | bug_class: manipulable-single-block-spot-oracle | group_key: GroveCompounderAprOracle | _grovePrice | manipulable-single-block-spot-oracle
file: src/periphery/GroveCompounderAprOracle.sol
path: market actor -> move V3 spot or the sole usable V4 spot in one transaction -> downstream caller invokes `aprAfterDebtChange()` -> oracle accepts manipulated price under liquidity/median guards -> actor executes APR-sensitive action -> actor restores price/liquidity
input: The attacker controls swaps and concentrated-liquidity positions in public configured pools and chooses a spot price that produces an APR at or below `MAX_EXPECTED_APR`.
assumption: The code assumes raw current liquidity, a V3 token-balance floor, and a median over the subset of currently usable V4 pools make a current spot price manipulation-resistant; it neither requires multiple usable observations nor uses time-weighted/cross-venue validation.
proof: The V3 branch always wins when its two raw gates pass and its exact-one-GROVE spot simulation is positive, without comparison to V4. If V3 is unusable, V4 accepts `quoteCount=1`: `_medianPrice` returns that quote and `_withinV4PriceDeviation(price, price)` is necessarily true. A live audit-time check confirmed this is not hypothetical for the seeded defaults: V3 active liquidity was `0` and its USDC balance was `71` raw units; V4 pool IDs 1, 3, and 4 each had liquidity `0`, while pool 2 had `0x7f06d99543f92` (> `1e12`), so pool 2 alone defined and passed its own median. With the contemporaneous staking values `assets=209216803145709085130056726` and `rewardRate=38844495180111618467`, an attacker-set pool-2 square-root price of about `273875497017147571517187714147376626` yields `83,686` raw USDC for one GROVE, normalized to `83_686e12`; the oracle then returns `489995776909960542` (about 49.0% APR), which passes the 50% cap. The attacker can add narrow active liquidity at the target price to remain above `1e12`, let an APR-sensitive allocator consume the inflated quote, and remove/unwind in the same transaction. The inverse manipulation toward a tiny positive price is also accepted because no lower bound exists.
description: Both price routes consume current public-pool state, and the V4 median defense becomes a self-comparison whenever only one candidate is usable, allowing same-transaction APR manipulation.
fix: Use a sufficiently long TWAP and require agreement between at least two independently liquid venues (or a trusted external oracle), rejecting rather than self-validating when too few observations survive.

LEAD | contract: GroveCompounder | function: _harvestAndReport | bug_class: paused-staking-report-liveness | group_key: GroveCompounder | _harvestAndReport | paused-staking-report-liveness
code_smells: `availableDepositLimit` explicitly reacts to `STAKING.paused()`, but the final report-time redeploy checks only strategy shutdown. With more than `DUST` idle USDS, a staking pause can make `STAKING.stake` revert after reward claiming/selling and roll back the entire report.
description: A concrete `2e18` idle-USDS -> paused staking -> keeper report -> attempted restake trace blocks reporting, but the exact deployed staking contract's pause semantics and whether this dependency state is considered an accepted operational shutdown remain outside the in-scope source.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: reward-period-boundary-staleness | group_key: GroveCompounderAprOracle | aprAfterDebtChange | reward-period-boundary-staleness
code_smells: The expiration check is `block.timestamp > periodFinish()`, so at exact equality the function annualizes the still-stored `rewardRate` even though no future reward seconds remain; one second later it returns zero.
description: At `timestamp == periodFinish`, identical staking state can produce a positive annual APR followed by zero at the next timestamp, but an exploitable downstream action timed to this single boundary was not present in scope.

LEAD | contract: UniswapV3SwapSimulator | function: simulateExactInputSingle | bug_class: unsigned-to-signed-mode-flip | group_key: UniswapV3SwapSimulator | simulateExactInputSingle | unsigned-to-signed-mode-flip
code_smells: `uint256 params.amountIn` is cast to `int256` without enforcing `amountIn <= type(int256).max`; inputs above that boundary become negative and make `simulateSwap` run its exact-output branch even though the public API promises exact-input output.
description: For `amountIn=2^255+1`, the routine interprets the request as a large negative exact-output amount and returns required input as if it were output; the in-scope oracle always passes `1e18`, so no internal exploit path was established.

## X-ray claim reconciliation

- The source confirms the stated deposit/stake, withdrawal, auction-report, direct-swap/PSM, and APR-quote call paths.
- The source confirms the 25 listed guards, including the constructor-only pause check, zero-PSM-fee direct-route check, auction receiver/want snapshots, APR cap, V4 list checks, and simulator amount/price-limit checks.
- I-1 through I-3 are enforced by the enumerated write sites. I-4 is false in the declaration-time state (`useAuction=true`, `auction=0`) and manifests as fail-closed report liveness rather than direct asset loss. I-5 is not constructor-validated; the runtime safely falls back to V4 when the default V3 pool is absent/unusable.
- The orientation's reward-route asymmetry, public spot-pricing boundary, pause-state mismatch, and replicated V3 traversal are real review surfaces. Only the concrete paths above were promoted to findings/leads.
