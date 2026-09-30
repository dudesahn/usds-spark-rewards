# Periphery lane output

No validated FINDINGs.

Reviewed primary surfaces: `GroveCompounder` staking deposit/withdraw hooks, reward claiming, UniV3/PSM sale path, auction kick path, permissioned setters, and `GroveCompounderAprOracle` management, V3/V4 pricing, V4 pool selection, median/deviation filtering, and APR debt-delta math.

## Mental tool markers

[Feynman: GroveCompounder] This strategy takes USDS from depositors, puts most of it into the Grove staking program, collects GROVE rewards, and either sells those rewards through an auction or through Uniswap plus the PSM so the strategy gets more USDS. It reports its value as staked USDS plus loose USDS.
[Feynman: GroveCompounder.constructor] Deployment checks the external staking program is usable for USDS, records the reward token, gives long-lived spending approval to staking and the PSM wrapper, then configures the reward sale path.
[Feynman: balanceOfAsset] This reports how much loose USDS the strategy currently holds.
[Feynman: balanceOfStake] This reports how much USDS the staking contract says the strategy has deposited.
[Feynman: balanceOfRewards] This reports how much unsold GROVE the strategy currently holds.
[Feynman: claimableRewards] This asks the staking program how much GROVE the strategy can claim now.
[Feynman: _deployFunds] This moves newly available USDS into staking under the current referral code.
[Feynman: _freeFunds] This pulls requested USDS back out of staking for withdrawals.
[Feynman: _harvestAndReport] This claims rewards, sells or auctions them if above the configured floor, restakes loose USDS above dust, then reports staked plus loose USDS.
[Socratic: src/GroveCompounder.sol:98 - why?] Why does the direct swap path require zero PSM fee? Because the code assumes the USDC-to-USDS leg should be one-for-one; if a fee exists, the strategy would knowingly sell rewards through a lossy route.
[Inversion: _harvestAndReport] Attack moves: make `useAuction=false` and sandwich the zero-minimum V3 sale; make the PSM report a nonzero fee so reports revert only on the swap path; donate just-under-dust USDS so it remains idle but still counted.
[Feynman: _emergencyWithdraw] This withdraws up to the requested amount from staking, capped by what the strategy actually has staked.
[Feynman: availableDepositLimit] This closes deposits when the staking program is paused, otherwise it applies the strategy's normal open/allow-list deposit gate.
[Feynman: _min] This returns the smaller of two numbers.
[Feynman: claimRewards] This lets management collect pending GROVE into the strategy without reporting.
[Feynman: _claimRewards] This calls the staking program to move earned GROVE to the strategy.
[Feynman: kickAuction] This lets a keeper start an auction for GROVE after claiming it, or for another non-USDS token already sitting in the strategy.
[Socratic: src/GroveCompounder.sol:169 - why?] Why is every token compared against the reward token's sale floor? The code appears to assume keepers mostly kick `REWARDS_TOKEN`, so arbitrary-token dust handling is not token-specific.
[Inversion: kickAuction] Attack moves: pass `asset` as `_token` and expect `_kickAuction` to reject it; pass an unsupported donated token and rely on `Auction.kick` reverting the whole transaction; pass a supported non-reward token whose decimals make the reward floor inappropriate.
[Feynman: _kickAuction] This sends a token balance to the configured auction contract and asks that auction to start selling it, while refusing to auction the strategy's USDS asset.
[Feynman: setMinAmountToSell] This lets management update the GROVE amount needed before the strategy sells or auctions rewards.
[Feynman: setUniV3Fees] This lets management choose the Uniswap V3 pool fee used for GROVE to USDC swaps.
[Feynman: setAuction] This lets management choose the auction contract after checking that auction pays USDS back to this strategy, or clear it only when auction mode is off.
[Inversion: setAuction] Attack moves: set an auction with a different receiver and hit the receiver check; set an auction whose wanted token is not USDS and hit the want check; clear the auction while auction mode is still on and hit the mode check.
[Feynman: setUseAuction] This switches reward selling between the auction route and direct Uniswap route, requiring an auction address before enabling auction mode.
[Feynman: setReferral] This updates the referral value attached to future staking deposits.

