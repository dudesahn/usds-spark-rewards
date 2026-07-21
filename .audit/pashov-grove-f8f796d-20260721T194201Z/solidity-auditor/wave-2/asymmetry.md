# Asymmetry lane: Grove compounder

Scope reviewed:
- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

## Mental tool markers

[Feynman: GroveCompounder] This contract takes USDS from depositors, puts it into the Sky staking contract, collects GROVE rewards, and turns those rewards back into more USDS either by sending them to an auction or by selling them through the GROVE/USDC pool and the PSM. The delicate part is that the two sale routes do not protect value in the same way.

[Feynman: GroveCompounder.constructor] This sets the staking and PSM wiring, checks that staking is live and accepts the same USDS token, records the reward token, grants spending permission to staking and the PSM, then configures USDC as the intermediate token for direct reward sales.

[Feynman: balanceOfAsset] This reports how much loose USDS the strategy currently holds.

[Feynman: balanceOfStake] This reports how much USDS the strategy has placed into staking.

[Feynman: balanceOfRewards] This reports how much GROVE reward token is sitting directly in the strategy.

[Feynman: claimableRewards] This asks the staking contract how much GROVE the strategy has earned but not yet collected.

[Feynman: _deployFunds] This takes idle USDS and places it into staking using the current referral code.

[Feynman: _freeFunds] This pulls USDS back out of staking so withdrawals can be paid.

[Feynman: _harvestAndReport] This collects GROVE rewards, chooses either the direct-swap path or auction path when the reward balance is large enough, restakes any loose USDS if the strategy is still active, and reports staked plus loose USDS as total assets.

[Socratic: src/GroveCompounder.sol:100 - why?] Why does the direct swap accept zero as the minimum USDC received when the auction path avoids immediate spot execution entirely?

[Inversion: _harvestAndReport] 1. Set `useAuction=false`, wait until rewards are just over `minAmountToSell`, then move the GROVE/USDC spot before the keeper report. 2. Leave `useAuction=true` with `auction == address(0)` during bootstrap and let rewards build until reports revert on `!auction`. 3. Send non-reward tokens to the strategy and test whether the keeper-only generic auction kick uses the wrong token's threshold.

[Feynman: _emergencyWithdraw] This withdraws no more than the strategy actually has staked, so an emergency request larger than the staked balance does not ask staking for impossible funds.

[Feynman: availableDepositLimit] This closes new deposits while staking is paused, otherwise it falls back to the normal deposit gate.

[Inversion: availableDepositLimit] 1. Pause staking between a deposit preview and the actual deposit. 2. Keep withdrawals possible while deposits are closed. 3. Check whether a paused staking contract can also block reward reports through reward collection or restaking.

[Feynman: _min] This returns the smaller of two numbers.

[Feynman: claimRewards] This lets management collect earned GROVE into the strategy without selling it.

[Feynman: _claimRewards] This asks staking to pay the strategy its earned GROVE.

[Feynman: kickAuction] This lets a keeper send available reward tokens, or another non-USDS token already sitting in the strategy, into the configured auction when auction mode is active.

[Socratic: src/GroveCompounder.sol:169 - why?] Why is a non-reward token's auction threshold compared to the reward token's `minAmountToSell` entry instead of the token being kicked?

[Feynman: _kickAuction] This refuses to auction USDS itself, checks that an auction address exists, sends the chosen token to that auction, and starts the auction.

[Feynman: setMinAmountToSell] This lets management change the reward balance threshold that must be crossed before rewards are sold or auctioned.

[Feynman: setUniV3Fees] This lets management change the pool fee used for direct GROVE-to-USDC sales.

[Feynman: setAuction] This lets management choose the auction contract, but only if that auction pays this strategy and asks buyers for USDS; clearing the auction is allowed only after auction mode is off.

[Inversion: setAuction] 1. Set an auction that has the right receiver and want token but has not enabled GROVE. 2. Try to clear the auction while `useAuction=true`. 3. Move from one valid auction to another while the old one still holds kicked rewards.

[Feynman: setUseAuction] This switches reward selling between auction mode and direct pool-selling mode, and requires an auction address before auction mode is turned on.

[Feynman: setReferral] This changes the referral code sent with future staking deposits.

[Feynman: GroveCompounderAprOracle] This contract estimates the strategy's APR from Sky's reward speed, total staked USDS, and a GROVE price. It prefers the Uniswap V3 GROVE/USDC pool when it looks usable, otherwise it falls back to configured Uniswap V4 pools.

[Feynman: GroveCompounderAprOracle.constructor] This records the deployer as manager and installs four default V4 pool candidates.

