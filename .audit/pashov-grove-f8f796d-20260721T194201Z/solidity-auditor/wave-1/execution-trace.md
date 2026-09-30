# Execution Trace Lane - Grove

Primary scope reviewed:
- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

FINDINGs: none.

## Mental tool markers

[Feynman: GroveCompounder] This contract accepts USDS from the Yearn strategy machinery, parks that USDS in the Sky staking contract, claims GROVE rewards, and either sends those rewards to an auction or swaps them through USDC back into USDS. The important execution story is: user assets become stake, stake can be withdrawn, rewards are only assets after a sale, and any USDS sitting in the contract can be staked again on report.

[Feynman: GroveCompounder.constructor] Deployment checks that staking is live and that the PSM wrapper and staking contract agree on USDS. It then gives the staking contract permission to pull USDS, gives the PSM wrapper permission to pull USDC, records GROVE as the reward token, and configures USDC as the sale route for rewards.

[Feynman: balanceOfAsset] This reports how much unstaked USDS is sitting in the strategy contract.

[Feynman: balanceOfStake] This reports how much USDS the strategy has parked in the staking contract.

[Feynman: balanceOfRewards] This reports how much GROVE reward token is currently held by the strategy.

[Feynman: claimableRewards] This asks the staking contract how much GROVE the strategy can claim right now.

[Feynman: _deployFunds] This takes newly available USDS and parks it in the staking contract using the current referral code.

[Feynman: _freeFunds] This pulls USDS back out of the staking contract.

[Feynman: _harvestAndReport] This claims GROVE, either sells it or moves it into the auction path if the reward balance is large enough, stakes any newly produced USDS above dust while the strategy is live, and finally reports staked plus idle USDS as total assets.

[Socratic: src/GroveCompounder.sol:100 - why?] Why is the minimum received from the reward swap zero? The implicit belief is that keeper timing, configured pools, or the surrounding strategy process will tolerate whatever price the swap route returns.

[Inversion: _harvestAndReport] Attacker move 1: let claimed GROVE sit just below `minAmountToSell[REWARDS_TOKEN]` so report records no realized asset value. Attacker move 2: when UniV3 mode is enabled, distort the GROVE/USDC pool before the keeper report because `_swapFrom(..., 0)` accepts any non-reverting output. Attacker move 3: donate USDC to the strategy before report and confirm line 104 sends the whole base balance through the PSM; this converts to strategy USDS rather than leaking value out.

[Feynman: _emergencyWithdraw] This caps the requested emergency withdrawal to the amount actually staked, then withdraws that much USDS.

[Feynman: availableDepositLimit] This closes deposits while staking is paused, otherwise it delegates the decision to the inherited strategy rules.

[Feynman: _min] This returns the smaller of two numbers.

[Feynman: claimRewards] Management can manually pull claimable GROVE from staking into the strategy.

[Feynman: _claimRewards] This asks the staking contract to send the strategy its earned GROVE.

[Feynman: kickAuction] A keeper can claim GROVE when the requested token is the reward token, or read the strategy balance of another token, then send the token to the configured auction if the balance is above the reward-token sale threshold.

[Socratic: src/GroveCompounder.sol:169 - why?] Why does the non-reward token branch compare against the reward token's threshold? The implicit belief is that auction kicks are primarily for GROVE and other token balances are incidental recovery balances.

[Inversion: kickAuction] Attacker move 1: call with `address(asset)` after donating USDS; `_kickAuction` rejects at line 175. Attacker move 2: call with a non-reward token that the auction has not enabled; the transfer and kick are in one transaction, so a revert leaves strategy state unchanged. Attacker move 3: call with GROVE while `useAuction` is false; line 159 blocks the path.

[Feynman: _kickAuction] This prevents USDS from being auctioned, checks that an auction exists, transfers the selected token to the auction, and tells the auction to start selling that token.

[Feynman: setMinAmountToSell] Management updates the GROVE sale threshold.

[Feynman: setUniV3Fees] Management updates the UniV3 fee tier used for the GROVE-to-USDC route.

[Feynman: setAuction] Management sets or clears the auction address. A nonzero auction must report this strategy as receiver and USDS as want; clearing is allowed only after auction mode has been disabled.

