# Lane 12 — Flow-Gap Raw Analysis

## Mandatory mental-tool trace

[Feynman: GroveCompounder] This strategy accepts USDS through its inherited vault interface, parks the USDS in Sky Rewards, collects GROVE incentives, and either auctions GROVE for USDS or trades GROVE through USDC before converting back to USDS. The fuzzy boundary is that settlement and accounting occur in external systems whose exact balance effects are assumed by the later steps.

[Feynman: GroveCompounder.constructor] Deployment binds the strategy asset to the wrapper's USDS token, checks the staking program is live and stakes that same token, grants unlimited spending permissions, and configures GROVE-to-USDC sales. It starts with auction mode selected even though no auction address has yet been installed.

[Feynman: balanceOfAsset] It reports how much idle USDS the strategy itself currently holds.

[Feynman: balanceOfStake] It reports how much USDS the staking program credits to this strategy.

[Feynman: balanceOfRewards] It reports how much GROVE is currently in the strategy wallet.

[Feynman: claimableRewards] It asks the staking program how much GROVE this strategy has earned but not yet collected.

[Feynman: _deployFunds] It hands a requested amount of USDS to the staking program and tags the deposit with the current referral code. It assumes the external stake operation credits exactly the amount removed from the strategy.

[Feynman: _freeFunds] It asks the staking program to return a requested amount of USDS. It assumes that successful completion makes that requested amount available to the inherited withdrawal flow.

[Feynman: _harvestAndReport] It collects rewards, conditionally sends GROVE down the selected sale route, stakes nearly all idle USDS while live, and reports staked plus idle USDS as strategy assets. The fuzzy point is whether sale proceeds arrive synchronously and whether the report observes all economically owned assets.

[Feynman: _emergencyWithdraw] It limits an emergency request to the currently recorded stake and asks the staking program to return that amount.

[Feynman: availableDepositLimit] It refuses new deposits while the staking program says it is paused, otherwise it inherits the normal limit.

[Feynman: _min] It returns the smaller of two numbers.

[Feynman: claimRewards] It lets management collect accrued GROVE into the strategy without selling it.

[Feynman: _claimRewards] It asks the staking program to move this strategy's earned GROVE into the strategy wallet.

[Feynman: kickAuction] It lets an authorized operator collect GROVE when appropriate, measure the selected token balance, and send that balance to the configured auction if the threshold test passes. The fuzzy point is that the threshold is read from the GROVE entry even when the selected token is not GROVE.

[Feynman: _kickAuction] It refuses to auction USDS, sends the entire supplied balance of another token to the configured auction, and tells the auction to begin selling that token.

[Feynman: setMinAmountToSell] It lets management change the minimum GROVE balance that triggers a sale.

[Feynman: setUniV3Fees] It lets management choose which Uniswap V3 fee tier the strategy will use for GROVE-to-USDC trades.

[Feynman: setAuction] It lets management select an auction only if that auction says it pays this strategy in USDS, and only permits clearing the address after auction mode is disabled.

[Feynman: setUseAuction] It chooses between auction and direct trading, requiring an auction address before choosing auction mode.

[Feynman: setReferral] It changes the referral number attached to future stakes.

[Inversion: _harvestAndReport] (1) Reach the reward threshold while `useAuction=true` and `auction=0`; (2) place pre-existing USDC in the strategy before the direct route converts its entire balance; (3) make the V3 sale succeed with negligible output because the call supplies zero minimum output.

[Inversion: kickAuction] (1) Ask to auction a non-GROVE token whose decimals/value do not match the GROVE threshold; (2) select a token with a hostile transfer callback; (3) use an auction whose advertised receiver/want remain correct while its later sale behavior changes.

[Feynman: UniswapV3SwapSimulator] This quoting helper reconstructs the result of a one-pool Uniswap V3 trade by reading the pool selected by the router's factory. It does not execute the trade or protect the state from changing after the read.

[Feynman: simulateExactInputSingle] It finds the configured pool, chooses trade direction from token ordering, simulates spending the exact input through the pool, and returns the output side as a positive number. It assumes the pool exists and follows the expected V3 interface.

[Feynman: getPool] It asks the router for its factory and asks that factory which pool corresponds to the two tokens and fee.

