# Economic-security lane — raw output

## Mandatory mental-tool trace

[Feynman: GroveCompounder] This strategy takes depositors' USDS, places it in the fixed Sky staking pool, collects GROVE rewards, and either sends those rewards to a Dutch auction or sells them through Uniswap before turning the proceeds back into USDS.

[Feynman: GroveCompounder.constructor] Deployment binds the strategy to the hard-coded staking pool and PSM wrapper, rejects a paused or mismatched staking pool, gives those dependencies spending authority, and chooses USDC plus the 1% GROVE/USDC route as the direct-sale defaults.

[Inversion: GroveCompounder.constructor] (1) Deploy while staking is unpaused and pause it immediately afterward; (2) let the PSM remain the expected address but later charge a fee or halt; (3) leave the default `useAuction=true` state while `auction` is still zero.

[Feynman: balanceOfAsset] This reports how much loose USDS the strategy currently holds outside staking.

[Feynman: balanceOfStake] This asks the external staking pool how much USDS principal belongs to the strategy.

[Feynman: balanceOfRewards] This reports how many already-claimed GROVE tokens remain at the strategy.

[Feynman: claimableRewards] This reports how many additional GROVE tokens the staking pool says the strategy may collect.

[Feynman: _deployFunds] This sends a requested amount of USDS into the staking pool and associates the configured referral code with that stake.

[Inversion: _deployFunds] (1) Pause staking after the deposit-limit check but before staking; (2) make the staking dependency accept less than requested; (3) make the external stake call revert after an otherwise valid share deposit.

[Feynman: _freeFunds] This asks the staking pool to return a requested amount of the strategy's USDS.

[Inversion: _freeFunds] (1) Pause or blacklist withdrawals at the dependency; (2) return less USDS than the recorded stake reduction; (3) make a large withdrawal fail while a smaller withdrawal would work.

[Feynman: _harvestAndReport] This collects GROVE, sells it when the balance clears the configured threshold, stakes any resulting loose USDS, and tells the share-accounting system only about USDS that is currently loose or staked.

[Socratic: src/GroveCompounder.sol:107-117 — why?] Why are claimed GROVE moved into an auction, and therefore removed from strategy custody, while the returned asset count assigns that pending sale no value? The implicit belief is that no share issuance or redemption between auction kick, settlement, and the next report can transfer ownership of that value.

[Socratic: src/GroveCompounder.sol:102-104 — why?] Why does the direct path convert the entire loose USDC balance rather than only the swap output? It assumes every USDC unit at the strategy is intended for this conversion and the PSM can process the whole balance in one call.

[Socratic: src/GroveCompounder.sol:98 — why?] Why is a zero `tin` observation enough to make the PSM route safe? It assumes that the fee cannot change inside the call and that no other capacity, halt, or output condition matters.

[Inversion: _harvestAndReport] (1) Deposit immediately before the reward-claim/report transaction; (2) settle the public auction, then deposit while the received USDS is still absent from recorded assets; (3) deposit while GROVE sits in the auction, wait for settlement and profit unlock, then redeem the acquired portion of incumbents' reward.

[Feynman: _emergencyWithdraw] This returns up to the smaller of the requested amount and the strategy's actual external stake, leaving any excess request unfulfilled rather than failing on the strategy's own arithmetic.

[Feynman: availableDepositLimit] This closes new deposits whenever the external staking pool says it is paused and otherwise defers to the inherited deposit policy.

[Inversion: availableDepositLimit] (1) Pause immediately after the view is read; (2) leave staking unpaused but make `stake` revert for another dependency reason; (3) transfer USDS directly to the strategy without using the deposit path.

[Feynman: _min] This returns the smaller of two numbers.

[Feynman: claimRewards] This lets management collect the strategy's pending GROVE without selling it.

[Feynman: _claimRewards] This asks the staking dependency to send all currently earned rewards to the strategy.

