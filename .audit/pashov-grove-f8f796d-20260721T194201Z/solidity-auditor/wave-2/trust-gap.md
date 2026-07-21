[Feynman: GroveCompounder]
This strategy takes USDS from depositors, stakes it in the Sky staking contract, claims GROVE rewards, and turns those rewards back into USDS either by sending them to an auction or by selling them through Uniswap and the PSM. Its accounting only counts USDS already held or staked, not unsold GROVE rewards.

[Feynman: GroveCompounder._harvestAndReport]
This report step claims any GROVE, decides whether to sell it directly or send it to an auction, stakes any loose USDS above dust, and reports staked USDS plus loose USDS as the strategy's assets. The fuzzy part is the reward sale: the direct swap path accepts any USDC amount, while the auction path depends on a separate mutable auction's pricing.

[Socratic: src/GroveCompounder.sol:100 - why?]
Why is the minimum output zero when the caller allowed to trigger the sale is a keeper? The implicit belief is that a permissioned keeper/timing path is enough protection for a spot-market sale, but the keeper can also be the actor choosing the adverse execution moment.

[Inversion: GroveCompounder._harvestAndReport]
1. Set `useAuction` false, wait until rewards exceed `minAmountToSell`, then have the keeper bundle a pool-moving swap before `report()`.
2. Keep `useAuction` true, let rewards accumulate, then kick a larger auction lot whose per-token starting price is lower because the auction divides a fixed lot price by the kicked balance.
3. Call `report()` while an auction is active and newly claimable rewards exceed the threshold, forcing the auction kick branch to revert until the active auction becomes inactive.

[Feynman: GroveCompounder.kickAuction]
This function lets a keeper move sellable tokens from the strategy into the configured auction and start the sale. For GROVE it first claims rewards; for any other token it uses the strategy's token balance directly.

[Socratic: src/GroveCompounder.sol:169 - why?]
Why does every token use the GROVE minimum amount instead of that token's own threshold? The code assumes only GROVE will matter in practice even though the function accepts any non-asset token.

[Inversion: GroveCompounder.kickAuction]
1. Pass the reward token after rewards accrue and become the first actor to choose the sale boundary.
2. Pass a non-reward token that was accidentally sent to the strategy and is enabled on the auction.
3. Kick immediately after a prior auction expires but before other actors can force a better-timed sale.

[Feynman: GroveCompounder._kickAuction]
This helper refuses to sell USDS itself, checks that an auction address exists, transfers the full chosen token balance to the auction, and asks the auction to start selling it. It does not re-check the auction's current receiver after the transfer beyond what `setAuction` checked earlier.

[Feynman: GroveCompounder.setAuction]
This setter lets management choose the auction contract if, at that moment, the auction says it will send sale proceeds back to this strategy and wants USDS. It does not pin who controls the auction after selection.

[Socratic: src/GroveCompounder.sol:211 - why?]
Why is checking the current receiver enough for a contract whose receiver can later be changed? The hidden assumption is that the auction's future governance is trusted or identical to strategy management.

[Inversion: GroveCompounder.setAuction]
1. Set an auction whose current receiver is the strategy, then have auction governance change the receiver before the next take.
2. Set an auction with correct `want` and `receiver` but stale or inappropriate pricing parameters.
3. Transfer auction governance after the strategy has accepted the auction.

[Feynman: GroveCompounderAprOracle]
This oracle estimates the USDS value of GROVE rewards per year divided by the amount of USDS staked in the external staking contract. It prices GROVE through a usable Uniswap V3 pool first, then through configured Uniswap V4 pools if V3 is not usable.

[Feynman: GroveCompounderAprOracle.aprAfterDebtChange]
This function reads global staking supply and global reward rate, gets a GROVE price, adjusts the global supply by a caller-supplied debt change, and returns the implied yearly reward rate. The fuzzy part is that the function accepts a strategy address but never uses it.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:109 - why?]
Why does the interface ask for a strategy if the result is the same for every strategy? The implicit belief is that this oracle will only ever be registered for strategies sharing the exact same staking pool and asset assumptions.