[Inversion: simulateExactInputSingle] (1) Resolve a missing pool and force the quote path to fail; (2) leave enough headline liquidity while concentrating it so the fixed one-GROVE trade suffers heavy price movement; (3) shift pool price in the same transaction before the consumer reads it.

[Feynman: Simulate] This library replays Uniswap V3's price movement, fee charging, and liquidity changes using only live pool reads so callers can estimate a trade without sending tokens.

[Feynman: simulateSwap] It starts from the pool's current price, tick, liquidity, fee, and spacing, walks through price ranges until the requested amount is consumed or the price limit is reached, and returns the token changes implied by that walk. The fuzzy point is faithful equivalence with the external pool across every boundary and rounding case.

[Feynman: nextInitializedTickWithinOneWord] It searches the pool's compact tick map in the trade direction and returns the next initialized boundary or the edge of the current word.

[Feynman: tickBitmapPosition] It maps a compressed tick number to the word and bit where the pool records whether that tick is initialized.

[Socratic: UniswapV3SwapSimulatorCore.sol:108 — why?] Why are signed remaining-amount updates unchecked? The implicit belief is that upstream swap-step arithmetic and the exact-input sign convention make overflow or crossing zero impossible before the loop condition is evaluated.

[Inversion: simulateSwap] (1) Start exactly adjacent to a tick word boundary; (2) cross a tick carrying the largest permitted negative liquidity change; (3) choose price/amount values that maximize fee-rounding so the remaining signed amount approaches zero from the wrong side.

[Feynman: GroveCompounderAprOracle] This contract estimates annual GROVE rewards per adjusted staked USDS and converts the GROVE amount to USDS using one V3 market first or a configured group of V4 observations as fallback. The fuzzy point is whether its market-quality gates make the returned spot-derived value safe for downstream allocation decisions.

[Feynman: _onlyManagement] It rejects configuration calls from anyone other than the single recorded manager.

[Feynman: GroveCompounderAprOracle.constructor] It makes the deployer manager and installs four fixed V4 pool identifiers, all interpreted with GROVE as the second token.

[Feynman: aprAfterDebtChange] It reads total external stake and reward speed, returns zero after rewards end, finds a GROVE price, hypothetically adds or subtracts a debt change from total stake, divides annual reward value by the adjusted stake, and rejects results above fifty percent. It ignores the strategy address argument.

[Feynman: setManagement] It immediately hands oracle configuration power to a nonzero new address.

[Feynman: setUniV3Fee] It changes the V3 fee tier only when the router's factory currently lists a pool for that tier.

[Feynman: setUniV4Pool] It replaces every V4 candidate with one nonzero identifier and a caller-supplied interpretation of token order.

[Feynman: setUniV4Pools] It delegates replacement of the V4 candidate list to a checked bulk helper.

[Feynman: addUniV4Pool] It appends a nonzero, not-yet-listed V4 identifier and a caller-supplied token orientation.

[Feynman: removeUniV4Pool] It removes one candidate by replacing it with the last candidate and shortening the list, while preserving at least one entry.

[Feynman: uniV3Pool] It exposes the pool currently resolved for the configured V3 fee.

[Feynman: uniV4PoolCount] It exposes how many V4 candidates are configured.

[Feynman: uniV4Pool] It exposes one candidate's identifier and claimed GROVE position.

[Feynman: groveUsdcV4PoolId] It exposes the first candidate's identifier for compatibility with consumers expecting a single pool.

[Feynman: v4GroveIsToken0] It exposes the first candidate's claimed token orientation for compatibility with consumers expecting a single pool.

[Feynman: bestUniV4Pool] It exposes the identity, orientation, and liquidity of the candidate selected by the internal filtering process.

[Feynman: selectedUniV4Pool] It exposes the selected V4 candidate together with the derived price.

[Feynman: _grovePrice] It trusts a V3 quote when the chosen pool passes raw liquidity and USDC-balance checks; if quoting fails or returns zero, it uses the selected V4 candidate; if neither works it refuses to quote.

[Feynman: _v3PoolHasUsableLiquidity] It considers the V3 pool usable if it exists, reports at least a fixed amount of active liquidity, and physically holds at least one thousand USDC.

[Feynman: _v4GrovePrice] It converts the V4 square-root price into the amount of USDC corresponding to one GROVE, using the configured token orientation and then normalizing six USDC decimals to eighteen.

