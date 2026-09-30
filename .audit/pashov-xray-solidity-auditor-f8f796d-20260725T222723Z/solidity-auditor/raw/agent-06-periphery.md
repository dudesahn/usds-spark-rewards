# Agent 06 — Periphery raw output

[Feynman: GroveCompounder] This strategy accepts USDS, places it in the Sky staking program, collects GROVE rewards, turns those rewards back into USDS through either an auction or Uniswap plus the PSM, and counts staked plus idle USDS as the users' assets.

[Feynman: GroveCompounder.constructor] Deployment fixes the external staking and PSM endpoints, confirms that both use the same USDS asset, grants them spending permission, and chooses USDC and the 1% GROVE/USDC market for direct sales. It starts in auction mode even though no auction has yet been supplied.

[Socratic: GroveCompounder.sol:22 — why?] Why start with auction sales selected before an auction exists? The deployment process assumes management will finish configuration before enough rewards accrue to trigger a sale.

[Feynman: GroveCompounder.balanceOfAsset] It reports how much unstaked USDS the strategy currently holds.

[Feynman: GroveCompounder.balanceOfStake] It reports how much USDS the external staking program credits to the strategy.

[Feynman: GroveCompounder.balanceOfRewards] It reports how much GROVE the strategy currently holds.

[Feynman: GroveCompounder.claimableRewards] It asks the staking program how much GROVE is waiting to be claimed for the strategy.

[Feynman: GroveCompounder._deployFunds] It sends a specified amount of idle USDS into the staking program and attaches the current referral code.

[Feynman: GroveCompounder._freeFunds] It asks the staking program to return a specified amount of USDS.

[Feynman: GroveCompounder._harvestAndReport] It claims GROVE, sells an above-threshold balance through the selected route, stakes idle USDS when operations are live, and reports the sum of staked and idle USDS. The fuzzy point is that its two sale routes trust very different external facts: the direct route trusts a zero PSM fee and an unrestricted market sale, while the auction route trusts a previously checked auction address.

[Inversion: GroveCompounder._harvestAndReport] (1) Put the GROVE balance exactly at the threshold so neither route sells it. (2) Sandwich the direct sale because its minimum output is zero. (3) Let the selected auction address remain unset so the first above-threshold harvest fails. These are operational/standard-tradeoff cases rather than standalone findings here.

[Feynman: GroveCompounder._emergencyWithdraw] It limits the requested emergency release to what is actually staked and then withdraws that amount.

[Inversion: GroveCompounder._emergencyWithdraw] (1) Request more than the staked balance. (2) Request zero. (3) Invoke it while the staking dependency is paused or withdrawal-disabled. The local cap handles the first two; dependency behavior controls the third.

[Feynman: GroveCompounder.availableDepositLimit] It closes new deposits whenever the staking program says it is paused; otherwise it uses the inherited deposit policy.

[Inversion: GroveCompounder.availableDepositLimit] (1) Pause staking immediately after this check. (2) Make the staking call itself fail. (3) Return false here but reject the later stake. These require behavior from the fixed external dependency, and the eventual stake fails closed.

[Feynman: GroveCompounder._min] It returns the smaller of two numbers.

[Feynman: GroveCompounder.claimRewards] It lets management pull accrued GROVE from the staking program into the strategy.

[Feynman: GroveCompounder._claimRewards] It asks the staking program to transfer all earned GROVE to the strategy.

[Feynman: GroveCompounder.kickAuction] It lets a keeper choose a non-principal token, optionally claim GROVE first, and send the strategy's entire balance of the chosen token into the configured auction when the balance clears the sale threshold.

[Socratic: GroveCompounder.sol:169 — why?] Why is every keeper-chosen token compared with the GROVE threshold? The code assumes all auctioned tokens share GROVE's denomination and economic scale.

