# Boundary lane - Grove compounder

Primary scope reviewed:
- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

No validated FINDING blocks from the boundary lane. I found three plausible LEADs that depend on integration/operational conditions outside the two primary contracts.

## Mental tool markers

[Feynman: GroveCompounder] This contract accepts USDS from the strategy wrapper, puts that USDS into the Sky staking contract, collects GROVE rewards, and either sends those rewards to an auction or sells them through Uniswap and the PSM before restaking any loose USDS.

[Feynman: GroveCompounder.constructor] The constructor checks that the hard-coded staking and PSM wrapper match the expected USDS asset, remembers the reward token, grants long-lived approvals to staking and the PSM wrapper, and configures the reward-sale path.

[Socratic: src/GroveCompounder.sol:38 - why?] Why is `PSM_WRAPPER.usds()` trusted as the constructor asset before the later equality check; because the wrapper is hard-coded and expected immutable, not caller supplied.

[Feynman: balanceOfAsset] This reports how much unstaked USDS the strategy is holding directly.

[Feynman: balanceOfStake] This reports how much USDS the staking contract says belongs to the strategy.

[Feynman: balanceOfRewards] This reports how much GROVE reward token is currently sitting in the strategy.

[Feynman: claimableRewards] This asks the staking contract how much GROVE the strategy could claim now.

[Feynman: _deployFunds] This takes loose USDS and places it into the staking contract using the current referral code.

[Inversion: _deployFunds] Try deposit while staking is paused; try deposit zero; try deposit after referral was changed to an arbitrary uint16.

[Feynman: _freeFunds] This asks the staking contract to return a requested amount of USDS to the strategy.

[Inversion: _freeFunds] Try withdrawing more than the strategy's stake; try withdrawing while staking is paused; try withdrawing when the staking contract returns less than requested.

[Feynman: _harvestAndReport] This claims rewards, sells or auctions enough GROVE if above the configured threshold, restakes loose USDS above dust if the strategy is live, and tells TokenizedStrategy how much USDS is staked plus idle.

[Socratic: src/GroveCompounder.sol:98 - why?] Why is the PSM fee checked only on the Uniswap path; because auctions exchange rewards outside the PSM, while the swap path immediately sends USDC through the PSM and assumes free 1:1 conversion.

[Socratic: src/GroveCompounder.sol:107 - why?] Why does the report path kick an auction without checking whether one is already active; because it assumes a reward balance above threshold means the auction is immediately kickable.

[Inversion: _harvestAndReport] Run report while a prior reward auction is active; manipulate the UniV3 spot price before a keeper report when `useAuction=false`; make the PSM fee nonzero just before the swap path.

[Feynman: _emergencyWithdraw] This frees up to the lesser of the requested amount and the strategy's staked balance.

[Feynman: availableDepositLimit] This closes deposits when staking says it is paused, otherwise it applies the inherited open/allow-list gate.

[Feynman: claimRewards] This lets management claim GROVE rewards without selling them.

[Feynman: _claimRewards] This asks the staking contract to send any earned GROVE to the strategy.

[Feynman: kickAuction] This lets a keeper move a token balance held by the strategy into the configured auction and start selling it, claiming GROVE first if the token is the reward token.

[Socratic: src/GroveCompounder.sol:169 - why?] Why is `minAmountToSell[REWARDS_TOKEN]` used even when `_token` is not the reward token; because the function is primarily intended for GROVE, and arbitrary-token support is only incidental.

[Inversion: kickAuction] Pass the strategy asset as `_token`; pass an unenabled token with a donated balance; pass the reward token while the auction is still active.

[Feynman: _kickAuction] This blocks auctioning USDS, sends the token balance to the auction contract, and asks the auction to start.

[Socratic: src/GroveCompounder.sol:178 - why?] Why transfer before calling `kick`; because the auction computes its available amount from its own token balance, so the funds must already be there before `kick`.

[Feynman: setMinAmountToSell] This lets management change the GROVE amount that must accumulate before selling.

[Feynman: setUniV3Fees] This lets management choose the Uniswap V3 fee tier used for the GROVE/USDC swap route.

[Feynman: setAuction] This lets management choose or clear the auction, but only accepts a nonzero auction whose receiver is this strategy and whose wanted token is USDS.

[Inversion: setAuction] Try an EOA as auction; try an auction with a different receiver; try clearing the auction while `useAuction` is still true.