[Feynman: _selectedV4Pool] It collects nonzero prices from candidates with enough reported active liquidity, computes their median, discards observations more than ten percent away, and returns the most liquid survivor. The fuzzy point is that pool identifiers and orientation are trusted configuration, and raw liquidity from different pool geometries is treated as directly comparable.

[Feynman: _medianPrice] It sorts the collected prices and returns the middle price, or the midpoint of the two middle prices.

[Feynman: _withinV4PriceDeviation] It accepts a price whose absolute distance from a reference is no more than ten percent of that reference.

[Feynman: _setUniV4Pools] It replaces the candidate list with a nonempty, equal-length list of unique nonzero identifiers and caller-supplied token orientations.

[Feynman: _hasUniV4Pool] It scans the configured candidates and says whether an identifier already appears.

[Feynman: _uniV3Pool] It resolves the GROVE/USDC pool for the currently configured fee.

[Feynman: _uniV3PoolForFee] It asks the router's factory for the pool address corresponding to GROVE, USDC, and a fee.

[Feynman: _quoteToken1ForToken0] It squares the encoded V4 price and calculates how many units of the second token correspond to a chosen amount of the first token while avoiding intermediate overflow.

[Feynman: _quoteToken0ForToken1] It takes the inverse of the squared encoded V4 price to calculate how many units of the first token correspond to a chosen amount of the second token while avoiding intermediate overflow.

[Socratic: GroveCompounderAprOracle.sol:113 — why?] Why is `_strategy` accepted but ignored? The implicit belief is that every strategy consumer shares the same global Sky staking economics, so strategy-specific state cannot affect the projected APR.

[Socratic: GroveCompounderAprOracle.sol:238 — why?] Why do raw active liquidity and token balance prove a one-GROVE V3 quote is representative? The implicit belief is that these units jointly lower-bound executable depth closely enough despite token order, current tick, and concentrated range placement.

[Socratic: GroveCompounderAprOracle.sol:280 — why?] Why does the median of all configured candidate quotes form a trustworthy reference? The implicit belief is that a majority of configured pools represent independent markets rather than correlated or attacker-created observations.

[Inversion: _grovePrice] (1) Manipulate the V3 spot while keeping the raw gates satisfied; (2) make the V3 simulation revert so control falls into a weaker V4 candidate set; (3) manipulate enough V4 candidates to control the median and make the deepest manipulated quote win.

[Inversion: aprAfterDebtChange] (1) Supply a negative delta larger than total external stake; (2) supply a positive delta near the signed maximum so unsigned addition overflows; (3) manipulate the peripheral reward price while keeping the computed APR just below the hard cap.

[Inversion: _selectedV4Pool] (1) Configure multiple identifiers pointing to markets sharing the same manipulable price source; (2) make an attacker pool report higher raw liquidity than honest pools; (3) move two middle observations so the even-sized median admits a manipulated cluster.

## Findings and leads

## Targeted dependency-boundary trace

[Feynman: UniswapV3Swapper._swapFrom] It authorizes the Uniswap router to spend the requested input, uses one hop when either side is USDC, and asks the router to trade the exact input for no less than the caller's chosen output floor. GroveCompounder passes an output floor of zero, so successful execution says nothing about retained value.

[Feynman: UniswapV3Swapper._checkAllowance] It raises the router's token-spending permission to the requested amount when the current permission is smaller.

[Feynman: Auction.kick] It starts a sale for an enabled token only when no sale is already active and snapshots the auction's entire current token balance as available inventory.

[Feynman: Auction._take] It calculates a buyer's payment from the snapshotted sale, sends the purchased token first, optionally lets the receiver run arbitrary code, then pulls USDS from the buyer directly into the strategy and closes the sale when fully consumed. The transaction-wide rollback protects the token send if payment fails, while the callback can still act against external systems before payment is collected.

[Inversion: Auction._take] (1) Use the receiver callback to interact with the strategy while USDS payment has not yet arrived; (2) partially buy just below the full available amount so the auction remains active; (3) make the auction's live token balance lower than its initial snapshot before a take.

[Feynman: TokenizedStrategy.deposit] It synchronizes accounting, turns a maximum-number request into the sender's whole asset balance, calculates shares at the current price, then moves and deploys the assets before recording the deposit.