[Inversion: GroveCompounder.kickAuction] (1) Choose a six-decimal token whose economically large balance is still below `5_000e18` raw units. (2) Choose a token not enabled by the auction so the kick rolls back. (3) Choose a callback-capable token controlled by the keeper and attempt reentry during transfer. The first produces the unit-mismatch lead below; the latter two fail or lack a principal-loss path.

[Feynman: GroveCompounder._kickAuction] It refuses to sell USDS, requires a configured auction, transfers the entire chosen-token balance there, and asks the auction to begin selling that token.

[Inversion: GroveCompounder._kickAuction] (1) Supply the strategy asset as the token. (2) leave the auction address empty. (3) Mutate the auction receiver after configuration. The first two guards fail closed; the third is an external-governance trust assumption rather than a new theft ability because auction governance can already sweep auction inventory.

[Feynman: GroveCompounder.setMinAmountToSell] It lets management replace the minimum GROVE balance that triggers a sale.

[Feynman: GroveCompounder.setUniV3Fees] It lets management replace the market-fee identifier used for the GROVE-to-USDC direct sale.

[Feynman: GroveCompounder.setAuction] It lets management choose an auction whose advertised payment recipient is this strategy and whose payment token is USDS, or clear it only after leaving auction mode.

[Inversion: GroveCompounder.setAuction] (1) Configure an auction and later change its receiver. (2) Configure an auction that has not enabled GROVE. (3) Configure a contract that reports the expected receiver and payment token but behaves differently when kicked. These are dependency/governance trust assumptions; the fixed first-party checks are only snapshots.

[Feynman: GroveCompounder.setUseAuction] It lets management switch sale routes, but it will not enter auction mode without a nonzero auction address.

[Inversion: GroveCompounder.setUseAuction] (1) Use the declaration-time `true` value before any setter call. (2) point `auction` at a contract that later changes. (3) switch to direct sales while the configured market fee identifies no useful pool. These fail closed or require trusted-management action.

[Feynman: GroveCompounder.setReferral] It lets management replace the referral number attached to future stakes.

[Feynman: BaseSwapper._setMinAmountToSell] The inherited helper stores a minimum raw balance separately for each token.

[Feynman: UniswapV3Swapper._setUniFees] The inherited helper records the same market-fee identifier for both directions of a token pair.

[Feynman: UniswapV3Swapper._swapFrom] The inherited helper spends an above-threshold input balance through one Uniswap V3 market when either token is USDC, or through a two-market route otherwise, and accepts no less than the caller's stated output floor.

[Feynman: Auction.kick] The auction's public entry asks its internal auction starter to make the token balance available for sale.

[Feynman: Auction._kick] The auction confirms the token is enabled and not already being sold, snapshots its full balance, and marks a new sale as started.

[Feynman: Auction.setReceiver] Auction governance can replace the address that receives buyers' USDS whenever no sale is active.

[Feynman: Auction._take] A buyer receives some auctioned token, optional callback work runs, and then the buyer pays USDS directly to the auction's current receiver.

[Feynman: UniswapV3SwapSimulator] This helper estimates a Uniswap V3 trade by replaying the pool's current market state without transferring tokens.

[Feynman: UniswapV3SwapSimulator.simulateExactInputSingle] It decides trade direction from token ordering, finds the factory's pool, asks the replay engine how a stated input would move that pool, and returns the simulated output-side decrease. The fuzzy point is that an unrestricted unsigned input is silently reinterpreted as a signed quantity before the replay engine decides whether it is an input or output request.

[Socratic: UniswapV3SwapSimulator.sol:38 — why?] Why is `params.amountIn` reinterpreted as a signed number without a range check? The helper assumes every caller supplies at most `int256.max`, although its public shape accepts the full unsigned range.

[Inversion: UniswapV3SwapSimulator.simulateExactInputSingle] (1) Supply `amountIn = 2^255` so it becomes a negative exact-output request. (2) Supply a router whose factory returns no pool. (3) point at a pool with enough initialized crossings to exhaust the caller's gas. The first is the library lead below; the oracle's fixed `1e18` input excludes it from the current protocol path.