[Feynman: setUseAuction] Management switches between auction and UniV3 reward sale modes, but cannot switch into auction mode without an auction address.

[Feynman: setReferral] Management changes the referral number used for future staking calls.

[Feynman: GroveCompounderAprOracle] This contract estimates the staking APR by reading the staking reward rate and total staked USDS, pricing one GROVE through UniV3 first and UniV4 fallback pools second, and dividing yearly reward value by the adjusted staking base.

[Feynman: _onlyManagement] This rejects callers other than the current management address.

[Feynman: GroveCompounderAprOracle.constructor] Deployment records the deployer as management and installs four default UniV4 pool ids as fallback price sources.

[Feynman: aprAfterDebtChange] This reads total staked USDS and GROVE emissions, returns zero after the reward period, prices GROVE, applies a proposed debt increase or decrease to the staking base, and returns the implied yearly reward rate if it is not above the oracle cap.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:114 - why?] Why does the oracle still quote a positive APR when `block.timestamp == periodFinish()`? The implicit belief is that only timestamps strictly after the finish are outside the live reward period.

[Inversion: aprAfterDebtChange] Attacker move 1: pass `_delta = -int256(assets + 1)` and force an underflow revert in a direct oracle call. Attacker move 2: manipulate the price source before a same-transaction oracle read, because the APR calculation trusts `_grovePrice()`. Attacker move 3: call exactly at `periodFinish` and observe that the function does not take the zero-APR branch.

[Feynman: setManagement] Management hands control to a nonzero new management address.

[Feynman: setUniV3Fee] Management selects a UniV3 fee tier only if the router factory reports that a GROVE/USDC pool exists for that fee.

[Feynman: setUniV4Pool] Management replaces all fallback pools with one nonzero pool id and a direction flag.

[Feynman: setUniV4Pools] Management replaces all fallback pools with a nonempty, same-length, duplicate-free list of pool ids and direction flags.

[Feynman: addUniV4Pool] Management appends one nonzero fallback pool id if it is not already configured.

[Feynman: removeUniV4Pool] Management removes one fallback pool by index while keeping at least one configured fallback pool.

[Feynman: uniV3Pool] This returns the current GROVE/USDC UniV3 pool address for the selected fee tier.

[Feynman: uniV4PoolCount] This returns how many fallback UniV4 pools are configured.

[Feynman: uniV4Pool] This returns the configured pool id and direction flag at one index.

[Feynman: groveUsdcV4PoolId] This returns the first configured UniV4 pool id.

[Feynman: v4GroveIsToken0] This returns the first configured UniV4 pool direction flag.

[Feynman: bestUniV4Pool] This returns the fallback pool selected by the internal median-and-liquidity logic, without returning its price.

[Feynman: selectedUniV4Pool] This returns the fallback pool selected by the internal median-and-liquidity logic, including its price.

[Feynman: _grovePrice] This first asks the UniV3 route what one GROVE would sell for in USDC if the V3 pool passes a minimal usability gate. If that fails or returns zero, it asks the UniV4 fallback selector for a price. If neither path produces a price, it reverts.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:212 - why?] Why does a minimally usable V3 pool short-circuit the V4 median pool logic instead of being compared against it? The implicit belief is that active V3 liquidity plus a 1,000 USDC pool balance is enough to trust the simulated V3 price.

[Inversion: _grovePrice] Attacker move 1: distort the GROVE/USDC V3 price while leaving `liquidity()` at least `1e12` and USDC balance at least `1_000e6`, so line 228 returns before V4 checks. Attacker move 2: make the V3 simulation revert so the function falls into V4 and then target the fallback pool set. Attacker move 3: leave only one usable V4 quote so the median check has no independent price disagreement to reject.

[Feynman: _v3PoolHasUsableLiquidity] This treats a V3 pool as usable when the selected pool exists, has at least the configured active liquidity, and holds at least the configured amount of USDC.

[Feynman: _v4GrovePrice] This converts a UniV4 square-root price into the USDS-scaled value of one GROVE, using the direction flag to decide which quote formula applies.

[Feynman: _selectedV4Pool] This reads every configured fallback pool, keeps only pools with enough liquidity and a nonzero price, computes the median price, ignores quotes more than 10 percent away from that median, and selects the remaining quote with the most liquidity.