[Feynman: TokenizedStrategy._deposit] It pulls the stated USDS amount, asks the strategy to stake every idle USDS unit it can see, then increases recorded assets by the originally stated amount and creates the calculated shares. The seam assumes the external token transfer and staking call preserve the stated amount.

[Feynman: TokenizedStrategy._withdraw] It checks permissions, measures idle USDS, asks the strategy to free any shortfall, treats a remaining shortfall as user-realized loss, reduces recorded assets, destroys shares, and sends the available USDS to the receiver.

[Feynman: TokenizedStrategy._accrue] Once per block it compares the strategy's read-only asset estimate with recorded assets, realizes any profit or loss and fees, and stores the new estimate. GroveCompounder's inherited estimate intentionally returns the prior recorded value, so only explicit reports discover its external rewards.

[Feynman: TokenizedStrategy.report] It first performs ordinary accounting synchronization, then calls the strategy's mutable harvest hook, compares the returned asset total to the recorded total, charges fees or realizes loss, adjusts profit-locking shares, and stores the new total.

[Feynman: BaseHealthCheck.harvestAndReport] It calls GroveCompounder's harvest routine and then rejects the entire report when the returned asset total falls outside management-configured profit and loss bounds.

[Feynman: BaseHealthCheck.strategyTotalAssets] It presents the strategy's read-only estimate after forcing it inside health-check bounds; because GroveCompounder keeps the default prior-report estimate, the clamp does not introduce live market accounting here.

[Feynman: TokenizedStrategy.emergencyWithdraw] It lets an emergency authority ask the strategy to free assets only after pause or shutdown, deliberately leaving recorded accounting unchanged until a later synchronization.

[Inversion: TokenizedStrategy.report] (1) Let an auction payment arrive after a previous zero-profit report and front-run the next report with a deposit; (2) make direct reward conversion return almost no USDC while every external call succeeds; (3) make a reward-sale external call reenter a custom unguarded strategy entry point while the inherited report guard is active.

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: auction-callback-profit-dilution | group_key: GroveCompounder | _harvestAndReport | auction-callback-profit-dilution
seam: three-way (execution × periphery × first-principles)
path: an auction buyer calls `Auction.take(..., attackerReceiver, nonemptyData)` → `Auction._take` sends the already-earned GROVE and invokes `attackerReceiver.auctionTakeCallback` before collecting USDS → the callback calls the open strategy's inherited `deposit` → the inherited report-boundary `_strategyTotalAssets()` still returns `lastTotalAssets`, so the deposit mints shares without pricing the imminent auction proceeds → `_take` resumes and transfers the buyer's USDS payment directly to the strategy → a later keeper `report` recognizes and locks those proceeds as profit for both incumbent and attacker shares → after unlock the buyer redeems part of the strategy's pre-deposit reward proceeds
periphery_interaction: `GroveCompounder._kickAuction` moves GROVE to the configured Yearn `Auction`; its `_take` implementation transfers GROVE and executes an arbitrary receiver callback before `safeTransferFrom(msg.sender, receiver, needed)` credits USDS to GroveCompounder.
violated_principle: proceeds from GROVE earned before a depositor entered must accrue to the shares that bore the capital exposure that generated those rewards; an auction buyer must not be able to insert itself into the ownership set between delivery of the earned reward and payment of its proceeds.
proof: Assume no locked shares, `lastTotalAssets = totalSupply = 1,000,000e18`, and a live GROVE auction whose full take requires `100,000e18` USDS. The buyer calls the four-argument `take` with nonempty callback data. During the callback it deposits `1,000,000e18` USDS. `deposit` first calls `_accrue`, but GroveCompounder does not override `BaseStrategy._strategyTotalAssets`, so the estimate remains the old `1,000,000e18`; the buyer therefore receives `1,000,000e18` shares, and `_deposit` records only its deposit, setting `lastTotalAssets` to `2,000,000e18`. After the callback, `_take` pays `100,000e18` USDS to the strategy. The next report stakes that idle payment and returns `2,100,000e18`; the default health check accepts it because it is only 5% above the new recorded total. With the default 10% performance fee, report mints `10,000e18` fee shares and `90,000e18` locked shares. After the 10-day unlock, effective supply is `2,010,000e18`, PPS is `2,100,000 / 2,010,000 = 1.044776...`, and the buyer's shares redeem for about `1,044,776e18` USDS: a roughly `44,776e18` gain in addition to the GROVE it bought. Without the callback deposit, the incumbent's `1,000,000e18` shares would redeem for about `1,089,108e18`; with the attack they redeem for only `1,044,776e18`, demonstrating a roughly `44,332e18` value shift. The buyer needs no privileged role, and the exact ordering is guaranteed inside one `take` transaction whenever deposits are open.
description: The auction's callback-before-payment ordering composes with GroveCompounder's stale report-boundary accounting to let an untrusted auction buyer mint shares immediately before pre-existing reward proceeds arrive and thereby dilute incumbent holders.
fix: Track an `auctionPending` state from kick through the first post-settlement report and return a zero deposit limit while it is set, clearing it only after received proceeds have been included in `lastTotalAssets`; if deposits must remain open, use an auction that pays before callbacks together with a live staked-plus-idle `_strategyTotalAssets` implementation.