[Inversion: GroveCompounderAprOracle.aprAfterDebtChange]
1. Register or query this oracle for a different strategy and still receive a Grove staking APR.
2. Pass a negative delta close to global staking supply to inflate APR or force a revert.
3. Use a positive delta from one vault allocator to dilute the displayed APR for all strategies sharing the same global denominator.

[Feynman: GroveCompounderAprOracle._grovePrice]
This function tries to estimate how many USDS one GROVE is worth. It first simulates selling one GROVE through the configured Uniswap V3 fee tier, and if that fails or has unusable liquidity, it falls back to the selected Uniswap V4 pool price.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:222 - why?]
Why does the quote object contain a zero minimum output? Because this is only a simulation, not an executed sale; the real risk is reliance on current spot state rather than a time-averaged or manipulation-cost-aware price.

[Inversion: GroveCompounderAprOracle._grovePrice]
1. Move the V3 pool price for one block while keeping liquidity and USDC balance above the hard thresholds.
2. Make the V3 simulation fail so pricing falls through to V4.
3. Keep a V4 candidate within the median deviation band while making it the highest-liquidity selected pool.

[Feynman: GroveCompounderAprOracle._selectedV4Pool]
This function asks each configured V4 pool for liquidity and price, discards empty or unusable answers, computes the median price, and chooses the most liquid pool close enough to that median.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:294 - why?]
Why select the most liquid pool after only a median-deviation check? The assumption is that configured pools are already trusted enough that liquidity is a good tiebreaker, not an attacker-controlled selection lever.

## Results

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: keeper-sandwich-zero-min-out | group_key: GroveCompounder | _harvestAndReport | keeper-sandwich-zero-min-out
seam: access x economics
actor: keeper or management-as-keeper when management has enabled UniV3 mode
path: management sets `useAuction` false -> keeper calls `report()` -> `_harvestAndReport()` claims GROVE and calls `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` -> Uniswap V3 executes with `amountOutMinimum = 0` -> PSM converts only the bad USDC output to USDS -> shareholders receive less harvested profit while the keeper's surrounding pool trades capture the difference
proof: `GroveCompounder._harvestAndReport()` enters the direct swap branch when `!useAuction`, `toSwap > minRewardAmountToSell`, and `PSM_WRAPPER.tin() == 0` (`src/GroveCompounder.sol:96-105`). The strategy passes literal `0` as the minimum output at `src/GroveCompounder.sol:100`. `UniswapV3Swapper._swapFrom()` forwards that value as `amountOutMinimum` for the router call (`lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:75-86`). A concrete trace is: default reward threshold is `5_000e18` GROVE (`src/GroveCompounder.sol:52`); with `toSwap = 10_000e18`, a keeper bundles a GROVE->USDC sale before `report()`, pushes the pool price down, lets the strategy sell with min output 0, then buys back after the strategy trade. Any positive USDC output is accepted and sold through the PSM (`src/GroveCompounder.sol:102-105`), so the strategy records only that reduced USDS while the keeper captures the adverse execution value. Because rewards were not included in the pre-report USDS asset total, this is lost upside rather than a reported principal loss.
description: The permissioned report path becomes an extractive market-timing right in UniV3 mode because the authorized keeper can trigger a reward sale with no slippage floor.
fix: Keep auction mode as the only keeper-triggered sale path, or require a trusted min-out/TWAP bound for `_swapFrom()` and revert if the realized USDS is below that bound.

