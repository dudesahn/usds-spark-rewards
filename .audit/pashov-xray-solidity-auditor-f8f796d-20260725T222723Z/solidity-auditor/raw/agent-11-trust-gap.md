# Agent 11 — Trust-Gap Raw Output

## Mandatory mental-tool stream

[Feynman: GroveCompounder] This strategy takes depositors' USDS, places it in the Sky staking program, collects GROVE rewards, turns those rewards back into USDS, and counts only staked and loose USDS as depositor value.

[Feynman: GroveCompounder.constructor] Deployment confirms that the fixed staking program accepts the same USDS produced by the fixed PSM wrapper, gives those two programs standing permission to move the relevant coins, and starts with auction sales selected even though no auction has yet been supplied.

[Socratic: src/GroveCompounder.sol:22 — why?] Why is auction mode selected before an auction exists? The implicit belief is that management will finish venue setup before rewards exceed the sale threshold and before any report must succeed.

[Inversion: GroveCompounder.constructor] (1) Accrue more than 5,000 GROVE before management sets an auction, then make a keeper report; (2) pause the fixed staking program immediately after deployment and test whether exits still work; (3) let a permitted external spender change behavior after receiving its unlimited allowance.

[Feynman: GroveCompounder.balanceOfAsset] This reports how much loose USDS is presently sitting at the strategy address.

[Feynman: GroveCompounder.balanceOfStake] This reports how much USDS the external staking program says belongs to the strategy.

[Feynman: GroveCompounder.balanceOfRewards] This reports how much already-claimed GROVE is sitting at the strategy.

[Feynman: GroveCompounder.claimableRewards] This asks the staking program how much GROVE the strategy has earned but not yet collected.

[Feynman: GroveCompounder._deployFunds] This hands a stated amount of loose USDS to the staking program and attaches the current referral code.

[Inversion: GroveCompounder._deployFunds] (1) Deposit while the staking program changes from unpaused to paused; (2) make the staking program accept less USDS than requested; (3) change the referral code immediately before a large deposit and ask who receives any referral economics.

[Feynman: GroveCompounder._freeFunds] This asks the staking program to return a stated amount of the strategy's USDS.

[Feynman: GroveCompounder._harvestAndReport] This collects GROVE, either starts an auction or immediately sells it through Uniswap and the PSM, stakes any loose USDS above one token, and tells share accounting that depositor value equals staked plus loose USDS.

[Socratic: src/GroveCompounder.sol:100 — why?] Why may the direct GROVE sale accept zero USDC? The implicit belief is that the authorized keeper's timing and the live Uniswap price are trustworthy enough that no enforceable sale floor is needed.

[Socratic: src/GroveCompounder.sol:103 — why?] Why does the PSM conversion consume the entire loose USDC balance rather than only this sale's output? The implicit belief is that every USDC already at the strategy should be treated as depositor yield and can safely be swept into USDS.

[Inversion: GroveCompounder._harvestAndReport] (1) A keeper sells GROVE immediately before the report and buys it back immediately after; (2) settle an auction into loose USDS and deposit before the next report; (3) leave an auction active, accrue another threshold-sized GROVE balance, and force every new report attempt to hit the auction's active-sale rejection.

[Feynman: GroveCompounder._emergencyWithdraw] This returns no more USDS than the staking program currently credits to the strategy, even when the requested emergency amount is larger.

[Feynman: GroveCompounder.availableDepositLimit] This rejects new deposits while the staking program reports itself paused, then applies the inherited open-or-allowlisted depositor rule.

[Socratic: src/GroveCompounder.sol:125 — why?] Why does the deposit check look only at staking pause state and not at unreported loose USDS or an unsettled auction? The implicit belief is that a new depositor may safely receive shares while external reward value is between realization and accounting.

[Inversion: GroveCompounder.availableDepositLimit] (1) Deposit just after auction USDS reaches the strategy; (2) deposit after GROVE has accrued but before it is harvested; (3) use an allowlisted receiver while a different address funds the deposit and test which identity the inherited gate actually checks.

[Feynman: GroveCompounder._min] This returns the smaller of two numbers.

[Feynman: GroveCompounder.claimRewards] This lets management collect the strategy's earned GROVE without yet valuing it as depositor assets.

[Feynman: GroveCompounder._claimRewards] This asks the staking program to send all currently earned GROVE to the strategy.