[Feynman: GroveCompounderAprOracle] This helper estimates the strategy APR by reading the global staking reward rate, pricing one GROVE in USDS terms, adjusting total staked USDS by a requested debt change, and returning a capped yearly rate.
[Feynman: GroveCompounderAprOracle.constructor] Deployment records the deployer as manager and installs four default Uniswap V4 GROVE/USDC pool ids as backup price sources.
[Feynman: aprAfterDebtChange] This reads total staked USDS and GROVE emitted per second, returns zero if the reward period is already over, prices GROVE, applies the requested stake increase or decrease, then returns yearly reward value divided by adjusted stake.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:118 - why?] Why is price read before the debt delta is applied? Because the code assumes changing this strategy's debt only changes the denominator, not the market price of GROVE.
[Inversion: aprAfterDebtChange] Attack moves: pass a negative delta equal to all global staking supply to force the zero-denominator revert; push the GROVE price high enough to hit the 50% APR cap and revert; manipulate the preferred spot price within the cap so consumers see a still-valid but wrong APR.
[Feynman: setManagement] This transfers oracle management to a nonzero address.
[Feynman: setUniV3Fee] This updates the Uniswap V3 fee only if the official factory has a GROVE/USDC pool for that fee.
[Feynman: setUniV4Pool] This replaces all backup V4 pools with one nonzero configured pool id and token direction.
[Feynman: setUniV4Pools] This replaces all backup V4 pools with a nonempty, aligned, duplicate-free list.
[Feynman: addUniV4Pool] This appends one nonzero V4 pool id if it is not already configured.
[Feynman: removeUniV4Pool] This removes one configured V4 pool by replacing it with the last entry, while never allowing the list to become empty.
[Feynman: uniV3Pool] This returns the current GROVE/USDC V3 pool for the configured fee.
[Feynman: uniV4PoolCount] This returns how many V4 backup pools are configured.
[Feynman: uniV4Pool] This returns the configured pool id and direction at one index.
[Feynman: groveUsdcV4PoolId] This returns the first configured V4 pool id.
[Feynman: v4GroveIsToken0] This returns the first configured V4 pool's GROVE direction.
[Feynman: bestUniV4Pool] This returns the selected V4 backup pool without the price.
[Feynman: selectedUniV4Pool] This returns the selected V4 backup pool with the price used for APR.
[Feynman: _grovePrice] This first tries to price one GROVE through the current V3 pool; if that does not return a positive value, it falls back to the selected V4 backup price, and otherwise reverts.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:212 - why?] Why does V3 win without comparing against V4? Because the code treats liquidity and USDC balance as enough proof that the current V3 quote is trustworthy.
[Inversion: _grovePrice] Attack moves: keep V3 above the liquidity and USDC-balance thresholds while moving its current quote; make the V3 simulation return zero or revert so V4 is used; make all V4 candidates return zero so the oracle reverts.
[Feynman: _v3PoolHasUsableLiquidity] This checks that the configured V3 pool exists, has enough active liquidity, and holds at least 1,000 USDC.
[Feynman: _v4GrovePrice] This turns a V4 pool square-root price into a USDS-scaled price for one GROVE, using the configured token direction.
[Feynman: _selectedV4Pool] This gathers usable V4 pool quotes, computes their median price, then chooses the highest-liquidity quote that stays within 10% of that median.
[Socratic: src/periphery/GroveCompounderAprOracle.sol:275 - why?] Why is the internal price conversion inside the successful external-call branch? The code assumes a nonzero pool price can always be converted safely, so only `getLiquidity` and `getSlot0` failures are skipped.
[Inversion: _selectedV4Pool] Attack moves: make one configured pool's external reads revert so it is skipped; make one configured pool return extreme square-root price so internal conversion reverts before median filtering; manipulate the highest-liquidity near-median pool so it is selected.
[Feynman: _medianPrice] This copies quote prices, sorts them from low to high, and returns the middle value or average of the two middle values.
[Feynman: _withinV4PriceDeviation] This checks whether a quote is no more than 10% away from the median reference price.
[Feynman: _setUniV4Pools] This validates and stores a new full V4 pool list.
[Feynman: _hasUniV4Pool] This scans the configured list for a pool id.
[Feynman: _uniV3Pool] This returns the V3 pool for the currently configured fee.
[Feynman: _uniV3PoolForFee] This asks the official V3 factory for the GROVE/USDC pool at a fee.
[Feynman: _quoteToken1ForToken0] This computes how much token1 one unit of token0 is worth at a square-root price.
[Feynman: _quoteToken0ForToken1] This computes how much token0 one unit of token1 is worth at a square-root price.