[Feynman: UniswapV3SwapSimulator.getPool] It asks the router for its factory and asks that factory for the market matching the two tokens and fee.

[Inversion: UniswapV3SwapSimulator.getPool] (1) Return the zero address. (2) return a contract with pool-shaped answers but inconsistent token ordering. (3) make the factory call fail. The production oracle uses the canonical fixed router, so these generic-router cases are not protocol findings.

[Feynman: Simulate] This library mirrors Uniswap V3's price walk so a caller can estimate a trade from stored pool state without executing it.

[Feynman: Simulate.simulateSwap] It starts from the pool's current price, current active capital, fee, and tick spacing; repeatedly advances toward the next initialized price boundary while consuming the requested amount; adjusts active capital when a position boundary is crossed; and returns the two token changes.

[Inversion: Simulate.simulateSwap] (1) Start with zero active capital and force a long empty-range walk. (2) use the most negative signed amount. (3) cross a maliciously dense set of initialized ticks. The canonical oracle catches V3 simulation failure and falls back, while the fixed one-token input avoids signed extremes.

[Feynman: Simulate.nextInitializedTickWithinOneWord] It inspects one 256-position bitmap word in the requested direction and returns either the nearest marked price boundary or the edge of that word.

[Inversion: Simulate.nextInitializedTickWithinOneWord] (1) begin at a negative, non-aligned tick. (2) begin at bit zero or bit 255. (3) scan an empty word at the global tick boundary. Comparison with the pinned Uniswap V3 implementation showed the same rounding, masks, and boundary formulas.

[Feynman: Simulate.tickBitmapPosition] It maps a compressed price-boundary number to the storage word and bit that represent it.

[Feynman: GroveCompounderAprOracle] This oracle estimates the annual GROVE reward value per staked USDS. It prefers a one-GROVE quote from a V3 pool and otherwise derives spot prices from configured V4 pools, then divides annual reward value by the hypothetical post-change staking supply.

[Feynman: GroveCompounderAprOracle._onlyManagement] It rejects configuration calls from anyone other than the current oracle manager.

[Feynman: GroveCompounderAprOracle.constructor] It gives the deployer configuration authority and seeds four fixed V4 market identifiers with GROVE recorded as token one.

[Feynman: GroveCompounderAprOracle.aprAfterDebtChange] It reads the global amount of staked USDS and current GROVE emission speed, returns zero after the reward period, changes the denominator by the proposed debt movement, obtains a GROVE price, and returns annual reward value divided by adjusted staked USDS, rejecting results above 50%.

[Socratic: GroveCompounderAprOracle.sol:119 — why?] Why is a negative change subtracted without first proving it is no larger than global staked assets? The code assumes all consumers model only achievable withdrawals.

[Inversion: GroveCompounderAprOracle.aprAfterDebtChange] (1) pass `delta = -(assets + 1)` to force subtraction failure. (2) manipulate the GROVE price to a false value that still yields 49.99% and passes the cap. (3) raise the price enough that numerator multiplication fails before the cap. The second is protocol-reachable through the market-source weakness below; the first is retained only as a consumer-bound lead.

[Feynman: GroveCompounderAprOracle.setManagement] It lets the current manager hand configuration authority to a nonzero successor immediately.

[Feynman: GroveCompounderAprOracle.setUniV3Fee] It lets management choose a fee tier only if the fixed Uniswap factory currently maps that tier to a GROVE/USDC pool.

[Inversion: GroveCompounderAprOracle.setUniV3Fee] (1) choose an existing but inactive pool. (2) choose a pool whose last stored price is stale. (3) later remove all liquidity from a once-valid pool. The nonzero-address check establishes existence, not price freshness or durable usability.

[Feynman: GroveCompounderAprOracle.setUniV4Pool] It replaces all V4 candidates with one nonzero market identifier and a caller-supplied statement about which side is GROVE.