[Feynman: GroveCompounder.kickAuction] This lets the keeper collect GROVE when appropriate, measure the full balance of any nominated non-principal coin, and send that balance into the configured auction when it exceeds the GROVE sale threshold.

[Socratic: src/GroveCompounder.sol:169 — why?] Why is every nominated coin compared with the GROVE threshold? The implicit belief is that any other auctionable coin has compatible units and should share GROVE's sale policy.

[Inversion: GroveCompounder.kickAuction] (1) Nominate USDC with six decimals against the 18-decimal GROVE threshold; (2) nominate the strategy's own share token while locked shares exist; (3) nominate an externally controlled coin whose balance query or transfer calls back into the keeper surface.

[Feynman: GroveCompounder._kickAuction] This refuses to sell USDS, sends the complete nominated coin balance to the configured auction, and asks that auction to begin selling it.

[Socratic: src/GroveCompounder.sol:175 — why?] Why is USDS the only protected token? The implicit belief is that every other balance held by the strategy is disposable reward inventory.

[Feynman: GroveCompounder.setMinAmountToSell] This lets management replace the GROVE amount that must accumulate before either sale route is used.

[Feynman: GroveCompounder.setUniV3Fees] This lets management choose the Uniswap fee-tier identifier used for GROVE-to-USDC execution without proving that the corresponding market exists or is liquid.

[Feynman: GroveCompounder.setAuction] This lets management replace the auction after checking, at that moment, that sale payments are directed to this strategy and paid in USDS.

[Socratic: src/GroveCompounder.sol:211 — why?] Why are the receiver and payment coin checked only when the address is installed? The implicit belief is that the auction's own privileged configuration will not later change the receiver.

[Inversion: GroveCompounder.setAuction] (1) Install a conforming auction and change its receiver after validation; (2) install one where GROVE was never enabled; (3) switch auctions while proceeds remain pending in the old venue.

[Feynman: GroveCompounder.setUseAuction] This lets management choose asynchronous auction sales or immediate Uniswap-plus-PSM sales, requiring an auction address before choosing auctions.

[Feynman: GroveCompounder.setReferral] This lets management replace the referral number attached to future staking deposits.

[Feynman: UniswapV3SwapSimulator] This quote helper replays a Uniswap V3 trade against live pool data without moving coins.

[Feynman: UniswapV3SwapSimulator.simulateExactInputSingle] This finds the requested fee-tier pool, works out which coin is first in that pool, simulates spending the stated input, and returns the predicted amount of the other coin.

[Inversion: UniswapV3SwapSimulator.simulateExactInputSingle] (1) Ask for a fee tier with no pool; (2) pass more input than fits in a positive signed number; (3) move the live pool price immediately before a consumer reads the quote.

[Feynman: UniswapV3SwapSimulator.getPool] This asks the router for its factory and asks that factory for the pool matching the two coins and fee tier.

[Feynman: Simulate] This library walks through the same price ranges a real Uniswap V3 trade would cross and totals the input, output, and charges along the way.

[Feynman: Simulate.simulateSwap] This starts from the pool's current price and active liquidity, advances range by range until the requested trade or price limit is reached, and returns the two coin changes the pool would experience.

[Socratic: src/libraries/UniswapV3SwapSimulatorCore.sol:92 — why?] Why may the remaining amount be reduced without arithmetic checks? The implicit belief is that the copied Uniswap step calculation can never consume more than the signed remainder on the exact-input path.

[Inversion: Simulate.simulateSwap] (1) Begin with zero active liquidity and many initialized ranges; (2) place the current price exactly next to the terminal boundary; (3) supply an input whose unsigned-to-signed conversion changes its sign.

[Feynman: Simulate.nextInitializedTickWithinOneWord] This scans one compact group of price ranges in the chosen direction and returns either the closest initialized boundary or the edge of that group.

[Feynman: Simulate.tickBitmapPosition] This turns a compressed price-range number into the storage group and bit that represent it.

[Feynman: GroveCompounderAprOracle] This estimator divides annual GROVE emissions, valued from Uniswap markets, by the staking program's total USDS after a hypothetical debt change and refuses to return more than 50% APR.

[Feynman: GroveCompounderAprOracle._onlyManagement] This rejects configuration calls from every address except the oracle's current manager.