[Feynman: setUseAuction] This switches reward selling between the auction path and the UniV3/PSM path.

[Feynman: setReferral] This lets management change the referral code sent to the staking contract on future stakes.

[Feynman: GroveCompounderAprOracle] This contract estimates the annualized return for USDS staked into Sky rewards by reading the staking reward rate, pricing one GROVE in USDS, applying a caller-supplied debt change, and rejecting APRs above a configured sanity cap.

[Feynman: GroveCompounderAprOracle.constructor] The constructor assigns management to the deployer and seeds four hard-coded UniV4 pool ids as fallback price sources.

[Feynman: aprAfterDebtChange] This reads total staked USDS and GROVE emitted per second, returns zero if the reward period is already over, gets a GROVE price, adjusts the staked amount by the requested debt change, and returns annual reward value divided by adjusted staked assets.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:109 - why?] Why is `_strategy` ignored; because this oracle is hard-coded to the one Sky staking market rather than measuring a per-strategy position.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:114 - why?] Why is the period-finished check strict `>` instead of `>=`; it assumes the exact finish timestamp still belongs to the reward period.

[Inversion: aprAfterDebtChange] Use a negative delta equal to total supply; use a negative delta greater than total supply; call exactly at `periodFinish` with a nonzero stale `rewardRate`.

[Feynman: setManagement] This lets the current manager transfer oracle configuration rights to a nonzero address.

[Feynman: setUniV3Fee] This lets management choose a UniV3 fee tier, accepting it if the Uniswap factory has a pool for GROVE/USDC at that fee.

[Feynman: setUniV4Pool] This replaces all fallback V4 price sources with one nonzero pool id and its token-order flag.

[Feynman: setUniV4Pools] This replaces all fallback V4 price sources with a nonempty, duplicate-free list of pool ids and token-order flags.

[Feynman: addUniV4Pool] This appends one new nonzero V4 pool id if it is not already configured.

[Feynman: removeUniV4Pool] This removes one configured V4 pool by swapping in the last entry, while refusing to remove the final pool.

[Feynman: uniV3Pool] This reports the current GROVE/USDC V3 pool address for the configured fee tier.

[Feynman: uniV4PoolCount] This reports how many V4 fallback pools are configured.

[Feynman: uniV4Pool] This reports the pool id and token-order flag stored at an index.

[Feynman: groveUsdcV4PoolId] This reports the first configured V4 pool id for legacy callers.

[Feynman: v4GroveIsToken0] This reports the token-order flag of the first configured V4 pool for legacy callers.

[Feynman: bestUniV4Pool] This reports the selected V4 fallback pool without its price.

[Feynman: selectedUniV4Pool] This reports the selected V4 fallback pool with its computed price.

[Feynman: _grovePrice] This prefers the UniV3 quote if the V3 pool passes basic liquidity checks; otherwise it asks the configured V4 pools for a fallback price and reverts if none can provide one.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:212 - why?] Why does a usable V3 pool bypass the V4 median checks; because V3 is treated as the primary source once its liquidity and USDC balance are above minimums.

[Inversion: _grovePrice] Move the V3 spot price but keep liquidity above threshold; make the V3 simulator revert so fallback is used; configure V4 pools with divergent prices and unequal liquidity.

[Feynman: _v3PoolHasUsableLiquidity] This checks that a V3 pool exists, has enough active liquidity, and holds at least 1,000 USDC.

[Feynman: _v4GrovePrice] This converts a V4 square-root price into a 1e18-scaled USDS price for one GROVE, depending on whether GROVE is token0 or token1.

[Feynman: _selectedV4Pool] This gathers usable V4 pool quotes, computes their median price, and selects the most liquid quote close enough to that median.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:267 - why?] Why is V4 usability only a liquidity threshold; because the pool id is assumed to already identify a correct GROVE/USDC pool.

[Inversion: _selectedV4Pool] One high-liquidity outlier far from the median; two coordinated pools near a shifted median; one pool reverting from StateView while other pools remain usable.

[Feynman: _medianPrice] This copies quote prices into a separate list, sorts them, and returns the middle price or the average of the two middle prices.

[Feynman: _withinV4PriceDeviation] This accepts a price if it is within 10 percent of a reference price.

[Feynman: _setUniV4Pools] This validates and stores a replacement list of V4 pool ids and direction flags.

[Feynman: _hasUniV4Pool] This checks whether a pool id is already in the configured list.