[Socratic: Auction.sol:596 — why?] Why may the reward buyer execute arbitrary code after receiving GROVE but before its USDS payment reaches the strategy? The implicit belief is that transaction rollback protects all relevant invariants, overlooking time-sensitive share pricing in the external receiver.

[Inversion: auction settlement plus deposit] (1) Make the auction buyer itself the callback receiver and deposit during the callback; (2) make a partial take, deposit before that payment, and repeat across later partial fills; (3) take the final lot immediately before a scheduled keeper report so the attacker's capital waits the minimum practical time before profit locking begins.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: v3-spot-precedence-manipulation | group_key: GroveCompounderAprOracle | _grovePrice | v3-spot-precedence-manipulation
seam: three-way (execution × periphery × first-principles)
code_smells: When the canonical V3 pool merely reports `liquidity >= 1e12` and holds `>= 1,000e6` USDC, `_grovePrice` accepts its single live one-GROVE swap quote immediately and never compares it with the four V4 observations. The USDC-balance gate can be inflated by a direct token transfer and neither gate constrains spot-price deviation or manipulation cost. A same-transaction actor can move V3 spot, cause the simulator to return that manipulated quote, call a downstream consumer, and restore the pool while keeping the APR below the 50% cap.
description: The execution path gives a manipulable peripheral V3 observation absolute precedence over the median-filtered fallback, but no in-scope state-changing APR consumer establishes a concrete value-extraction sink.

LEAD | contract: GroveCompounder | function: _harvestAndReport | bug_class: active-auction-report-blocking | group_key: GroveCompounder | _harvestAndReport | active-auction-report-blocking
seam: execution × periphery
code_smells: While a GROVE auction is active, any new strategy GROVE balance above the threshold makes `_harvestAndReport` transfer the balance and call `Auction.kick`; `Auction._kick` rejects because `isActive(GROVE)` is true, rolling back the whole report. An untrusted account can ensure the branch is taken by donating enough GROVE immediately before a keeper report, even if organically accrued rewards are below threshold.
description: A public token donation can compose with the auction's external active-state guard to block reports during the active auction window, but the bounded one-day window and concrete operational impact were not established strongly enough for a finding.

## Post-proof dependency check

[Feynman: TokenizedStrategy._convertToShares] It prices a requested asset amount against the same simulated supply and asset totals used by the strategy's public accounting views. In the callback trace those totals contain the attacker's deposit but cannot contain the auction payment that has not happened yet.

[Feynman: TokenizedStrategy._maxDeposit] It blocks deposits only for shutdown, pause, a strategy-owned receiver, or a strategy-defined limit. GroveCompounder's open-mode limit has no awareness of an active auction, so the auction buyer's callback deposit is admitted.

[Feynman: TokenizedStrategy._unlockedShares] It calculates how many strategy-owned profit-locking shares have aged out of effective supply, excluding the full remaining strategy balance after the unlock date. This confirms that the attacker's ordinary shares participate in the auction profit as the locking shares disappear.

[Inversion: GroveCompounder.availableDepositLimit] (1) Deposit from the auction receiver while the auction remains active; (2) use a normal external receiver so the inherited self-receiver check does not fire; (3) wait until management has enabled open deposits, after which neither token balance nor auction state reduces the limit.

## Lane summary

- FINDING count: 1
- LEAD count: 2
- Primary seam: auction callback ordering × report-boundary share accounting × incumbent reward ownership