[Feynman: kickAuction] This lets an authorized keeper collect GROVE when requested, measure the chosen token's full strategy balance, and start its sale if that balance clears the GROVE-sized threshold.

[Socratic: src/GroveCompounder.sol:168 — why?] Why is every `_token` compared against `minAmountToSell[REWARDS_TOKEN]` rather than its own threshold? The code assumes non-GROVE manual auctions either share GROVE's decimals/economics or are operational recovery only.

[Inversion: kickAuction] (1) Pass the principal token and rely on the inner rejection; (2) pass an enabled non-GROVE token with very different decimals; (3) call while the same token's previous auction remains active so the kick reverts atomically.

[Feynman: _kickAuction] This refuses to sell USDS, requires a configured auction, transfers the entire selected token balance to that auction, and asks the auction to begin selling it.

[Inversion: _kickAuction] (1) Set the auction to zero; (2) use the asset itself; (3) configure a receiver correctly, mutate that receiver later through the external auction's governance, and then kick.

[Feynman: setMinAmountToSell] This lets management choose how much GROVE must accumulate before an automatic or manual sale is worthwhile.

[Feynman: setUniV3Fees] This lets management choose the Uniswap V3 fee tier that the direct GROVE-to-USDC sale will address.

[Feynman: setAuction] This lets management choose an auction only if it currently pays this strategy in USDS, or clear the auction only after auction mode has been disabled.

[Inversion: setAuction] (1) Supply a contract whose receiver is wrong; (2) supply one whose payment token is wrong; (3) pass validation and later change the auction receiver through the auction's separate authority.

[Feynman: setUseAuction] This switches reward realization between the configured auction and direct Uniswap/PSM conversion, and refuses to enable auction mode without an address.

[Inversion: setUseAuction] (1) Enable auction mode before setting an auction; (2) clear the auction while auction mode remains on; (3) switch to direct mode when its configured V3 pool has no active liquidity.

[Feynman: setReferral] This lets management replace the referral number attached to future stakes.

[Feynman: UniswapV3SwapSimulator] This helper estimates a V3 swap by replaying the pool's current price and liquidity state without moving tokens.

[Feynman: simulateExactInputSingle] This finds the requested fee-tier pool, determines which token is first in that pool, walks an exact-input sale to the chosen price boundary, and returns the predicted amount of the other token.

[Inversion: simulateExactInputSingle] (1) Resolve a nonexistent pool; (2) point at a pool with no active liquidity and sparse initialized price ranges; (3) manipulate the pool immediately before an on-chain consumer reads the result.

[Feynman: getPool] This asks the router for its factory and asks that factory for the unique pool matching the two tokens and fee tier.

[Feynman: Simulate] This library reproduces how a V3 pool moves across price ranges so another contract can obtain a quote from current state.

[Feynman: simulateSwap] This starts at the pool's current price and active liquidity, repeatedly moves to the next price boundary while consuming the requested input, adjusts liquidity when positions begin or end, and returns the two token changes.

[Socratic: src/libraries/UniswapV3SwapSimulatorCore.sol:106-161 — why?] Why is a potentially long sparse-range walk acceptable inside an oracle read? It assumes the configured pool's initialized ranges make the copied traversal both affordable and terminating within consumer gas limits.

[Inversion: simulateSwap] (1) Put the current price beside an extreme boundary; (2) create many initialized boundaries that maximize loop work; (3) leave zero active liquidity across many words so price moves without consuming the requested input.

[Feynman: nextInitializedTickWithinOneWord] This examines one compact block of price-range flags, finds the nearest initialized boundary in the swap direction, and otherwise returns the edge of that block.

[Feynman: tickBitmapPosition] This converts a compressed signed price index into the storage word and bit that represent it.

[Feynman: GroveCompounderAprOracle] This oracle annualizes the staking pool's GROVE emissions, values GROVE from current Uniswap state, divides by the staking pool's adjusted total USDS, and caps the returned APR at 50%.

[Feynman: _onlyManagement] This rejects configuration changes from every address except the oracle's current manager.