[Inversion: _selectedV4Pool] Attacker move 1: make all but one configured V4 pool unusable so the remaining quote becomes the median. Attacker move 2: move two configured pools together so their manipulated prices define the median band. Attacker move 3: keep a manipulated pool inside the 10 percent band and give it the highest liquidity so line 296 selects it.

[Feynman: _medianPrice] This copies the collected prices, sorts them, and returns the middle price or the average of the two middle prices.

[Feynman: _withinV4PriceDeviation] This checks whether one price is within 10 percent of a reference price.

[Feynman: _setUniV4Pools] This validates a new fallback pool list, clears the old list, rejects zero and duplicate pool ids, and stores each pool id with its direction flag.

[Feynman: _hasUniV4Pool] This scans the configured fallback pool list for a matching id.

[Feynman: _uniV3Pool] This returns the pool address for the currently configured UniV3 fee tier.

[Feynman: _uniV3PoolForFee] This asks the UniV3 factory behind the router for the GROVE/USDC pool at a specific fee tier.

[Feynman: _quoteToken1ForToken0] This quotes how much token1 corresponds to a token0 amount at the supplied square-root price.

[Feynman: _quoteToken0ForToken1] This quotes how much token0 corresponds to a token1 amount at the supplied square-root price.

## Leads

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: v3-priority-oracle-manipulation | group_key: GroveCompounderAprOracle | _grovePrice | v3-priority-oracle-manipulation
code_smells: `aprAfterDebtChange` consumes `_grovePrice()` before computing APR at `src/periphery/GroveCompounderAprOracle.sol:118` and `src/periphery/GroveCompounderAprOracle.sol:131`. `_grovePrice()` returns the UniV3 simulation result as soon as `_v3PoolHasUsableLiquidity()` passes and `output > 0` at `src/periphery/GroveCompounderAprOracle.sol:211-229`. The V3 usability gate only checks pool existence, `liquidity() >= 1e12`, and USDC balance `>= 1_000e6` at `src/periphery/GroveCompounderAprOracle.sol:239-245`. Once the V3 branch returns, the multi-pool V4 fallback and median selection at `src/periphery/GroveCompounderAprOracle.sol:232-236` and `src/periphery/GroveCompounderAprOracle.sol:255-305` are never consulted.
path: external caller or allocator -> `aprAfterDebtChange(_strategy, _delta)` -> `_grovePrice()` -> V3 pool passes minimal liquidity/balance gate -> `simulateExactInputSingle(... amountIn: 1e18, amountOutMinimum: 0 ...)` returns manipulated `output` -> APR uses `output * 1e12`.
description: If an attacker can move the configured GROVE/USDC V3 pool price while leaving the minimal liquidity and USDC-balance checks true, the oracle will prefer that manipulated V3 quote over the more redundant V4 median fallback; downstream allocator impact and manipulation cost remain unverified.

## Rejected / Notes

- Strategy reward-sale trace did not produce a source-backed value leak. In auction mode `_harvestAndReport` moves only non-asset rewards to the configured auction after `_kickAuction` rejects `address(asset)` at `src/GroveCompounder.sol:174-179`; in UniV3 mode, any existing USDC base balance is sold through the PSM into strategy-owned USDS at `src/GroveCompounder.sol:100-105`.
- `kickAuction(address _token)` uses `minAmountToSell[REWARDS_TOKEN]` for non-reward tokens at `src/GroveCompounder.sol:169`, but the path is keeper-gated, rejects USDS at `src/GroveCompounder.sol:175`, and transfers to an auction whose receiver and want were checked by management at `src/GroveCompounder.sol:209-216`. I did not find a direct user-asset loss or untrusted-caller exploit from this threshold mismatch.
- `aprAfterDebtChange` can revert for impossible negative debt changes larger than total staking supply at `src/periphery/GroveCompounderAprOracle.sol:121-122`, but this is a view-call input rejection without a proven downstream exploit path in the scoped code.
- `aprAfterDebtChange` returns zero only when `block.timestamp > periodFinish()` at `src/periphery/GroveCompounderAprOracle.sol:114-116`; at exact equality it can still quote a positive APR. I did not escalate this one-timestamp boundary behavior without evidence that a consumer can be harmed at that exact state.

Validation: static execution trace only; no tests or source modifications were performed.
