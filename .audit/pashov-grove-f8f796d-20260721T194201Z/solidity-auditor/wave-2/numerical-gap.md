# Numerical Gap Lane - Grove

No validated FINDING blocks.

Primary surfaces reviewed:
- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

## Mental tool trace

[Feynman: GroveCompounder] This contract takes USDS from depositors, puts it into the Sky staking contract, collects GROVE rewards, and either sells those rewards through an auction or through a direct USDC-to-USDS path. Its reported asset value is the USDS still in the contract plus the USDS currently staked.
[Feynman: GroveCompounder.constructor] The setup checks that staking is live and that the staking token matches the USDS asset, then gives the staking and PSM wrapper contracts spending permission and configures the default reward sale path.
[Feynman: balanceOfAsset] This answers how much loose USDS the strategy currently holds.
[Feynman: balanceOfStake] This answers how much USDS the strategy has placed in the staking contract.
[Feynman: balanceOfRewards] This answers how many GROVE reward tokens the strategy currently holds.
[Feynman: claimableRewards] This asks the staking contract how much GROVE the strategy has earned but not yet pulled in.
[Feynman: _deployFunds] This puts the requested amount of USDS into staking with the current referral code.
[Feynman: _freeFunds] This pulls the requested amount of staked USDS back out.
[Feynman: _harvestAndReport] This collects rewards, sells or auctions them if above the configured floor, stakes loose USDS when it is larger than the dust threshold, and reports staked plus loose USDS as total assets.
[Feynman: _emergencyWithdraw] This pulls out the smaller of the requested amount and the amount actually staked.
[Feynman: availableDepositLimit] This closes deposits while staking is paused and otherwise delegates the normal deposit limit decision.
[Feynman: _min] This returns the smaller of two numbers.
[Feynman: claimRewards] This lets management pull earned GROVE into the strategy without running a full report.
[Feynman: _claimRewards] This asks staking to send earned GROVE to the strategy.
[Feynman: kickAuction] This lets keepers move either GROVE rewards or another non-asset token into the configured auction when the balance is above the reward sale floor.
[Feynman: _kickAuction] This refuses to auction USDS, sends the selected token to the auction, and starts that auction.
[Feynman: setMinAmountToSell] This lets management change the GROVE sale floor.
[Feynman: setUniV3Fees] This lets management change the UniV3 fee tier used for the GROVE to USDC sale path.
[Feynman: setAuction] This lets management choose an auction whose receiver is this strategy and whose wanted token is USDS.
[Feynman: setUseAuction] This lets management choose the auction path or the direct swap path.
[Feynman: setReferral] This lets management change the referral code used for future staking deposits.