[Feynman: aprAfterDebtChange] This calculates what APR would be after adding or removing a given amount of staked USDS from the global staking total.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:109 - why?] Why is `_strategy` accepted but never used, and is this oracle intentionally only for the single global staking market rather than per-strategy state?

[Inversion: aprAfterDebtChange] 1. Pass a negative change larger than total staking supply. 2. Move the price source while keeping the final APR below the cap. 3. Query exactly at `periodFinish` where the function still treats the reward period as live.

[Feynman: setManagement] This hands manager authority to a new nonzero address.

[Feynman: setUniV3Fee] This changes which V3 fee tier is used, but only if a pool exists for that tier.

[Feynman: setUniV4Pool] This replaces all V4 candidates with one nonzero pool.

[Feynman: setUniV4Pools] This replaces all V4 candidates with a supplied non-empty, duplicate-free list.

[Feynman: addUniV4Pool] This adds one new nonzero V4 pool candidate if it is not already configured.

[Feynman: removeUniV4Pool] This removes one V4 pool candidate by swapping in the last entry, while keeping at least one pool configured.

[Feynman: uniV3Pool] This reports the V3 pool address for the currently configured fee tier.

[Feynman: uniV4PoolCount] This reports how many V4 pool candidates are configured.

[Feynman: uniV4Pool] This reports the pool id and token ordering flag for one configured V4 candidate.

[Feynman: groveUsdcV4PoolId] This reports the first configured V4 pool id for backward-compatible callers.

[Feynman: v4GroveIsToken0] This reports whether GROVE is the first token in the first configured V4 pool.

[Feynman: bestUniV4Pool] This reports the selected V4 pool candidate and its liquidity.

[Feynman: selectedUniV4Pool] This reports the selected V4 pool candidate, its ordering flag, liquidity, and price.

[Feynman: _grovePrice] This gets a GROVE price by first trusting a usable V3 pool quote, and only if that path is unavailable or fails does it ask the V4 pool-selection logic.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:228 - why?] Why does a positive V3 quote return immediately without being compared against the V4 median/deviation machinery below it?

[Inversion: _grovePrice] 1. Keep the V3 pool barely above the liquidity and USDC-balance thresholds, then move its spot before the oracle read. 2. Make the V3 simulator return a tiny positive output so V4 fallback is skipped. 3. Push the price high enough to bias allocation but low enough that `MAX_EXPECTED_APR` does not revert.

[Feynman: _v3PoolHasUsableLiquidity] This checks that the selected V3 pool exists, has enough active liquidity, and holds at least 1,000 USDC.

[Feynman: _v4GrovePrice] This converts a V4 square-root price into a USDS-per-GROVE price using the configured token ordering.

[Feynman: _selectedV4Pool] This gathers usable V4 pool quotes, computes their median price, ignores candidates more than 10% from that median, and chooses the most liquid remaining candidate.

[Inversion: _selectedV4Pool] 1. Configure a single V4 pool so the median check compares the pool only to itself. 2. With two pools, move one far enough from the other that both may fail the 10% midpoint check. 3. Add many pools so the view path becomes expensive for callers.

[Feynman: _medianPrice] This sorts the collected prices and returns the middle price, or the average of the two middle prices.

[Feynman: _withinV4PriceDeviation] This checks whether a candidate price is within 10% of the reference price.

[Feynman: _setUniV4Pools] This validates a new V4 pool list, clears the old list, and stores each unique nonzero pool with its token-ordering flag.

[Feynman: _hasUniV4Pool] This scans the stored V4 pool list to see whether a pool id is already present.

[Feynman: _uniV3Pool] This looks up the V3 pool for the current fee setting.

[Feynman: _uniV3PoolForFee] This asks the V3 factory for the GROVE/USDC pool at a given fee.

[Feynman: _quoteToken1ForToken0] This calculates how much second token one unit of first token is worth at a given V4 price.

[Feynman: _quoteToken0ForToken1] This calculates how much first token one unit of second token is worth at a given V4 price.

## Paired surfaces enumerated