[Feynman: GroveCompounderAprOracle.constructor] Deployment assigns the deployer as manager and installs four fixed V4 pool identifiers, all interpreted as USDC-first and GROVE-second.

[Inversion: GroveCompounderAprOracle.constructor] (1) Let three default pools lose all active liquidity; (2) let only one manipulable pool remain; (3) let a default pool's hook or economics change while its identifier remains configured.

[Feynman: aprAfterDebtChange] This reads global staking principal and GROVE emissions, returns zero after emissions finish, changes the denominator by the proposed debt movement, values emissions at the current GROVE price, and rejects a result above 50%.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:111 — why?] Why is `_strategy` ignored? The oracle assumes every authorized consumer binds this instance only to a strategy whose debt movement lands in this exact global staking pool.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:122-126 — why?] Why may any signed debt change be subtracted directly from global supply? It assumes callers never request a withdrawal larger than the pool and never pass the smallest signed integer.

[Inversion: aprAfterDebtChange] (1) Push the spot GROVE price just above the 50% cap to force a revert; (2) pass a negative delta larger than global stake; (3) bind the oracle to an unrelated strategy and obtain an apparently valid but unrelated APR.

[Feynman: setManagement] This immediately hands all future oracle configuration power to a nonzero successor.

[Feynman: setUniV3Fee] This changes the preferred V3 fee tier only when the factory currently returns a pool for GROVE and USDC.

[Feynman: setUniV4Pool] This replaces all fallback markets with one manager-selected pool and a manager-supplied direction for interpreting its price.

[Feynman: setUniV4Pools] This replaces the fallback set with the supplied list after the shared validation routine accepts it.

[Feynman: addUniV4Pool] This appends one nonzero pool identifier if it is not already in the list.

[Feynman: removeUniV4Pool] This removes one chosen candidate by replacing it with the final candidate, while refusing to remove the last remaining pool.

[Feynman: uniV3Pool] This reports the factory pool currently selected by the configured V3 fee tier.

[Feynman: uniV4PoolCount] This reports how many fallback V4 candidates are configured.

[Feynman: uniV4Pool] This reports one candidate's identifier and the direction in which its price will be interpreted.

[Feynman: groveUsdcV4PoolId] This reports the first configured V4 candidate for compatibility with single-pool callers.

[Feynman: v4GroveIsToken0] This reports the first candidate's configured GROVE direction.

[Feynman: bestUniV4Pool] This reports the identifier, direction, and active liquidity of the V4 candidate selected by the internal filter.

[Feynman: selectedUniV4Pool] This reports the complete selected V4 candidate, including the price the oracle would use.

[Feynman: _grovePrice] This trusts a simulated one-GROVE V3 sale whenever the V3 pool clears two coarse gates, otherwise asks the V4 selector for a current spot price, and fails if neither route returns a positive number.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:223 — why?] Why is the first positive V3 quote accepted without comparison to any V4 market or time average? It assumes active liquidity and a $1,000 token balance make the same-block spot quote economically trustworthy.

[Inversion: _grovePrice] (1) Manipulate V3 while keeping active liquidity above `1e12`; (2) move V3 out of active liquidity so the oracle silently changes sources; (3) leave only one V4 quote usable and manipulate that single spot.

[Feynman: _v3PoolHasUsableLiquidity] This accepts a V3 pool when it exists, has at least `1e12` units of active liquidity, and physically holds at least 1,000 USDC.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:239-245 — why?] Why do raw active-liquidity units and total USDC balance establish manipulation resistance? The implicit assumption is that neither narrow ranges nor out-of-range balances can satisfy the gates cheaply.

[Inversion: _v3PoolHasUsableLiquidity] (1) Donate 1,000 USDC that is not active liquidity; (2) create very narrow active liquidity whose raw value clears `1e12`; (3) shift price within the active range while leaving both gates true.