[Feynman: GroveCompounderAprOracle.constructor] This makes the deployer manager and seeds four fixed Uniswap V4 market identifiers with GROVE marked as the second coin.

[Feynman: GroveCompounderAprOracle.aprAfterDebtChange] This values one year of current GROVE emissions, adjusts all staked USDS by the caller's signed hypothetical change, and returns annual reward value per adjusted USDS so long as it is at most 50%.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:110 — why?] Why is the supplied strategy address ignored? The implicit belief is that every valid consumer asks about the same staking program, reward coin, costs, and aggregate dilution.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:128 — why?] Why is an excessive positive APR rejected while an arbitrarily depressed APR is accepted? The implicit belief is that only overvaluation, not undervaluation, creates dangerous downstream decisions.

[Inversion: GroveCompounderAprOracle.aprAfterDebtChange] (1) Push the market quote down toward zero so the one-sided cap still passes; (2) request a negative debt change larger than total staked USDS; (3) pass the smallest signed number so negating it fails.

[Feynman: GroveCompounderAprOracle.setManagement] This lets the current manager immediately hand all future oracle configuration power to one nonzero address.

[Feynman: GroveCompounderAprOracle.setUniV3Fee] This lets management choose any fee tier for which the factory currently reports a GROVE-USDC pool.

[Feynman: GroveCompounderAprOracle.setUniV4Pool] This lets management discard every V4 candidate and replace them with one nonzero identifier plus a claimed GROVE direction.

[Feynman: GroveCompounderAprOracle.setUniV4Pools] This lets management replace all V4 candidates and their claimed GROVE directions as one batch.

[Feynman: GroveCompounderAprOracle.addUniV4Pool] This lets management append one nonzero, not-yet-listed V4 identifier and its claimed direction.

[Feynman: GroveCompounderAprOracle.removeUniV4Pool] This lets management delete one candidate while ensuring at least one candidate remains, filling the gap with the previous last entry.

[Feynman: GroveCompounderAprOracle.uniV3Pool] This reveals the factory pool currently selected by the configured V3 fee tier.

[Feynman: GroveCompounderAprOracle.uniV4PoolCount] This reveals how many V4 candidates management has configured.

[Feynman: GroveCompounderAprOracle.uniV4Pool] This reveals one configured V4 identifier and which side management says GROVE occupies.

[Feynman: GroveCompounderAprOracle.groveUsdcV4PoolId] This reveals the first configured V4 identifier for compatibility with callers expecting a single pool.

[Feynman: GroveCompounderAprOracle.v4GroveIsToken0] This reveals the claimed GROVE direction of the first V4 candidate.

[Feynman: GroveCompounderAprOracle.bestUniV4Pool] This reports the chosen V4 candidate and its active liquidity but omits the chosen price.

[Feynman: GroveCompounderAprOracle.selectedUniV4Pool] This reports the chosen V4 candidate, claimed direction, active liquidity, and calculated GROVE price.

[Feynman: GroveCompounderAprOracle._grovePrice] This uses a one-GROVE V3 execution quote whenever that pool passes two raw-balance gates; only if that route fails does it use the selected V4 candidate.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:212 — why?] Why does any gate-passing V3 quote outrank the multi-pool V4 median without a consistency check? The implicit belief is that the V3 gates make its instantaneous price more trustworthy than all V4 observations.

[Inversion: GroveCompounderAprOracle._grovePrice] (1) Donate USDC directly to the V3 pool to satisfy its balance gate; (2) move V3's instantaneous price while leaving four honest V4 quotes untouched; (3) make V3 simulation fail so pricing changes branches at a consumer-chosen moment.

[Feynman: GroveCompounderAprOracle._v3PoolHasUsableLiquidity] This calls V3 usable when its currently active liquidity reaches a raw threshold and at least 1,000 USDC tokens sit at the pool address.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:241 — why?] Why does a freely transferable pool balance prove sale depth? The implicit belief is that USDC sitting at the pool was supplied through economically active positions and cannot be a donation.

[Feynman: GroveCompounderAprOracle._v4GrovePrice] This converts the V4 square-root price into the USDC received for one GROVE according to management's claimed coin direction, then scales six-decimal USDC into an 18-decimal USDS-like number.