- Stake/unstake: `_deployFunds` (`src/GroveCompounder.sol:76`) stakes USDS with `referral`; `_freeFunds` (`src/GroveCompounder.sol:80`) withdraws USDS. No storage-write asymmetry.
- Deposit gate/staking write: `availableDepositLimit` (`src/GroveCompounder.sol:125`) blocks deposits while staking is paused; `_deployFunds` (`src/GroveCompounder.sol:76`) relies on staking to enforce live staking at execution time. This is expected preview/execution asymmetry.
- Reward claim/sale: `claimRewards` (`src/GroveCompounder.sol:145`) only claims; `_harvestAndReport` (`src/GroveCompounder.sol:84`) claims then sells or auctions; `kickAuction` (`src/GroveCompounder.sol:158`) claims only for `REWARDS_TOKEN` and otherwise uses the token balance already present.
- Reward sale branches: direct UniV3 path (`src/GroveCompounder.sol:96-105`) versus auction path (`src/GroveCompounder.sol:107-109`).
- Auction config pair: `setAuction` (`src/GroveCompounder.sol:209`) validates receiver/want and can clear only when auction mode is off; `setUseAuction` (`src/GroveCompounder.sol:224`) can enable auction mode only when an auction address exists.
- APR delta branches: negative `_delta` subtracts assets (`src/periphery/GroveCompounderAprOracle.sol:121-122`); positive `_delta` adds assets (`src/periphery/GroveCompounderAprOracle.sol:123-124`).
- Oracle price branches: V3 quote path (`src/periphery/GroveCompounderAprOracle.sol:211-229`) versus V4 fallback/median path (`src/periphery/GroveCompounderAprOracle.sol:232-236`, `255-304`).
- V4 config variants: replace-one (`src/periphery/GroveCompounderAprOracle.sol:147-151`), replace-many (`src/periphery/GroveCompounderAprOracle.sol:154-155`, `338-355`), add (`src/periphery/GroveCompounderAprOracle.sol:158-163`), remove (`src/periphery/GroveCompounderAprOracle.sol:166-175`).
- V4 quote direction pair: GROVE token0 branch (`src/periphery/GroveCompounderAprOracle.sol:248-249`) versus GROVE token1 branch (`src/periphery/GroveCompounderAprOracle.sol:251-252`).

## Storage lifecycle summary

- `GroveCompounder.referral`: initialized to `2009` (`src/GroveCompounder.sol:16`), written by `setReferral` (`src/GroveCompounder.sol:234-235`), read by `_deployFunds` (`src/GroveCompounder.sol:76-77`). No issue.
- `GroveCompounder.auction`: written by `setAuction` (`src/GroveCompounder.sol:209-216`), read by `_kickAuction` (`src/GroveCompounder.sol:176-179`) and `setUseAuction` (`src/GroveCompounder.sol:224-226`). No issue beyond bootstrap/config notes below.
- `GroveCompounder.useAuction`: initialized true (`src/GroveCompounder.sol:22`), written by `setUseAuction` (`src/GroveCompounder.sol:224-226`), read by `_harvestAndReport`, `kickAuction`, and `setAuction` (`src/GroveCompounder.sol:96`, `159`, `214`). Direct-swap branch has materially weaker value protection.
- `GroveCompounder.minAmountToSell[REWARDS_TOKEN]`: written in constructor and setter (`src/GroveCompounder.sol:52`, `192`), read by `_harvestAndReport` and `kickAuction` (`src/GroveCompounder.sol:94`, `169`), and rechecked by inherited `_swapFrom` (`lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:72`). The generic non-reward `kickAuction` threshold mismatch is noted but not escalated.
- `GroveCompounderAprOracle.management`: written in constructor and `setManagement` (`src/periphery/GroveCompounderAprOracle.sol:95-101`, `135-138`), read by `_onlyManagement` (`src/periphery/GroveCompounderAprOracle.sol:91-93`). No issue.
- `GroveCompounderAprOracle.rewardToBaseUniV3Fee`: initialized to default (`src/periphery/GroveCompounderAprOracle.sol:81`), written by `setUniV3Fee` after pool-existence check (`src/periphery/GroveCompounderAprOracle.sol:141-144`), read by V3 pool lookup and quote (`src/periphery/GroveCompounderAprOracle.sol:218`, `366-371`). The price branch has weaker validation than V4.
- `GroveCompounderAprOracle.v4Pools`: initialized with four defaults (`src/periphery/GroveCompounderAprOracle.sol:95-101`), written by set/add/remove paths (`src/periphery/GroveCompounderAprOracle.sol:147-175`, `338-355`), read by getters and `_selectedV4Pool` (`src/periphery/GroveCompounderAprOracle.sol:182-208`, `260-304`). No direct storage bug.