[Feynman: _v4GrovePrice] This turns a pool's square-root price into the amount of six-decimal USDC corresponding to one eighteen-decimal GROVE, using the configured token direction, then expresses that answer with eighteen decimals.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:247-253 — why?] Why is a manager-supplied direction trusted separately from the opaque pool identifier? The code assumes configuration always matches the pool's actual currencies.

[Feynman: _selectedV4Pool] This gathers every candidate with at least `1e12` active-liquidity units and a nonzero spot price, computes the median of whatever candidates survived, discards quotes farther than 10% from that median, and returns the remaining quote with the largest raw liquidity number.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:270-286 — why?] Why is one surviving quote sufficient to form its own median and pass with zero deviation? The implicit belief is that configuration count, rather than usable independent observations at call time, supplies redundancy.

[Inversion: _selectedV4Pool] (1) Remove active liquidity from three of four pools so one quote self-validates; (2) split four valid quotes into two price clusters so none lie within 10% of their averaged median; (3) add narrow liquidity to a manipulated quote until its raw liquidity wins selection.

[Feynman: _medianPrice] This copies the usable prices, sorts them from low to high, returns the center price for an odd count, and averages the two center prices for an even count.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:323-327 — why?] Why is the average of two distant center quotes used even if that average is not quoted by any market? The code assumes the center pair is already close enough that a real candidate will survive the later 10% test.

[Inversion: _medianPrice] (1) Supply prices `[1,1,2,2]`; (2) make one of three observations temporarily unusable so the even-count branch activates; (3) choose center values whose average is more than 10% from both values.

[Feynman: _withinV4PriceDeviation] This accepts a quote when its absolute distance from the reference is no more than 10% of the reference.

[Feynman: _setUniV4Pools] This requires a nonempty one-to-one list, rejects zero or repeated identifiers, clears the old set, and installs every supplied candidate and direction.

[Feynman: _hasUniV4Pool] This scans the candidate list and says whether a given identifier is already present.

[Feynman: _uniV3Pool] This resolves the currently configured V3 fee tier to a pool address.

[Feynman: _uniV3PoolForFee] This asks the hard-coded router for its factory and resolves the GROVE/USDC pool for one fee tier.

[Feynman: _quoteToken1ForToken0] This calculates how much second token corresponds to a chosen amount of first token at the supplied pool price while selecting a multiplication order that avoids overflow.

[Feynman: _quoteToken0ForToken1] This calculates how much first token corresponds to a chosen amount of second token at the supplied pool price while selecting a multiplication order that avoids overflow.

## Structured results

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: unaccounted-rewards-share-dilution | group_key: GroveCompounder | _harvestAndReport | unaccounted-rewards-share-dilution
path: permissionless depositor/taker -> auction holds GROVE or pays USDS to strategy -> inherited share conversion still uses `lastTotalAssets` that excludes both pending GROVE and newly arrived proceeds -> attacker deposits at the pre-reward price -> keeper report recognizes the old reward as profit -> locked-profit shares burn over time -> attacker redeems a pro-rata portion of rewards earned before their deposit
proof: The in-scope report counts only `balanceOfStake() + balanceOfAsset()` after sending GROVE to the external auction, and between reports the inherited default asset estimate remains the stale recorded value. Worse, inherited `_deposit` stakes the strategy's entire loose USDS balance but increments recorded assets only by the caller's `assets`. Let incumbents have 10,000,000 USDS/shares and let an already-kicked auction contain 1,122,909 GROVE earned during the preceding week. At dependency state sampled at Ethereum block 25,612,587 (`rewardRate=38.844495180111618467 GROVE/s`, global stake `209,216,803.145709085130056726 USDS`, usable V4 spot `$0.013065369498313038/GROVE`), that inventory is about 14,671.23 USDS. An attacker atomically settles/takes the auction at fair value and deposits 10,000,000 USDS before any strategy report; the 14,671.23 USDS paid by the auction is not in recorded assets, so the attacker receives about 10,000,000 shares instead of about 9,985,350. On the next report, total assets become 20,014,671.23 USDS and the old reward is locked as profit. Once unlocked, the attacker owns half the user shares and redeems about 10,007,335.61 USDS, in addition to retaining the fairly purchased GROVE: 7,335.61 USDS of incumbent yield is transferred to the attacker (about 6,602 USDS even after a hypothetical 10% performance fee). With 10x incumbent capital the captured fraction approaches 90.9%, or about 13,337.48 USDS. The same dilution works by front-running a direct-sale report with a deposit, and a sole new depositor can capture essentially all proceeds if old shares exit while an auction is pending.
description: Claimable GROVE, GROVE transferred to the auction, and settled-but-unreported USDS are absent from the price used to mint shares, allowing a depositor to buy into already-earned yield and dilute incumbent holders.
fix: Override live asset accounting so loose and staked USDS are reflected before every share conversion, and prevent deposits (or conservatively value/track a receivable) while claimable GROVE or an auctioned reward balance remains economically attributable to existing shares.

