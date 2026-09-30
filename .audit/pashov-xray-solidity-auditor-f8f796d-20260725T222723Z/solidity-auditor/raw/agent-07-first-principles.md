# Lane 7 — First-principles raw output

The x-ray document was used only as orientation. Every statement used below was checked against the bundled source or, where explicitly identified, narrowly read dependency code / live dependency state.

## Mental-tool transcript

[Feynman: GroveCompounder] This contract takes users' USDS, places it in one fixed rewards program, turns the GROVE earned there back into USDS, and counts the USDS still held or staked as the value backing its shares.

[Feynman: GroveCompounder.constructor] Deployment identifies USDS through the PSM wrapper, refuses to start if the rewards program is paused or accepts a different coin, grants the external programs spending permission, and chooses USDC plus the 1% GROVE/USDC market as the default direct-sale route.

[Socratic: GroveCompounder.sol:22 — why?] Why is auction mode selected before any auction has been named? The implicit belief is that management will finish venue setup before the reward balance first crosses the sale threshold.

[Inversion: GroveCompounder.constructor] (1) Let rewards exceed 5,000 GROVE before an auction is configured; the first report fails. (2) Let the external staking program become paused immediately after deployment; new deposits close but other calls retain dependency-specific behavior. (3) Make the selected 1% market absent or unusable before management switches to direct mode; reward realization fails.

[Feynman: balanceOfAsset] This reports how much unstaked USDS is sitting at the strategy address right now.

[Feynman: balanceOfStake] This reports how much USDS the external rewards program says belongs to the strategy.

[Feynman: balanceOfRewards] This reports how much GROVE has already reached the strategy address.

[Feynman: claimableRewards] This reports how much GROVE the rewards program currently attributes to the strategy but has not paid out yet.

[Feynman: _deployFunds] This sends the requested USDS into the fixed rewards program and attaches the current referral number.

[Socratic: GroveCompounder.sol:77 — why?] Why is the requested amount assumed to become the same-sized stake? The accounting relies on the external program accepting exact-transfer, non-rebasing USDS and crediting one stake unit per USDS unit.

[Feynman: _freeFunds] This asks the rewards program to return exactly the requested amount of staked USDS.

[Feynman: _harvestAndReport] This collects all earned GROVE, either sends it to the configured auction or sells it through the chosen Uniswap market and the PSM, stakes loose USDS when appropriate, and finally reports staked plus loose USDS as the strategy's backing.

[Socratic: GroveCompounder.sol:100 — why?] Why may the direct GROVE sale accept zero USDC? The code assumes the public pool price will remain economically fair throughout the keeper's transaction.

[Socratic: GroveCompounder.sol:109 — why?] Why is GROVE sent to an asynchronous auction before the strategy updates its accounting? The code assumes value returning later as USDS cannot be captured by shares minted in the meantime.

[Inversion: _harvestAndReport] (1) Front-run the keeper with a large deposit after rewards accrued, then retain the new shares through profit unlock. (2) Sandwich a 100,000 GROVE direct sale because its output floor is zero. (3) Keep a prior auction active while the strategy accumulates another threshold-sized reward balance so a report reaches the auction's "too soon" failure.

[Feynman: _emergencyWithdraw] This requests no more USDS than is currently staked and leaves any already-loose USDS alone.

[Feynman: availableDepositLimit] This closes deposits whenever the external rewards program says it is paused; otherwise it applies the inherited open-or-allowlisted deposit policy.

[Inversion: availableDepositLimit] (1) Open deposits and place unreported USDS in the strategy before minting shares. (2) Leave deposits closed but compromise an allowed receiver. (3) Change the external pause state between a quote and execution so the later deposit fails.

[Feynman: _min] This returns the smaller of two numbers.

[Feynman: claimRewards] This lets management collect GROVE into the strategy without yet selling it or recording it as USDS profit.

[Feynman: _claimRewards] This asks the fixed rewards program to pay all GROVE currently owed to the strategy.

[Feynman: kickAuction] This lets a keeper collect GROVE when applicable, inspect the full balance of any requested non-USDS token, and send that balance into the configured auction when it exceeds a threshold.

[Socratic: GroveCompounder.sol:169 — why?] Why is every requested token compared with the GROVE-denominated threshold? The implicit belief is that every auctioned token shares GROVE's decimals and economic scale, despite the function deliberately accepting arbitrary tokens.

[Inversion: kickAuction] (1) Pass USDS and rely on the downstream principal guard. (2) Pass a six-decimal token whose entire valuable balance can never exceed a 5,000e18 GROVE threshold. (3) Pass an enabled token while its previous sale is still active so the operation fails atomically.

