[Feynman: GroveCompounder] This strategy takes USDS from depositors, puts the USDS into the external Sky staking contract, earns GROVE rewards, and turns those rewards back into more USDS either by sending them to an auction or by swapping them through Uniswap and the PSM wrapper.

[Feynman: _harvestAndReport] A report first claims GROVE rewards. If auctions are enabled, the rewards are moved to the auction and the strategy reports only USDS that is staked or sitting in the strategy. If the direct swap path is enabled, it sells GROVE for USDC, converts all USDC to USDS, stakes any loose USDS above dust, and reports staked plus loose USDS.

[Socratic: src/GroveCompounder.sol:117 -- why?] Why does the report count only stake plus idle USDS after rewards are sent to the auction? The implicit belief is that auctioned GROVE has no reportable value until USDS returns, which creates an accounting gap between auction settlement and the next report.

[Inversion: _harvestAndReport] 1. Let old users earn GROVE, kick it to the auction, then buy the auction so USDS sits idle before a report. 2. Deposit a large amount after the USDS arrives but before accounting notices it. 3. Let the next report distribute the old reward proceeds over the enlarged share supply.

[Feynman: TokenizedStrategy._deposit] A deposit takes assets from the caller, sends every loose asset balance in the strategy into the strategy's yield source, records only the caller's deposit amount as new managed assets, then mints shares to the receiver.

[Socratic: lib/tokenized-strategy/src/TokenizedStrategy.sol:1110 -- why?] Why does deposit deploy the whole loose balance but add only `assets` to accounting? It assumes loose balance has already been accounted for, which is false after auction proceeds arrive before the next report.

[Feynman: Auction.take] A buyer takes the token being sold, optionally runs a callback, and then pays the wanted token directly to the receiver configured on the auction.

[Inversion: deposit] 1. Put unreported USDS into the strategy by taking the reward auction. 2. Deposit before `report()` can turn that idle USDS into locked profit. 3. Use a larger deposit than incumbents to take most of the next profit unlock.

[Feynman: GroveCompounderAprOracle] This oracle estimates the staking APR by reading the staking contract's total staked amount and reward speed, then multiplying the yearly reward amount by a current GROVE price from Uniswap pools.

[Feynman: aprAfterDebtChange] The APR function reads global staking totals, adjusts the total by the requested debt change, gets a live GROVE price, computes annual reward value divided by adjusted staked assets, and rejects outputs above 50% APR.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:111 -- why?] Why is global staking `totalSupply()` used as the denominator? The oracle assumes the whole external staking pool is the relevant capacity, so any same-block external stake or withdrawal can change the APR seen by downstream consumers.

[Feynman: _grovePrice] This price helper first tries to quote selling one GROVE through a current Uniswap V3 pool if the pool has enough reported liquidity and USDC balance. If that fails, it picks a Uniswap V4 pool price from current pool state.

[Inversion: _grovePrice] 1. Move the current V3 pool price before a caller reads the oracle, then reverse after. 2. Make V3 unusable so the oracle falls back to V4. 3. Manipulate the only usable V4 pool so its own price becomes the median and passes the deviation check.

[Feynman: _selectedV4Pool] This function asks each configured V4 pool for liquidity and current price, keeps only nonzero prices above the liquidity floor, computes the median price, and returns the highest-liquidity quote within 10% of that median.

[Inversion: _selectedV4Pool] 1. Leave only one configured pool with enough liquidity so the median check compares the pool to itself. 2. Manipulate two similarly priced pools so both sit near the median. 3. Put the most liquidity in the manipulated in-range pool so it is selected over cleaner quotes.