[Feynman: _uniV3Pool] This finds the active V3 pool address using the stored fee.

[Feynman: _uniV3PoolForFee] This asks the Uniswap V3 factory for the GROVE/USDC pool at a specified fee tier.

[Feynman: _quoteToken1ForToken0] This calculates how much token1 one unit amount of token0 is worth from a square-root price.

[Feynman: _quoteToken0ForToken1] This calculates how much token0 one unit amount of token1 is worth from a square-root price.

## Boundary enumeration

GroveCompounder external boundaries reviewed:
- Hard-coded external contracts: `STAKING`, `PSM_WRAPPER`, `auction`, Uniswap V3 router inherited from `UniswapV3Swapper`.
- Constructor external reads/approvals: `PSM_WRAPPER.usds()`, `STAKING.paused()`, `STAKING.stakingToken()`, `STAKING.rewardsToken()`, `asset.forceApprove(STAKING)`, `PSM_WRAPPER.gem()`, `ERC20(usdc).forceApprove(PSM_WRAPPER)`.
- Staking hooks: `STAKING.stake`, `STAKING.withdraw`, `STAKING.getReward`, `STAKING.balanceOf`, `STAKING.earned`, `STAKING.paused`.
- Reward-sale calls: `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)`, `PSM_WRAPPER.tin()`, `PSM_WRAPPER.sellGem`, `ERC20(token).safeTransfer(auction)`, `Auction(auction).kick(token)`.
- Caller-supplied address boundary: `kickAuction(address _token)`.
- Sentinel branch: `setAuction(address(0))` versus nonzero auction validation.
- No payable functions and no `bytes`/`abi.decode` inputs in primary contract.

GroveCompounderAprOracle external boundaries reviewed:
- Staking reads: `totalSupply`, `rewardRate`, `periodFinish`.
- Uniswap V3 reads/simulation: factory `getPool`, pool `liquidity`, USDC `balanceOf(pool)`, simulator quote using current pool state.
- Uniswap V4 StateView reads: `getLiquidity(poolId)`, `getSlot0(poolId)`.
- Caller-controlled numerical boundary: signed `_delta`.
- Management-controlled pool boundaries: UniV3 fee tier, V4 pool ids, V4 token-order flags.
- Sentinel/empty boundaries: V3 pool address zero, V4 quote count zero, V4 pool id zero.
- No payable functions and no `bytes`/`abi.decode` inputs in primary contract.

## Leads