## Findings / Leads

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: asymmetric-slippage-protection | group_key: GroveCompounder | _harvestAndReport | asymmetric-slippage-protection
path: management sets `useAuction=false` via `setUseAuction` (`src/GroveCompounder.sol:224-226`) -> keeper `report()` enters `_harvestAndReport` -> rewards above `minAmountToSell[REWARDS_TOKEN]` enter the direct UniV3 branch (`src/GroveCompounder.sol:96-100`) -> manipulated GROVE/USDC spot is accepted because `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` passes zero minimum output -> USDC is immediately converted to USDS through the PSM (`src/GroveCompounder.sol:102-105`) -> reward value can be extracted by a sandwich attacker before the strategy reports assets (`src/GroveCompounder.sol:111-117`).
pair_or_branch: direct UniV3 reward-sale branch (`src/GroveCompounder.sol:96-105`) versus auction reward-sale branch (`src/GroveCompounder.sol:107-109`).
asymmetry: the direct branch executes an immediate AMM sale with `_minAmountOut = 0`, while the auction branch only transfers rewards to the configured auction and does not accept a same-transaction spot quote.
proof: With `useAuction=false`, `toSwap = 5_000e18 + 1` and `minAmountToSell[REWARDS_TOKEN] = 5_000e18`, the branch condition at `src/GroveCompounder.sol:97` is true. The strategy then calls `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` at `src/GroveCompounder.sol:100`. The inherited swapper checks only that `_amountIn >= minAmountToSell[_from]` (`lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:72`) and places `_minAmountOut` directly into the Uniswap `amountOutMinimum` field (`lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:75-83`). Therefore a report sandwiched so the pool returns only 1 USDC unit still succeeds, after which `PSM_WRAPPER.sellGem` converts that tiny USDC balance to USDS (`src/GroveCompounder.sol:102-105`) and `_totalAssets` records only staked plus loose USDS (`src/GroveCompounder.sol:117`). The difference between fair output and accepted output is lost reward value.
description: Supported direct-swap mode lacks the value protection present in the auction route, letting a public keeper report sell all accrued GROVE at an attacker-controlled spot price.
fix: Require a nonzero, oracle/TWAP-derived minimum output or remove the direct UniV3 reward-sale mode in favor of auction-only liquidation.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: asymmetric-oracle-validation | group_key: GroveCompounderAprOracle | _grovePrice | asymmetric-oracle-validation
code_smells: `_grovePrice` returns the V3 simulated spot quote immediately when `_v3PoolHasUsableLiquidity()` is true and output is positive (`src/periphery/GroveCompounderAprOracle.sol:211-229`), while the V4 fallback collects multiple pool quotes, computes a median, filters candidates outside `MAX_V4_POOL_PRICE_DEVIATION_BPS`, and selects the most liquid remaining pool (`src/periphery/GroveCompounderAprOracle.sol:255-304`, `333-335`). The V3 usability check only requires active liquidity and a 1,000 USDC pool balance (`src/periphery/GroveCompounderAprOracle.sol:239-244`), so V4 median validation is skipped even when V4 pools are configured.
pair_or_branch: V3 oracle branch (`src/periphery/GroveCompounderAprOracle.sol:211-229`) versus V4 fallback branch (`src/periphery/GroveCompounderAprOracle.sol:232-236`, `255-304`).
asymmetry: V3 price acceptance has no cross-source deviation check, no TWAP, and no comparison to the configured V4 median, while V4 prices are explicitly median/deviation filtered.
description: If the live V3 GROVE/USDC pool can be moved economically while still satisfying the low liquidity/balance thresholds, `aprAfterDebtChange` can be biased because `_grovePrice` will return the manipulated V3 quote and never consult the more defensive V4 path; remaining work is to quantify live-pool manipulation cost and confirm the allocator's trust assumptions.

## Rejected / Notes

- `kickAuction` compares all token balances to `minAmountToSell[REWARDS_TOKEN]` (`src/GroveCompounder.sol:169`) even when `_token != REWARDS_TOKEN` (`src/GroveCompounder.sol:165-167`). This is a real asymmetry, but I did not escalate it because the primary reward path only kicks `REWARDS_TOKEN`, the function is keeper-only, and the observed impact is mostly poor recovery behavior for incidental non-reward token balances.
- `useAuction` defaults to true while `auction` defaults to zero (`src/GroveCompounder.sol:19`, `22`), so rewards above threshold can make reports revert until management configures an auction. The setup flow configures the auction before opening deposits, and this is a bootstrap/configuration hazard rather than an untrusted-user exploit.
- `aprAfterDebtChange` subtracts negative `_delta` without clamping (`src/periphery/GroveCompounderAprOracle.sol:121-122`) while positive `_delta` cannot underflow (`src/periphery/GroveCompounderAprOracle.sol:123-124`). Passing a withdrawal larger than global staking supply reverts, but I did not find a source-backed path where valid callers should request more than total staked assets.
- `setUniV4Pool` can reduce V4 pricing to a single configured pool (`src/periphery/GroveCompounderAprOracle.sol:147-151`), making the median check self-referential. This is management-only configuration risk and is not reported as an exploit by itself.