[Feynman: GroveCompounderAprOracle] This contract estimates the strategy's APR by reading global staking rewards, pricing one GROVE in USDS terms, adjusting the staking supply by a requested debt change, and dividing yearly reward value by adjusted staked assets.
[Feynman: _onlyManagement] This rejects callers that are not the configured manager.
[Feynman: GroveCompounderAprOracle.constructor] This sets the deployer as manager and loads four default UniV4 GROVE/USDC pools as fallback price sources.
[Feynman: aprAfterDebtChange] This reads staking supply and reward speed, returns zero after rewards end, gets a GROVE price, applies the requested supply increase or decrease, and returns the yearly reward value per unit of staked USDS subject to an upper APR cap.
[Feynman: setManagement] This transfers oracle configuration rights to a nonzero address.
[Feynman: setUniV3Fee] This stores a new UniV3 fee tier only if a GROVE/USDC pool exists for it.
[Feynman: setUniV4Pool] This replaces all fallback pools with one specified fallback pool.
[Feynman: setUniV4Pools] This replaces all fallback pools with a supplied list.
[Feynman: addUniV4Pool] This appends a new fallback pool if it is nonzero and not already configured.
[Feynman: removeUniV4Pool] This removes one fallback pool while keeping at least one fallback pool configured.
[Feynman: uniV3Pool] This returns the GROVE/USDC UniV3 pool for the stored fee tier.
[Feynman: uniV4PoolCount] This returns how many fallback UniV4 pools are configured.
[Feynman: uniV4Pool] This returns one configured fallback pool and whether GROVE is the first token in that pool.
[Feynman: groveUsdcV4PoolId] This returns the first configured fallback pool id.
[Feynman: v4GroveIsToken0] This returns the token order flag for the first configured fallback pool.
[Feynman: bestUniV4Pool] This returns the currently selected fallback pool and its liquidity.
[Feynman: selectedUniV4Pool] This returns the currently selected fallback pool, liquidity, and computed price.
[Feynman: _grovePrice] This tries to price one GROVE through UniV3 first; if that cannot produce a nonzero amount, it asks the UniV4 fallback selector for a price.
[Feynman: _v3PoolHasUsableLiquidity] This considers the UniV3 pool usable when it exists, reports at least the configured in-range liquidity, and holds at least the configured USDC balance.
[Feynman: _v4GrovePrice] This converts a UniV4 square-root price into the USDS-scaled value of one GROVE depending on token order.
[Feynman: _selectedV4Pool] This gathers usable fallback pool quotes, computes their median price, and selects the most liquid quote within 10% of that median.
[Feynman: _medianPrice] This copies prices, sorts them, and returns the middle price or the average of the two middle prices.
[Feynman: _withinV4PriceDeviation] This checks whether a price is no more than 10% away from a reference price.
[Feynman: _setUniV4Pools] This validates and stores a replacement fallback pool list.
[Feynman: _hasUniV4Pool] This checks whether a pool id is already configured.
[Feynman: _uniV3Pool] This returns the UniV3 pool for the currently configured fee.
[Feynman: _uniV3PoolForFee] This asks the UniV3 factory for the GROVE/USDC pool at a supplied fee.
[Feynman: _quoteToken1ForToken0] This returns how much token1 corresponds to a base amount of token0 at the supplied square-root price.
[Feynman: _quoteToken0ForToken1] This returns how much token0 corresponds to a base amount of token1 at the supplied square-root price.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:228 - why?] Why is any nonzero 6-decimal USDC output enough to make the oracle skip all fallback pricing, rather than treating boundary-sized quotes as unusable?
[Socratic: src/periphery/GroveCompounderAprOracle.sol:268 - why?] Why does the V4 fallback require only liquidity units, while the V3 path also checks a concrete USDC balance?
[Socratic: src/periphery/GroveCompounderAprOracle.sol:294 - why?] Why is deviation from the median meaningful when the median can be computed from a single surviving quote?
[Socratic: src/periphery/GroveCompounderAprOracle.sol:122 - why?] Why is the negative debt change subtracted before the code checks whether adjusted assets are zero or outside the sane oracle range?
[Socratic: src/GroveCompounder.sol:169 - why?] Why is a balance of an arbitrary token compared against the reward token's sale floor?

[Inversion: _grovePrice] Try to make UniV3 return exactly 1 USDC wei so `output > 0` wins; try to make UniV3 pass the liquidity/balance gate while V4 has a better quote; try to keep the quoted APR below the high-APR cap by pushing price downward instead of upward.
[Inversion: _selectedV4Pool] Try to leave only one fallback quote alive; try to make three configured pools fail the liquidity or slot0 reads; try to make the one surviving quote define its own median.
[Inversion: aprAfterDebtChange] Try `_delta = -assets - 1`; try a boundary-small positive price; try adjusted assets of exactly zero.
[Inversion: _harvestAndReport] Try rewards exactly equal to the sale floor; try loose USDS exactly equal to `DUST`; try a nonzero PSM fee in the direct swap branch.
[Inversion: kickAuction] Try a 6-decimal non-reward token under the 18-decimal GROVE threshold; try the asset token; try a configured zero auction.