## Leads

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: single-block-spot-oracle | group_key: GroveCompounderAprOracle | _grovePrice | single-block-spot-oracle
code_smells: `aprAfterDebtChange()` trusts `_grovePrice()` for the numerator at `src/periphery/GroveCompounderAprOracle.sol:118` and only caps the final APR at `src/periphery/GroveCompounderAprOracle.sol:132`. `_grovePrice()` always prefers the V3 path when `_v3PoolHasUsableLiquidity()` passes, returning `output * 1e12` from a one-GROVE simulated swap at `src/periphery/GroveCompounderAprOracle.sol:211-229`. The usability gate only checks nonzero pool, active liquidity, and the pool's USDC balance at `src/periphery/GroveCompounderAprOracle.sol:239-245`; it does not use a TWAP, previous observation, or the configured V4 pool set as a cross-check before returning the V3 spot quote.
description: A same-block GROVE/USDC V3 price move can feed a manipulated but still-under-cap APR to any allocator or keeper system consuming this oracle; the remaining unverified link is an in-scope state-changing consumer that acts on `getStrategyApr()`/`aprAfterDebtChange()` in the same transaction or block.

LEAD | contract: GroveCompounderAprOracle | function: _selectedV4Pool | bug_class: fallback-oracle-dos | group_key: GroveCompounderAprOracle | _selectedV4Pool | fallback-oracle-dos
code_smells: `_selectedV4Pool()` catches failures from `getLiquidity()` and `getSlot0()` at `src/periphery/GroveCompounderAprOracle.sol:267-285`, but the internal `_v4GrovePrice()` conversion at `src/periphery/GroveCompounderAprOracle.sol:275` is not protected by those catches. With `groveIsToken0 == false` and `sqrtPriceX96 == 1`, `_quoteToken0ForToken1()` computes `ratioX192 = 1` and then attempts `FullMath.mulDiv(Q192, 1e18, 1)` at `src/periphery/GroveCompounderAprOracle.sol:384-388`, which cannot fit in `uint256` and reverts before the median/deviation logic can skip that quote. Because the loop aborts on that internal revert, one configured V4 pool with sufficient reported liquidity can make the whole fallback path revert even if later configured pools would be usable.
description: The V4 fallback can be denied by one pathological configured quote; the remaining unverified link is attacker feasibility for driving one of the default configured V4 pools to such an extreme active price while the V3 preferred path is unusable.

## Rejected / Notes

- `GroveCompounder._harvestAndReport()` passes `_minAmountOut = 0` to the direct V3 reward sale at `src/GroveCompounder.sol:96-105`. This can leak reward value to MEV when management disables auction mode, but the default path is auction mode, the branch reverts if the PSM fee is nonzero, and the impact from the scoped code is lost unreported yield rather than a demonstrated loss of already-accounted strategy principal.
- `GroveCompounder.kickAuction()` compares non-reward tokens against `minAmountToSell[REWARDS_TOKEN]` at `src/GroveCompounder.sol:158-170`. This makes arbitrary donated-token sweeping imprecise, but keepers cannot auction the asset due to `src/GroveCompounder.sol:174-179`, and unsupported-token `Auction.kick()` failures revert the prior transfer with the transaction.
- The staking deposit, withdrawal, emergency withdrawal, paused-deposit, auction-address validation, V4 list uniqueness, V4 nonempty-list, and APR zero-denominator/cap branches were reviewed without a source-backed FINDING.