[Feynman: _kickAuction] This refuses to move USDS, sends the entire requested token balance to a nonzero auction, and asks that auction to start a sale.

[Feynman: setMinAmountToSell] This lets management replace the minimum GROVE balance required before automatic selling.

[Feynman: setUniV3Fees] This lets management choose which GROVE/USDC Uniswap fee market the direct route will use.

[Feynman: setAuction] This lets management name an auction only when it promises to send USDS back to this strategy, or clear the address only while auction mode is off.

[Inversion: setAuction] (1) Supply a contract that answers the two identity questions correctly but later changes behavior. (2) Replace the auction while a prior sale is live; old proceeds still return, but operations now address another venue. (3) Try to clear it while auction mode remains selected; the guard correctly refuses.

[Feynman: setUseAuction] This switches between asynchronous auctions and immediate Uniswap sales, requiring a named auction before selecting auctions.

[Feynman: setReferral] This changes the small referral number attached to future stakes.

[Feynman: UniswapV3SwapSimulator] This helper reads an official Uniswap pool and predicts the output of one proposed swap without moving tokens.

[Feynman: simulateExactInputSingle] This finds the requested token pair's pool, works out which token occupies the lower address slot, replays a sale of the given input, and returns the amount of the other token that would leave the pool.

[Socratic: UniswapV3SwapSimulator.sol:39 — why?] Why is an unsigned input amount converted directly to a signed number? The helper assumes callers never provide more than the largest positive signed integer; the in-scope caller uses exactly 1e18.

[Inversion: simulateExactInputSingle] (1) Supply more than 2^255-1 so the number becomes negative and the replay changes meaning. (2) Select a fee with no pool so the first pool read fails. (3) place the pool at a boundary or without active liquidity so the replay traverses many empty ranges.

[Feynman: getPool] This asks the router which factory it trusts, then asks that factory for the pool belonging to the token pair and fee.

[Feynman: Simulate] This library copies the pool's price-walk rules so a caller can calculate a quote from the pool's current bookkeeping without executing the trade.

[Feynman: simulateSwap] This begins from the pool's current price and active liquidity, repeatedly walks toward the next initialized price boundary, accounts for input, output, fees, and liquidity changes, and stops when the requested amount or price limit is reached.

[Socratic: UniswapV3SwapSimulatorCore.sol:116 — why?] Why may remaining signed input be changed without overflow checks? The copied algorithm relies on official-pool bounds plus the caller's signed amount range to make the wraparound states unreachable.

[Inversion: simulateSwap] (1) Start with zero active liquidity and force traversal across empty words. (2) use a price immediately adjacent to the minimum while selling token zero. (3) use the largest negative signed amount and challenge the unchecked amount updates.

[Feynman: nextInitializedTickWithinOneWord] This searches one 256-position block in the requested direction and returns either the closest active boundary or the edge of that block.

[Feynman: tickBitmapPosition] This splits a compressed tick number into the storage-word number and the bit position within that word, including negative positions represented in two's-complement form.

[Socratic: UniswapV3SwapSimulatorCore.sol:185 — why?] Why is the remainder narrowed through a signed byte before becoming unsigned? It intentionally preserves the low eight bits for negative compressed ticks, matching the official pool bitmap layout.

[Feynman: GroveCompounderAprOracle] This contract estimates the annual GROVE reward value per USDS staked by combining live emissions, a live staking balance, and a live GROVE/USDC market price.

[Feynman: _onlyManagement] This accepts configuration changes only from the single address currently recorded as manager.

[Feynman: GroveCompounderAprOracle.constructor] Deployment makes the deployer manager and seeds four preselected V4 pool identifiers, all interpreted as USDC in slot zero and GROVE in slot one.

[Feynman: aprAfterDebtChange] This reads total USDS in the rewards program and GROVE paid per second, returns zero after emissions end, changes the stake total by the proposed debt movement, values a year of GROVE at the chosen spot price, divides by the changed stake, and refuses results above 50%.

[Socratic: GroveCompounderAprOracle.sol:109 — why?] Why is the strategy address unused? The code assumes this oracle is never asked about a strategy whose debt change is not an exact change to this same global staking pool.

[Socratic: GroveCompounderAprOracle.sol:114 — why?] Why does equality with the reward end time still use the old reward rate? The code assumes the boundary timestamp is economically equivalent to the final rewarding instant, although no future rewards remain then.