LEAD | contract: GroveCompounderAprOracle | function: _selectedV4Pool | bug_class: singleton-spot-oracle-manipulation | group_key: GroveCompounderAprOracle | _selectedV4Pool | singleton-spot-oracle-manipulation
code_smells: The V4 fallback requires no minimum number of usable observations, no token-balance/depth check, and no time average. A single quote becomes its own median and necessarily passes the 10% deviation filter. At Ethereum block 25,612,587 the configured V3 pool had zero active liquidity and only 71 raw USDC units, while V4 pool liquidities were `[0, 2,234,678,351,511,442, 0, 0]`; consequently the source's four-pool design collapses at runtime to the one live V4 spot. Its square-root price `693136446531199880837452956973944644` yields `$0.013065369498313038/GROVE` and about 7.65% APR. The current active-liquidity math alone implies only about 397.6 USDC of token0 movement to scale this price toward the 50% APR cap if no additional ranges are crossed (exact crossed-range and hook costs remain unverified). No in-scope value-moving consumer of the APR was present, so profitable extraction rather than quote corruption/DoS is not proven.
description: Runtime loss of three candidates silently turns the median fallback into an unprotected single-block spot oracle that can be manipulated or pushed above the APR cap to make reads revert.

LEAD | contract: GroveCompounderAprOracle | function: _medianPrice | bug_class: even-median-selection-dos | group_key: GroveCompounderAprOracle | _medianPrice | even-median-selection-dos
code_smells: For an even number of usable quotes, the reference is an arithmetic midpoint that need not be quoted by any pool. With usable prices `[1, 1, 2, 2]`, `_medianPrice` returns `1.5`; every real quote is 33.3% away, `_withinV4PriceDeviation` rejects all four, `_selectedV4Pool` returns price zero, and `_grovePrice` reverts even though all four pools are nonzero and liquid. A two-pool set `[1,2]` has the same failure. A transient liquidity loss that changes the candidate count from odd to even can therefore convert a dispersed but live market into total oracle unavailability. A concrete profit-taking downstream action was not in scope, so this remains a liveness lead.
description: Averaging the middle pair before requiring an actual quote near that average can reject every usable pool and make APR reads revert during price dispersion.

## Closed hypotheses / exclusions

- The direct Uniswap path forwards `amountOutMinimum=0`, so a configured live pool would expose reward sales to sandwiches; this was not emitted as a structured result because the shared rules explicitly exclude standard MEV tradeoffs, and the default V3 pool had zero active liquidity in the sampled state.
- Default `useAuction=true` with `auction=0` fails closed after deployment, but intended setup also keeps deposits closed until management completes configuration; no untrusted profit path was established.
- The manual arbitrary-token auction compares balances to the GROVE threshold, but exploiting a token-decimal mismatch requires keeper participation and an auction separately enabled by governance; no untrusted extraction was established.
- Signed-delta underflow/`int256.min` and a spot-price move above `MAX_EXPECTED_APR` can revert view calls, but without an in-scope state-changing consumer they do not independently prove fund loss.