LEAD | contract: GroveCompounder | function: kickAuction/_harvestAndReport | bug_class: keeper-timed-fixed-lot-auction | group_key: GroveCompounder | kickAuction/_harvestAndReport | keeper-timed-fixed-lot-auction
seam: access x economics
actor: keeper, potentially also acting as auction taker
code_smells: The strategy lets only keepers start reward auctions through `kickAuction()` (`src/GroveCompounder.sol:158-170`) or through `report()` (`src/GroveCompounder.sol:84-109`), and `_kickAuction()` transfers the full selected balance before calling `Auction.kick()` (`src/GroveCompounder.sol:174-179`). The auction then records the current full token balance as `initialAvailable` (`lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:513-520`) and computes initial price as `startingPrice / initialAvailable` (`lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:312-319`), while the factory default is a fixed `1_000_000e18` lot price (`lib/tokenized-strategy-periphery/src/Auctions/AuctionFactory.sol:12-13`).
description: A keeper can choose the auction batch boundary, and because a fixed total starting price is divided by the kicked reward balance, delaying the kick can lower per-token auction price for all holders' accrued rewards; exploitability depends on live GROVE price, reward accrual, and configured auction price/minimums.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: strategy-agnostic-apr-delta | group_key: GroveCompounderAprOracle | aprAfterDebtChange | strategy-agnostic-apr-delta
seam: economics x asymmetry
actor: APR oracle registry/consumer or allocator using `_strategy` and `_delta`
code_smells: The public interface and comment accept `_strategy` as "the strategy to get the apr for" (`src/periphery/GroveCompounderAprOracle.sol:104-109`), but the function never reads it; instead it always uses global staking `totalSupply()` and `rewardRate()` (`src/periphery/GroveCompounderAprOracle.sol:110-118`) and applies the caller-supplied `_delta` directly to that global denominator (`src/periphery/GroveCompounderAprOracle.sol:120-132`). The generic registry passes a per-strategy oracle call through by strategy address (`lib/tokenized-strategy-periphery/src/AprOracle/AprOracle.sol:57-74`).
description: If this oracle is registered or consumed outside the exact Grove USDS staking strategy assumptions, callers can receive a Grove-global APR for the wrong strategy or make a strategy-local debt change affect the global denominator; exploitability depends on the allocator/registry constraining this oracle to the intended strategy and clamping negative deltas to feasible strategy debt.

LEAD | contract: GroveCompounder | function: setAuction/_kickAuction | bug_class: mutable-auction-receiver-trust | group_key: GroveCompounder | setAuction/_kickAuction | mutable-auction-receiver-trust
seam: access x asymmetry x economics
actor: auction governance if it is not the same trusted authority as strategy management
code_smells: `setAuction()` validates only the auction's current `receiver()` and `want()` (`src/GroveCompounder.sol:209-216`). Later, `_kickAuction()` blindly transfers rewards to that auction and starts it (`src/GroveCompounder.sol:174-179`). The auction contract allows governance to change `receiver` when no auction is active (`lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:421-428`), and auction settlement pulls payment to the current receiver (`lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:600-604`).
description: A previously accepted auction can redirect future sale proceeds away from the strategy if its governance can change receiver after the strategy's one-time validation; this remains a lead unless deployment evidence shows auction governance is external or can drift independently of strategy management.

## Rejected / Notes

- `claimRewards()` is management-only but only calls the same staking reward claim used by reports (`src/GroveCompounder.sol:145-150`); I did not find a value redirect or user-class asymmetry there.
- `setReferral()` changes the referral code used on future staking calls (`src/GroveCompounder.sol:76-78`, `src/GroveCompounder.sol:234-235`); no in-scope asset flow depends on the referral recipient.
- The arbitrary-token branch of `kickAuction()` is unusual because it accepts non-reward tokens and checks the GROVE threshold (`src/GroveCompounder.sol:162-170`), but `_kickAuction()` rejects the asset (`src/GroveCompounder.sol:174-179`) and a non-enabled auction token reverts in `Auction.kick()` (`lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:507-516`). Without a strategy-owned non-asset balance and enabled auction, this is not a reportable trust-gap issue.