[Feynman: GroveCompounderAprOracle.setUniV4Pools] It replaces all V4 candidates with the paired identifier and orientation lists after shared validation.

[Feynman: GroveCompounderAprOracle.addUniV4Pool] It appends one nonzero, not-already-listed V4 identifier and its claimed orientation.

[Feynman: GroveCompounderAprOracle.removeUniV4Pool] It removes one selected V4 candidate by replacing it with the last candidate, while refusing to remove the final entry.

[Feynman: GroveCompounderAprOracle.uniV3Pool] It returns the factory market for the currently configured V3 fee.

[Feynman: GroveCompounderAprOracle.uniV4PoolCount] It returns how many V4 candidates are configured.

[Feynman: GroveCompounderAprOracle.uniV4Pool] It returns one configured V4 identifier and its claimed GROVE side.

[Feynman: GroveCompounderAprOracle.groveUsdcV4PoolId] It returns the first configured V4 identifier for compatibility with older consumers.

[Feynman: GroveCompounderAprOracle.v4GroveIsToken0] It returns the first configured V4 candidate's orientation for compatibility with older consumers.

[Feynman: GroveCompounderAprOracle.bestUniV4Pool] It returns the identifier, orientation, and active capital of the internally selected V4 candidate.

[Feynman: GroveCompounderAprOracle.selectedUniV4Pool] It exposes the internally selected V4 candidate together with the spot price computed from it.

[Feynman: GroveCompounderAprOracle._grovePrice] It first accepts a simulated one-GROVE output from V3 whenever two instantaneous balance tests pass; only if that route is absent, fails, or returns zero does it use the selected V4 spot price. The fuzzy point is that no observation age or comparison between these branches exists.

[Socratic: GroveCompounderAprOracle.sol:212 — why?] Why does any V3 pool that passes two instantaneous capital checks outrank all V4 observations? The code assumes current capital proves that V3's stored price is fresh and representative.

[Inversion: GroveCompounderAprOracle._grovePrice] (1) Temporarily add active V3 capital around a stale stored price. (2) place recoverable USDC in an inactive V3 position so the raw-balance threshold passes. (3) after the false V3 quote is consumed, remove both positions in the same transaction. This exact current-state path proves the finding below.

[Feynman: GroveCompounderAprOracle._v3PoolHasUsableLiquidity] It calls the factory-selected pool usable when its instantaneous active capital is at least `1e12` and its raw USDC token balance is at least 1,000 USDC.

[Socratic: GroveCompounderAprOracle.sol:243 — why?] Why do active capital and a raw token balance prove price quality? An inactive position can supply the balance, a tiny active position can independently satisfy the capital check, and neither changes or refreshes the stored price.

[Inversion: GroveCompounderAprOracle._v3PoolHasUsableLiquidity] (1) Mint an all-USDC position outside the current range to raise only `balanceOf(pool)`. (2) Mint a broad in-range position with exactly `1e12` active capital. (3) use the pool's old `slot0` without executing a price-changing swap. All three are permissionless and reversible.

[Feynman: GroveCompounderAprOracle._v4GrovePrice] It turns the V4 square-root price into the raw USDC received for one GROVE and scales six-decimal USDC into the oracle's 18-decimal convention, using the configured token orientation.

[Feynman: GroveCompounderAprOracle._selectedV4Pool] It gathers every configured V4 candidate whose current active capital and price are nonzero, computes the median of those spot prices, and returns the candidate with the most active capital among prices within 10% of that median.

[Socratic: GroveCompounderAprOracle.sol:284 — why?] Why is one surviving quote allowed to be its own median and deviation reference? The code assumes the configured list implies multiple live observations, but it never requires a live-source quorum.