## LEADs

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: micro-quote-preempts-fallback | group_key: GroveCompounderAprOracle | _grovePrice | micro-quote-preempts-fallback
seam: boundary x precision x invariant
path: caller -> `aprAfterDebtChange` -> `_grovePrice` -> UniV3 simulation returns a boundary-small nonzero USDC amount -> `_grovePrice` returns that amount scaled to 18 decimals -> `aprAfterDebtChange` computes a near-zero positive APR without consulting V4 fallback pools
code_smells: `amountIn` is fixed at `1e18` GROVE, the UniV3 output is denominated in 6-decimal USDC, and `src/periphery/GroveCompounderAprOracle.sol:228` accepts any `output > 0` as a valid price by returning `output * 1e12`; the V3 usability gate at `src/periphery/GroveCompounderAprOracle.sol:243-244` checks pool liquidity and raw USDC balance, but it does not lower-bound the quote itself or cross-check it against the V4 fallback path.
proof: With `output = 1`, line 228 returns `1 * 1e12 = 1_000_000_000_000`, i.e. `0.000001e18` USDS per GROVE. Line 131 then computes APR with this price, and line 132 only rejects APRs above `5e17`; underpriced quotes remain accepted. Compared with the mocked V4 source example price `26_362_000_000_000_000` in `src/test/Oracle.t.sol:193`, this boundary quote is only `0.00379338896897049%` of that price, so a 10% APR would be reported as roughly `0.0003793338896897%` if the same reward and asset values were used.
description: A one-wei USDC quote sits just above the zero boundary, survives the precision scaling, and prevents fallback pricing, so the APR oracle can report a drastically suppressed positive APR instead of rejecting or using the V4 median.
unverified: I did not prove that the live default UniV3 pool can be pushed to `output = 1` while still satisfying the liquidity and balance checks; this remains a plausible manipulation trail rather than a validated exploit.
fix: Treat V3 quotes below an absolute minimum price as unusable and/or compare V3 against the V4 median before allowing it to preempt fallback pricing.

LEAD | contract: GroveCompounderAprOracle | function: _selectedV4Pool | bug_class: singleton-median-price-validation | group_key: GroveCompounderAprOracle | _selectedV4Pool | singleton-median-price-validation
seam: boundary x invariant
path: caller -> `aprAfterDebtChange` -> `_grovePrice` falls through to `_selectedV4Pool` -> only one configured V4 pool survives liquidity and slot0 filtering -> that sole quote becomes the median -> deviation is zero -> the quote is selected as valid
code_smells: `_selectedV4Pool` silently skips unusable pools at `src/periphery/GroveCompounderAprOracle.sol:267-285`, returns only when `quoteCount == 0` at line 288, and applies median deviation filtering even when `quoteCount == 1` at lines 290-304. With one survivor, `_withinV4PriceDeviation` at lines 333-335 compares the quote to itself.
proof: For a single surviving quote with `price = 2e18` and `liquidity = 1e12`, line 290 computes `medianPrice = 2e18`; line 334 computes `deviation = 0`; line 335 allows it because `0 <= 2e17`; lines 296-304 select and return it. The same self-reference would also accept `price = 1e12`, and line 132 only caps high APR, not low APR.
description: The median/deviation invariant collapses at the one-quote boundary, allowing a single V4 pool to validate its own price whenever the other configured pools fail or fall below the liquidity floor.
unverified: I did not prove that current default pool states or a feasible attacker action can force exactly one manipulated survivor; this is a source-backed oracle robustness lead.
fix: Require at least two or three valid independent V4 quotes before applying median deviation logic, or add absolute lower/upper sanity bounds and balance/depth checks for singleton fallback operation.

## Rejected / Notes

- `src/GroveCompounder.sol:97` and `src/GroveCompounder.sol:107` use `>` rather than `>=` for the reward sale floor. At exactly `minAmountToSell`, rewards stay in the strategy for a later report; this is a pure boundary choice and I did not find a combined numerical invariant break.
- `src/GroveCompounder.sol:113` stakes only when loose USDS is greater than `DUST`. Exactly `1e18` USDS can remain idle, but line 117 still includes idle USDS in total assets, so I did not find user value loss.
- `src/GroveCompounder.sol:169` compares non-reward token balances against `minAmountToSell[REWARDS_TOKEN]`. This is a real decimals-mismatch smell for arbitrary stray tokens, but the primary reward path uses the 18-decimal GROVE token itself and I did not find a concrete exploit beyond possible recovery friction for non-reward tokens.
- `src/periphery/GroveCompounderAprOracle.sol:122` can revert with arithmetic underflow for `_delta < -assets` before reaching the explicit zero-assets check at line 128. This is a malformed view-query edge and I did not identify a state-changing or externally forced protocol impact.