LEAD | contract: GroveCompounder | function: _harvestAndReport | bug_class: auction-active-report-dos | group_key: GroveCompounder | _harvestAndReport | auction-active-report-dos
boundary: `GroveCompounder._kickAuction(REWARDS_TOKEN, toSwap)` crosses into `Auction(_auction).kick(_token)` during `report`.
assumption: Once claimed GROVE exceeds `minAmountToSell[REWARDS_TOKEN]`, the configured auction is ready to accept a new kick.
actual: `Auction._kick` rejects a kick while the previous auction is still active with `require(!isActive(_from), "too soon")`.
code_smells: `src/GroveCompounder.sol:107-109` unconditionally calls `_kickAuction` when `useAuction` is true and rewards are above threshold; `src/GroveCompounder.sol:174-180` transfers the token to the auction and calls `Auction.kick`; `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:507-520` rejects active auctions and otherwise records the new `kicked` timestamp and `initialAvailable`.
description: A second report with rewards above threshold during an already-active reward auction reverts instead of skipping or accumulating rewards for the next kick.
proof: Sequence: first report in auction mode with `toSwap > min` reaches `_kickAuction`, after which `Auction._kick` stores `auctions[REWARDS_TOKEN].kicked = uint64(block.timestamp)` and `initialAvailable`; before that auction becomes inactive, another report that claims enough new GROVE again reaches `_kickAuction`, but `Auction._kick` hits `require(!isActive(_from), "too soon")` and reverts the whole report.
remaining_gap: This is not a validated finding because the caller is keeper/management gated and the denial window depends on reward accrual versus the configured threshold and auction duration; no unpermissioned trigger was established from primary scope alone.
fix: Before kicking, check auction kickability/active status and leave rewards in the strategy when the auction is still live, or route them to an existing auction-compatible accumulation flow.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: spot-price-oracle-boundary | group_key: GroveCompounderAprOracle | _grovePrice | spot-price-oracle-boundary
boundary: The V3 price path consumes the current GROVE/USDC pool state through `UniswapV3SwapSimulator.simulateExactInputSingle`.
assumption: A V3 pool with at least `MIN_REWARD_POOL_LIQUIDITY` and `MIN_REWARD_POOL_USDC_BALANCE` returns a reliable GROVE price.
actual: The simulator prices against current pool state, so an in-block trade can move `slot0`/liquidity traversal while still leaving liquidity and USDC balance above the two thresholds.
code_smells: `src/periphery/GroveCompounderAprOracle.sol:211-229` returns the V3 quote immediately if `_v3PoolHasUsableLiquidity()` passes; `src/periphery/GroveCompounderAprOracle.sol:239-245` only checks pool existence, active liquidity, and USDC balance; `src/libraries/UniswapV3SwapSimulatorCore.sol:69-86` reads the pool's current `slot0`, liquidity, fee, and tick spacing for the quote.
description: The primary APR price source is a manipulable spot quote with no TWAP or cross-source deviation check before V4 fallback is skipped.
proof: If the V3 pool passes the liquidity/balance checks, `_grovePrice` never consults `_selectedV4Pool`; it returns `output * 1e12` from the current-state simulator. A trade placed before an allocator's oracle call can alter the simulated output for `amountIn: 1e18` GROVE while the code has no primary-scope guard that compares the result to V4 median price or time-weighted price.
remaining_gap: This remains a lead because the two scoped contracts only expose a view APR; the downstream debt allocator or keeper decision path that would turn the manipulated APR into asset movement is outside the primary scope.
fix: Use a TWAP, compare V3 against V4 median/deviation bounds even when V3 is liquid, or require off-chain/allocator callers to use manipulation-resistant sampling.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: period-finish-boundary | group_key: GroveCompounderAprOracle | aprAfterDebtChange | period-finish-boundary
boundary: The oracle consumes `IStaking(STAKING).periodFinish()` and `rewardRate()` to decide whether rewards are still active.
assumption: `block.timestamp > periodFinish` is the only finished-reward state that should return zero APR.
actual: At `block.timestamp == periodFinish`, the strict comparison is false, so a stale nonzero `rewardRate` is annualized even though the reward period has reached its endpoint.
code_smells: `src/periphery/GroveCompounderAprOracle.sol:111-115` reads total supply and reward rate, then returns zero only when `block.timestamp > periodFinish`; `src/periphery/GroveCompounderAprOracle.sol:130-132` annualizes `rewardRate` when the strict check does not return.
description: The exact reward-period boundary can report a nonzero APR for one timestamp where a `>= periodFinish` check would report zero.
proof: With `periodFinish == block.timestamp`, `rewardRate > 0`, `assets > 0`, and a positive `_grovePrice()`, line 114 does not return zero and line 131 computes `(rewardRate * SECONDS_PER_YEAR * price) / assets`; with the same state one second later, line 114 returns zero.
remaining_gap: This is not a finding because exploitability depends on an allocator making a decision exactly at the staking period boundary and on the staking contract's intended semantics at equality.
fix: Use `block.timestamp >= periodFinish` if the oracle is intended to report forward-looking APR only while future rewards remain.

## Rejected / Notes

- `kickAuction(address _token)` accepts arbitrary token addresses, but `_kickAuction` blocks the strategy asset (`src/GroveCompounder.sol:175`) and a failed `Auction.kick` reverts the preceding transfer atomically. I did not find a source-backed theft path for donated non-reward tokens.
- `PSM_WRAPPER.sellGem` return value is ignored on the UniV3 path, but `_harvestAndReport` measures actual USDS with `balanceOfAsset()` after the call (`src/GroveCompounder.sol:111-117`). A bad PSM conversion reduces reported assets instead of silently inflating them; the wrapper address is hard-coded.
- Negative `_delta` greater than `IStaking.totalSupply()` reverts by arithmetic underflow before the explicit zero-assets guard (`src/periphery/GroveCompounderAprOracle.sol:121-128`). I treated this as caller-domain rejection rather than a lead because a debt reduction larger than total staked assets is not a feasible strategy debt change from the scoped code alone.
- V4 pool ids and `groveIsToken0` flags are management-controlled. Misconfiguration can make the oracle wrong or unavailable, but I did not report admin-only misconfiguration as a vulnerability.
- No payable/native-token branch or `bytes` decoding surface exists in the two primary contracts.