[Socratic: GroveCompounderAprOracle.sol:120 — why?] Why is the denominator read from live global stake? The code assumes an untrusted staker cannot cheaply change total stake around the consumer's call.

[Inversion: aprAfterDebtChange] (1) Temporarily stake 1 billion USDS before a consumer calls, depressing the quote, then withdraw it. (2) pass a negative movement larger than total global stake so subtraction fails. (3) push GROVE's spot price high enough that multiplication or the 50% cap makes the oracle unavailable.

[Feynman: setManagement] This replaces the sole oracle manager with another nonzero address in one step.

[Feynman: setUniV3Fee] This changes the V3 fee choice only if the fixed factory currently lists a pool for GROVE and USDC at that fee.

[Inversion: setUniV3Fee] (1) Choose an existing but empty pool; the guard accepts its address. (2) choose a live but economically tiny pool; the guard does not test depth. (3) choose a pool whose liquidity disappears immediately after configuration.

[Feynman: setUniV4Pool] This discards every V4 candidate and replaces them with one nonzero identifier plus a manager-supplied statement about which side contains GROVE.

[Feynman: setUniV4Pools] This replaces the V4 candidate list with a nonempty, equally sized list of identifiers and GROVE orientations.

[Feynman: addUniV4Pool] This appends one nonzero, not-already-listed V4 identifier and its stated orientation.

[Feynman: removeUniV4Pool] This removes one indexed V4 candidate by moving the last candidate into its place, while refusing to remove the final candidate.

[Feynman: uniV3Pool] This reveals the factory's current pool address for the configured V3 fee.

[Feynman: uniV4PoolCount] This reveals how many V4 candidates are configured.

[Feynman: uniV4Pool] This reveals one configured V4 identifier and its declared GROVE side.

[Feynman: groveUsdcV4PoolId] This reveals the first configured V4 identifier; configuration rules keep at least one entry present.

[Feynman: v4GroveIsToken0] This reveals whether the first candidate is configured with GROVE on side zero.

[Feynman: bestUniV4Pool] This returns the identifier, GROVE side, and raw active-liquidity number of the candidate the selection routine prefers.

[Feynman: selectedUniV4Pool] This returns the preferred V4 candidate together with the spot GROVE price derived from it.

[Feynman: _grovePrice] This first trusts any positive one-GROVE quote from a minimally usable V3 pool; only when that path is absent or fails does it use the selected V4 spot price, and it fails if neither path returns a positive value.

[Socratic: GroveCompounderAprOracle.sol:231 — why?] Why does one positive V3 quote override every V4 observation? The code assumes passing the two coarse V3 depth checks makes that one instantaneous price more trustworthy than all fallback evidence.

[Inversion: _grovePrice] (1) Move the V3 spot price just before the call while leaving both coarse gates satisfied. (2) drain V3 active liquidity to force the call onto a sole usable V4 pool. (3) raise the chosen price until the later 50% APR guard reverts instead of trying another source.

[Feynman: _v3PoolHasUsableLiquidity] This calls a V3 pool usable when it exists, reports at least 1e12 active-liquidity units, and physically holds at least 1,000 USDC.

[Socratic: GroveCompounderAprOracle.sol:242 — why?] Why do raw active liquidity and a transferable token balance prove economic depth? The code assumes those two independently manipulable quantities bound the cost of moving the one-block price.

[Feynman: _v4GrovePrice] This converts the pool's square-root price into the USDC received for one GROVE, using the configured side and then expanding six-decimal USDC into an 18-decimal price.

[Feynman: _selectedV4Pool] This gathers positive spot prices from candidates above a raw-liquidity floor, computes their median, rejects prices farther than 10% from that median, and returns the remaining candidate with the largest raw-liquidity number.

[Socratic: GroveCompounderAprOracle.sol:286 — why?] Why is a median computed even when only one candidate survived? The code assumes a single surviving market is self-validating: its price equals its own median and can never fail the deviation check.

[Inversion: _selectedV4Pool] (1) Leave only one pool at or above 1e12 liquidity and set its spot price; it automatically wins. (2) leave two pools and separate their prices far enough that neither is within 10% of their average, making selection return empty. (3) supply narrowly concentrated liquidity to an attacked pool so its raw liquidity is the largest among accepted quotes.

[Feynman: _medianPrice] This sorts the gathered prices and returns the middle one, or the average of the two middle prices when the count is even.

[Feynman: _withinV4PriceDeviation] This accepts a price when its absolute distance from the reference is no more than one tenth of the reference.