[Inversion: GroveCompounderAprOracle._selectedV4Pool] (1) Let three of four configured markets have zero active capital, as at block 25,612,581. (2) move the only surviving market's spot price and make it its own median. (3) add narrow active capital to the manipulated market so it wins the liquidity tie-break. This is a second reachable branch of the same spot-oracle finding.

[Feynman: GroveCompounderAprOracle._medianPrice] It copies live candidate prices, orders them from low to high, and returns the middle price or the overflow-safe average of the two middle prices.

[Inversion: GroveCompounderAprOracle._medianPrice] (1) provide one quote. (2) provide two attacker-correlated quotes. (3) provide many quotes to make ordering expensive. The arithmetic is sound, but one quote provides no manipulation resistance and list length is management-controlled.

[Feynman: GroveCompounderAprOracle._withinV4PriceDeviation] It accepts a candidate whose absolute difference from the chosen reference is at most 10% of that reference.

[Inversion: GroveCompounderAprOracle._withinV4PriceDeviation] (1) make the manipulated quote the reference itself. (2) keep a selected quote exactly 10% away. (3) move two middle quotes together so their median moves with them. The comparison works mathematically but cannot establish independence.

[Feynman: GroveCompounderAprOracle._setUniV4Pools] It requires matching nonempty lists, rejects empty and repeated identifiers, and stores every identifier with its caller-supplied orientation.

[Inversion: GroveCompounderAprOracle._setUniV4Pools] (1) provide a real pool with the wrong orientation. (2) provide a pool for unrelated currencies. (3) provide a very long unique list. All require trusted-management configuration and are therefore not reported as attacker findings.

[Feynman: GroveCompounderAprOracle._hasUniV4Pool] It scans the configured candidates and says whether an identifier is already present.

[Feynman: GroveCompounderAprOracle._uniV3Pool] It resolves the fixed token pair through the currently selected V3 fee.

[Feynman: GroveCompounderAprOracle._uniV3PoolForFee] It asks the canonical router's canonical factory for the GROVE/USDC pool at a specified fee.

[Feynman: GroveCompounderAprOracle._quoteToken1ForToken0] It squares the encoded price safely and computes token-one units received for a stated token-zero amount, selecting a scale that avoids intermediate overflow.

[Inversion: GroveCompounderAprOracle._quoteToken1ForToken0] (1) use a price just below the branch boundary. (2) use a price just above it. (3) use the protocol's maximum valid price. The two branches preserve scaling, and valid Uniswap prices stay within the final multiplication range.

[Feynman: GroveCompounderAprOracle._quoteToken0ForToken1] It inverts the squared encoded price to compute token-zero units received for a stated token-one amount, again selecting a scale that avoids intermediate overflow.

[Inversion: GroveCompounderAprOracle._quoteToken0ForToken1] (1) supply zero. (2) use the minimum valid Uniswap price. (3) cross the branch boundary. The caller skips zero and valid Uniswap price bounds keep the denominator and products safe.

[Feynman: AprOracle.getStrategyApr] The downstream Yearn helper looks up the custom oracle registered for a strategy and directly returns this contract's debt-adjusted APR when one is configured.

[Inversion: AprOracle.getStrategyApr] (1) consume the quote in the same transaction as temporary liquidity. (2) use it to rank strategies for an allocation decision. (3) query with a negative debt change near the strategy's full debt. The first two establish that a false return is externally consumable; concrete allocation policy remains downstream-specific.