[Feynman: GroveCompounderAprOracle._selectedV4Pool] This gathers every candidate with enough active liquidity and a nonzero price, computes the median candidate price, rejects quotes over 10% from that median, and chooses the remaining quote with the most raw active liquidity.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:292 — why?] Why is raw active liquidity comparable across pools with different prices, fee tiers, and range shapes? The implicit belief is that a larger liquidity number always means a harder-to-manipulate GROVE-USDC quote.

[Inversion: GroveCompounderAprOracle._selectedV4Pool] (1) Manipulate half of an even-sized candidate set so their arithmetic-middle price moves; (2) create the largest raw liquidity number in an extremely narrow range; (3) move one cheap pool just inside 10% of the manipulated median so it becomes eligible for selection.

[Feynman: GroveCompounderAprOracle._medianPrice] This sorts the usable candidate prices and returns the middle one, or the average of the two middle prices when the count is even.

[Feynman: GroveCompounderAprOracle._withinV4PriceDeviation] This accepts a quote when its absolute difference from the reference is no more than 10% of the reference.

[Feynman: GroveCompounderAprOracle._setUniV4Pools] This empties the current V4 list and repopulates it after checking equal nonzero list lengths, nonzero identifiers, and no duplicates.

[Feynman: GroveCompounderAprOracle._hasUniV4Pool] This walks the current list and says whether a given V4 identifier is already present.

[Feynman: GroveCompounderAprOracle._uniV3Pool] This resolves the live factory pool for the presently configured V3 fee tier.

[Feynman: GroveCompounderAprOracle._uniV3PoolForFee] This asks the router's factory for the GROVE-USDC market at a stated fee tier.

[Feynman: GroveCompounderAprOracle._quoteToken1ForToken0] This calculates how much second coin corresponds to a stated amount of first coin at the supplied square-root price while changing arithmetic form to avoid oversized intermediate multiplication.

[Feynman: GroveCompounderAprOracle._quoteToken0ForToken1] This calculates how much first coin corresponds to a stated amount of second coin at the supplied square-root price while changing arithmetic form to avoid oversized intermediate multiplication.