[Feynman: _setUniV4Pools] This validates a nonempty one-to-one configuration, rejects zero and repeated identifiers, then replaces the stored candidate list.

[Feynman: _hasUniV4Pool] This scans the configured identifiers and reports whether the requested one is already present.

[Feynman: _uniV3Pool] This resolves the current V3 pool address for the stored fee choice.

[Feynman: _uniV3PoolForFee] This asks the fixed router's factory for the GROVE/USDC pool associated with a fee.

[Feynman: _quoteToken1ForToken0] This turns a square-root pool price into the amount of side-one units corresponding to a chosen amount of side zero, using two equivalent calculation forms to avoid intermediate overflow.

[Feynman: _quoteToken0ForToken1] This turns a square-root pool price into the amount of side-zero units corresponding to a chosen amount of side one, again choosing the safe calculation form for the price's size.

### Dependency context opened for proof

[Feynman: UniswapV3Swapper._swapFrom] This spends the supplied input through the configured Uniswap market and passes the caller-supplied minimum output directly to the router; zero therefore permits any nonzero or even zero economic return the router accepts.

[Feynman: BaseStrategy._strategyTotalAssets] Unless a strategy replaces it, this returns only the last recorded asset number rather than reading what the strategy currently owns.

[Feynman: BaseHealthCheck.strategyTotalAssets] This asks the strategy for its current estimate and bounds it to the health-check interval; because Grove leaves the underlying estimator unchanged, the result remains the last recorded number.

[Feynman: BaseHealthCheck.availableDepositLimit] This permits deposits from everyone in open mode and only named receivers in closed mode.

[Feynman: TokenizedStrategy.deposit] This updates accounting from the strategy's current estimate, prices the deposit into shares, receives the user's USDS, and sends the loose balance into the strategy's deployment hook.

[Feynman: TokenizedStrategy._deposit] This receives the user's USDS, asks the strategy to deploy every loose USDS already present as well as the new deposit, adds only the user's deposit to the recorded asset number, and mints the precomputed shares.

[Feynman: TokenizedStrategy._accrue] This compares the strategy's current read-only estimate with the last recorded assets and immediately records any difference before a deposit, withdrawal, or report.

[Feynman: TokenizedStrategy.report] This first performs the read-only accounting update, then asks the strategy to realize and count assets, charges fees, and spreads newly reported profit to existing share holders over the configured unlock time.

[Feynman: Auction._take] This gives the buyer GROVE and pulls the required USDS payment from that buyer directly into the strategy receiver before ending a fully filled sale.

## Structured results