FINDING | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: manipulable-spot-oracle | group_key: GroveCompounderAprOracle | _grovePrice | manipulable-spot-oracle
path: permissionless liquidity provider → temporarily satisfies `_v3PoolHasUsableLiquidity()` around the V3 pool's stale `slot0` → `_grovePrice()` returns V3 immediately and skips all V4 candidates → `aprAfterDebtChange()` returns attacker-selected/stale APR → downstream `AprOracle.getStrategyApr()` consumers rank or allocate to the strategy using false yield → attacker removes the temporary positions
proof: At Ethereum block 25,612,581, the configured V3 pool `0x5D23797587B2c17414384384098291c0B1Fe1362` has `liquidity() = 0`, only 71 raw USDC, but retains `sqrtPriceX96 = 444097037295074674201962457733874940` and tick 310799, which encode 0.031827 USDC/GROVE; the only live default V4 candidate instead encodes 0.013065 USDC/GROVE, and the live staking values make the honest oracle result `76,497,799,217,654,500` (7.6498%). The attacker can mint an inactive all-USDC V3 position over ticks `[310800, 887200]` containing 1,000 USDC, then an active `[310600, 887200]` position with liquidity exactly `1e12` (about 0.178403 USDC plus 0.055765 GROVE). Both threshold checks now pass without changing `slot0`; when the simulated input crosses tick 310800, the first position becomes active and supplies about `5.6053e15` additional liquidity. Replaying the hard-coded 1 GROVE input at the pool's 1% fee returns 31,508 raw USDC, so the oracle prices GROVE at `31,508e12` and returns `184,484,703,999,223,726` (18.4485%), still below the 50% cap. Both positions can be burned and collected after the same-transaction consumer call because the oracle itself performs no trade. Independently, at that block the four V4 liquidities are `[0, 2,234,678,351,511,442, 0, 0]`, so fallback also has only one spot source and its median/deviation test becomes tautological.
description: Instantaneous, independently satisfiable V3 liquidity and token-balance checks can reactivate a stale pool that unconditionally outranks V4, allowing temporary recoverable liquidity to more than double the reported APR without moving the market price.
fix: Price GROVE from a manipulation-resistant TWAP or external oracle, require observation freshness and meaningful time-weighted liquidity, and never prefer V3 unless its price agrees with an independent live-source quorum such as the V4 aggregate.

LEAD | contract: UniswapV3SwapSimulator | function: simulateExactInputSingle | bug_class: unchecked-uint-to-int-cast | group_key: UniswapV3SwapSimulator | simulateExactInputSingle | unchecked-uint-to-int-cast
code_smells: `params.amountIn` accepts every `uint256` but is passed as `int256(params.amountIn)`; for `amountIn = 2^255` it becomes `type(int256).min`, so `Simulate.simulateSwap` treats a function advertised as exact-input as an exact-output request. The in-scope oracle always supplies `1e18`, so no current protocol caller reaches the bad range.
description: The generic quote helper silently changes trade semantics for inputs above `int256.max`; a concrete in-scope caller or integration accepting such amounts remains unverified.

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: cross-token-threshold-unit-mismatch | group_key: GroveCompounder | kickAuction | cross-token-threshold-unit-mismatch
code_smells: The keeper can supply any non-asset `_token`, but `rewardsBalance` is always compared with `minAmountToSell[REWARDS_TOKEN]` (default `5_000e18`) rather than a threshold denominated in `_token`; an economically large six-decimal balance can therefore remain below an 18-decimal GROVE threshold. Management can temporarily change the GROVE threshold, so permanent loss is not established.
description: Arbitrary auction tokens are gated using GROVE raw units, which can strand or mistime non-GROVE balances; a material naturally accruing non-GROVE balance and unrecoverable impact remain unverified.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: unbounded-negative-delta | group_key: GroveCompounderAprOracle | aprAfterDebtChange | unbounded-negative-delta
code_smells: For `_delta < 0`, `assets - uint256(-_delta)` has no explicit bound and `-_delta` itself fails for `type(int256).min`; with current `assets = 209,216,803,145,709,085,130,056,726`, `_delta = -(assets + 1)` deterministically fails instead of returning a bounded result. Normal Yearn weighted-debt calculations appear to keep withdrawals within current debt, so an attacker-controlled state-changing consumer path is not established.
description: Out-of-domain negative debt scenarios make the oracle revert and may deny downstream simulations, but no protocol-reachable oversized delta was proven.

Raw lane result: 1 FINDING, 3 LEADs.