FINDING | contract: GroveCompounder | function: _harvestAndReport | bug_class: stale-accounting-profit-dilution | group_key: GroveCompounder | _harvestAndReport | stale-accounting-profit-dilution
path: keeper -> `report()` -> `_harvestAndReport()` transfers GROVE rewards to the auction and reports only `balanceOfStake() + balanceOfAsset()` -> auction taker pays USDS to the strategy -> attacker deposits while deposits are open or the attacker is allowed, before the next report, at stale share pricing -> next report locks the auction proceeds across the enlarged supply -> attacker withdraws a share of rewards earned before entry
evidence: `src/GroveCompounder.sol:107-117` kicks rewards to the auction and excludes auction-held reward value from `_totalAssets`; `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:600-604` sends auction payment directly to the strategy receiver; `src/GroveCompounder.sol:125-132` delegates deposit availability to the inherited open/allowlist gate when staking is not paused; `lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol:189-191` permits deposits for open or allowed receivers; `lib/tokenized-strategy/src/BaseStrategy.sol:237-244` defaults live asset estimates to `lastTotalAssets`; `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540` accrues before minting deposit shares; `lib/tokenized-strategy/src/TokenizedStrategy.sol:1105-1114` deploys the full loose asset balance but increments `lastTotalAssets` only by the depositor's `assets`; `src/GroveCompounder.sol:76-78` stakes the full loose balance.
proof: Start with incumbents holding 1,000,000 shares against `lastTotalAssets = 1,000,000 USDS`, with deposits open or the attacker allowlisted. A report kicks earned GROVE to the auction and still reports 1,000,000 USDS because `_totalAssets` excludes the auctioned GROVE. The auction later pays 10,000 USDS to the strategy. Before the next report, an attacker deposits 1,000,000 USDS. Because `_strategyTotalAssets()` still returns `lastTotalAssets`, the attacker mints 1,000,000 shares at the old 1:1 price. `_deposit()` then stakes the full 1,010,000 loose USDS but adds only the attacker's 1,000,000 USDS to `lastTotalAssets`, making the next report see `newTotalAssets = 2,010,000` and `oldTotalAssets = 2,000,000`. The 10,000 USDS of old reward profit is then locked across 2,000,000 user shares, so the attacker owns 50% of the unlock and captures 5,000 USDS of rewards earned before their deposit. With a 9,000,000 USDS deposit against the same incumbents, the attacker captures 9,000 of the 10,000 USDS reward profit, less borrowing/opportunity cost through the profit unlock window.
description: Auction proceeds can sit in the strategy as unreported idle USDS, and deposits price from stale accounting, letting just-in-time capital dilute incumbent users' earned rewards.
fix: Override `_strategyTotalAssets()` to return a read-only live estimate such as `balanceOfStake() + balanceOfAsset()` so deposits accrue returned auction proceeds before minting, or otherwise close/limit deposits while auction proceeds are unreported.

LEAD | contract: GroveCompounder | function: _harvestAndReport | bug_class: zero-slippage-reward-swap | group_key: GroveCompounder | _harvestAndReport | zero-slippage-reward-swap
code_smells: If `useAuction` is false and rewards exceed the threshold, the strategy calls `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` after only checking `PSM_WRAPPER.tin() == 0` (`src/GroveCompounder.sol:96-105`). `UniswapV3Swapper._swapFrom()` passes that zero directly as `amountOutMinimum` and uses the current block timestamp as the deadline (`lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:67-86`).
description: A liquid UniV3 fallback route can be sandwiched so GROVE rewards sell for near-zero USDC, but this remains a lead because the audited default mode is auction and exploitability depends on management enabling the direct-swap mode with a usable pool.

LEAD | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: spot-price-apr-manipulation | group_key: GroveCompounderAprOracle | _grovePrice | spot-price-apr-manipulation
code_smells: `aprAfterDebtChange()` uses the staking contract's current `totalSupply()` and `rewardRate()` (`src/periphery/GroveCompounderAprOracle.sol:109-132`). `_grovePrice()` trusts a current Uniswap V3 one-GROVE quote when the pool passes minimal liquidity and USDC-balance checks (`src/periphery/GroveCompounderAprOracle.sol:211-244`), otherwise `_selectedV4Pool()` uses current V4 `slot0` prices and a median filter that is tautological when only one quote is usable (`src/periphery/GroveCompounderAprOracle.sol:255-305`).
description: A downstream allocator using this oracle can potentially be steered by same-block price or staking-denominator manipulation; the missing piece for a finding is an in-scope consumer that commits funds based on this view.

Rejected / Notes

- `kickAuction(address)` accepts non-reward tokens, but it is keeper/management gated, rejects the asset, and the external auction must have the token enabled before `Auction.kick()` can succeed (`src/GroveCompounder.sol:158-180`; `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:510-516`).
- The PSM fee check prevents the direct swap path from silently paying a USDC-to-USDS fee, but if `useAuction == false` and `tin() != 0`, reports can revert by configuration rather than by an untrusted caller (`src/GroveCompounder.sol:96-105`).
- Negative `_delta` values larger than staking `totalSupply()` revert by checked subtraction in the APR oracle (`src/periphery/GroveCompounderAprOracle.sol:120-128`), but the caller controls that impossible query and no profitable victim path is present in scope.