## Findings and leads

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: stale-auction-proceeds-share-dilution | group_key: GroveCompounder | _harvestAndReport | stale-auction-proceeds-share-dilution
seam: economics×asymmetry (keeper-controlled report timing strengthens the access component)
actor: any depositor accepted by the inherited open/allowlist gate; an auction buyer can execute the settlement and deposit atomically, and a colluding keeper can choose the eventual report time
path: incumbent users earn GROVE → `_harvestAndReport` transfers GROVE to the asynchronous auction without changing recorded assets → `Auction.take` pays USDS directly to the strategy → accepted newcomer deposits against stale `lastTotalAssets` → later keeper report recognizes the old users' reward proceeds after the newcomer already owns shares → newcomer captures part of historical yield
proof: Start with 100,000 USDS staked, 100,000 incumbent shares, and 10,000 USDS worth of GROVE in the auction. The attacker calls `Auction.take`, paying 10,000 USDS to the strategy and receiving the GROVE, then in the same transaction deposits another 100,000 USDS. `GroveCompounder` does not override `_strategyTotalAssets`, so the inherited view returns the stored 100,000 rather than stake plus the newly received 10,000; the deposit therefore issues 100,000 shares at PPS 1. The inherited deposit path stakes the full 110,000 loose USDS but increments stored assets by only the attacker's 100,000, leaving recorded assets at 200,000 while real assets are 210,000. At the next report the 10,000 difference becomes profit. With the inherited default 10% performance fee and ten-day unlock, approximately 1,000 fee shares and 9,000 locked shares are created; after the 9,000 locked shares burn, 210,000 assets back 201,000 shares, so the attacker redeems 100,000 shares for about 104,477 USDS and captures about 4,477 USDS of proceeds earned before entry (5,000 USDS if the fee is zero). The direct Uniswap route has no equivalent externally visible USDS-arrival window because sale, conversion, and report accounting occur atomically.
root_cause: the auction branch realizes reward value asynchronously into the strategy, while share minting uses report-boundary accounting that ignores loose USDS until a keeper report; `availableDepositLimit` checks only pause/open/allowlist state and does not close deposits when live USDS exceeds recorded assets
description: An auction buyer can settle earned rewards and immediately mint underpriced shares before those proceeds are recorded, diluting incumbents and reclaiming part of its auction payment as historical strategy profit.
fix: Before allowing a deposit, compare live staked-plus-loose USDS with recorded assets and return a zero deposit limit until a report synchronizes any discrepancy (or otherwise make auction settlement and accounting atomic); a live-value override alone must also handle TokenizedStrategy's same-block accrual latch.

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: keeper-self-sandwich-zero-min-out | group_key: GroveCompounder | _harvestAndReport | keeper-self-sandwich-zero-min-out
seam: access×economics
actor: the configured strategy keeper when management has selected the supported direct Uniswap route (`useAuction == false`)
path: keeper obtains exclusive authority to choose the report moment → keeper pre-sells GROVE to depress the configured pool → keeper calls `report` → `_harvestAndReport` sells the strategy's entire GROVE balance with `amountOutMinimum = 0` → keeper buys back its GROVE and retains the USDC difference → shareholders receive less reward value
proof: Use a fee-free constant-product-equivalent active range holding 100,000 GROVE and 100,000 USDC, with 10,000 GROVE ready in the strategy. Without interference the strategy sale returns 100,000 - 10^10/110,000 = 9,091 USDC. A keeper first sells 50,000 GROVE and receives 33,333 USDC, leaving 150,000/66,667; its authorized report then sells the strategy's 10,000 GROVE for only 4,167 USDC because the call hardcodes a zero floor, leaving 160,000/62,500. Buying back 50,000 GROVE costs 28,409 USDC and restores the same 110,000/90,909 post-victim reserves, so the keeper retains about 4,924 USDC and shareholders lose the same amount versus the unsandwiched sale. Uniswap fees reduce but do not remove the attack for a sufficiently large victim sale. The health check does not detect this because the pre-report GROVE was never part of `lastTotalAssets`: principal plus even the impaired 4,167 USDS is still reported as a positive profit, not a loss.
root_cause: the only actor allowed to select direct-sale timing is also allowed to execute the sale with no price protection, so the authorization boundary gives that actor a deterministic victim order whose entire slippage can be internalized
description: A malicious keeper can self-sandwich the strategy's direct reward sale and extract reward value while the report still records a harmless-looking positive profit.
fix: Derive and enforce a nonzero manipulation-resistant minimum output for every direct sale (for example from a suitably delayed TWAP plus bounded slippage), and do not let the keeper supply or bypass that bound.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: v3-priority-bypasses-v4-consensus | group_key: GroveCompounderAprOracle | _grovePrice | v3-priority-bypasses-v4-consensus
seam: economics×asymmetry
actor: a permissionless Uniswap V3 trader, potentially one positioned to profit from a downstream allocator reacting to the returned APR
code_smells: A V3 pool that passes raw `liquidity` and `USDC.balanceOf(pool)` thresholds always wins, even when all configured V4 pools agree on a different price. The USDC gate can be increased by a direct token donation, the quote is an instantaneous one-GROVE execution, and `aprAfterDebtChange` rejects only excessive high APR while accepting an arbitrarily depressed one. Thus a trader can target the favored V3 branch, depress its price, and produce a low but non-reverting APR while the V4 median is never consulted.
description: The pricing branches are economically asymmetric: weakly gated V3 spot state has unconditional priority over V4 consensus, but the in-scope repository does not identify a downstream allocator or a realizable position from which the manipulator profits, so end-to-end impact remains unverified.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: quote-execution-size-mismatch | group_key: GroveCompounderAprOracle | _grovePrice | quote-execution-size-mismatch
seam: economics×asymmetry
actor: a keeper able to delay harvesting and any downstream allocator that treats the quote as realizable strategy APR
code_smells: The oracle always simulates selling exactly 1 GROVE, whereas direct harvesting sells the complete reward balance and does not start until that balance exceeds 5,000 GROVE. In a simple 10,000 GROVE/1,000 USDC constant-product-equivalent range, the one-GROVE quote is approximately 0.10 USDC/GROVE while selling 5,000 GROVE realizes only about 333.33 USDC, or 0.0667 USDC/GROVE, before fees. A keeper can enlarge this gap by delaying the report, and the strategy uses zero minimum output. The in-scope code does not expose the consumer's allocation rule, so a concrete extraction from forecast error is not established.
description: Forecasting with a one-token quote while realizing rewards in threshold-sized bulk trades can systematically overstate the sale value that backs the advertised APR.