FINDING | contract: GroveCompounder | function: _harvestAndReport / inherited _strategyTotalAssets | bug_class: pre-report-value-capture | group_key: GroveCompounder | _harvestAndReport | pre-report-value-capture
path: public depositor or auction taker → Auction._take sends USDS to strategy (or GROVE accrues before a direct-sale report) → attacker deposits while shares still use lastTotalAssets → _deployFunds stakes both the unreported value and the new deposit but accounting adds only the deposit → keeper report recognizes the old value as profit → attacker retains shares through unlock and withdraws part of value earned before entry
assumption: A share minted immediately before a report cannot acquire a claim on value earned or received before that share existed.
violation: Grove does not replace BaseStrategy's last-report-only `_strategyTotalAssets`, even though auction payments can arrive asynchronously and claimable GROVE accrues continuously; when deposits are open, the inherited pre-deposit accrual therefore cannot see either source of pending value.
proof: Start with 1,000,000 USDS recorded/staked and 1,000,000 circulating shares. An auction buyer takes GROVE and pays 100,000 USDS to the strategy receiver; `lastTotalAssets` remains 1,000,000. The same actor deposits 9,000,000 USDS before the next keeper report. `_accrue` still reads 1,000,000, so the actor receives 9,000,000 shares at PPS 1; `_deposit` stakes the full 9,100,000 loose USDS while increasing recorded assets by only 9,000,000. The next report returns 10,100,000 assets and records 100,000 profit. With zero performance fee and after the configured profit unlock, PPS is 10,100,000 / 10,000,000 = 1.01, so the actor redeems for 9,090,000 USDS: 90,000 of their auction payment is recovered through newly minted shares. Pre-existing holders receive only 10,000 of the 100,000 payment instead of all of it. The same dilution works by depositing immediately before a direct-mode report that realizes already-accrued GROVE.
description: Open deposits are priced without asynchronous auction proceeds or accrued rewards, allowing a late depositor—and especially the auction taker who controls when proceeds arrive—to capture nearly all previously earned yield by temporarily dominating share supply.
fix: Override `_strategyTotalAssets` with at least `balanceOfStake() + balanceOfAsset()` and ensure accrued GROVE is conservatively reflected or realized before minting shares; otherwise keep direct deposits closed to parties that can enter around reward realization.

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: unbounded-reward-sale-output | group_key: GroveCompounder | _harvestAndReport | unbounded-reward-sale-output
path: MEV searcher → front-runs keeper's direct-mode report with GROVE sale → report calls `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` → strategy accepts the manipulated USDC output and converts it to USDS → searcher back-runs to restore price and retains the difference → strategy shareholders lose reward value
assumption: The public GROVE/USDC pool will quote an economically fair output during a known keeper transaction even when the strategy places no lower bound on output.
violation: The inherited swapper supports an output floor, but Grove hardcodes that floor to zero, and the health check only sees principal plus whatever positive reward output remains; it has no expectation for the value of GROVE sold.
proof: Consider a valid single-range 1%-fee pool state equivalent to 1,000,000 GROVE and 10,000 USDC reserves, and a report selling 100,000 GROVE (well above the 5,000 GROVE threshold). Without interference, the sale returns about 900.82 USDC. A searcher first sells 500,000 GROVE, receiving about 3,311.04 USDC and moving reserves to about 1,500,000 GROVE / 6,688.96 USDC. Grove's zero-floor sale then receives only about 414.14 USDC. Spending the 3,311.04 USDC in the back-run returns about 549,023.23 GROVE, leaving the searcher with about 49,023.23 GROVE net before gas while the strategy receives about 486.68 fewer USDS after the zero-fee PSM conversion. Because rewards were not part of prior `totalAssets`, the report still shows positive profit and the loss-side health check does not stop it.
description: A zero output floor lets a searcher extract a material portion of every direct-mode GROVE harvest by sandwiching the keeper's predictable sale.
fix: Derive and pass a nonzero minimum USDC output from a manipulation-resistant reference plus a bounded slippage setting, or require the keeper to provide a checked quote/deadline and default to auctions when a safe bound is unavailable.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice / _selectedV4Pool | bug_class: self-validating-spot-source | group_key: GroveCompounderAprOracle | _grovePrice | self-validating-spot-source
code_smells: V3 is accepted from a one-block 1-GROVE simulation whenever raw active liquidity is at least 1e12 and the pool token balance is at least 1,000 USDC; it is never compared with V4. On fallback, `quoteCount == 1` makes the sole price equal its own median, so it automatically passes the 10% test. Raw V4 liquidity is also trusted without token balances, time weighting, notional depth, or a minimum independent-source count. A latest-state dependency check found V3 active liquidity equal to zero and three of the four default V4 identifiers at zero liquidity, leaving only pool `0x9fe7...41f` usable with liquidity 2,234,678,351,511,442; in that state the supposed median reduces to one spot observation.
description: An attacker who moves the sole usable spot market can make a false price pass all source checks, while moving V3 high enough causes the later 50% APR cap to revert instead of falling back to sane V4 data; a concrete downstream value-extraction transaction was not present in scope, so consumer impact remains to be verified.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: transient-stake-denominator | group_key: GroveCompounderAprOracle | aprAfterDebtChange | transient-stake-denominator
code_smells: The denominator is the rewards program's instantaneous global `totalSupply`, which any ordinary staker can increase, and the oracle performs no time weighting or minimum holding-period check. At the inspected state, approximately 211.217 million USDS staked and the selected price produced about 7.58% APR; temporarily adding 1 billion USDS would reduce the same quote to about 1.32% before withdrawing again.
description: A same-transaction stake/call-consumer/withdraw sequence appears able to depress the advertised APR arbitrarily; the external staking implementation's exact same-transaction withdrawal behavior and a value-moving oracle consumer were outside the bundle and remain to be verified.

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: cross-token-threshold-mismatch | group_key: GroveCompounder | kickAuction | cross-token-threshold-mismatch
code_smells: For every `_token` other than GROVE, the function reads that token's balance but compares it to `minAmountToSell[REWARDS_TOKEN]`; the only public threshold setter also changes only the GROVE entry. A 1 WETH balance, for example, cannot pass the default 5,000e18 GROVE threshold even if an auction for WETH is enabled, while tokens with larger units can cross at unrelated economic values.
description: The arbitrary-token auction surface has no token-specific usable threshold and can strand valuable non-GROVE balances; no normal protocol path that deposits such a secondary token was established.

## Count

- FINDING: 2
- LEAD: 3
