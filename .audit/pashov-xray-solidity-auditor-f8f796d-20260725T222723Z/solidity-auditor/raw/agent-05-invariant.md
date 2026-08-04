# Agent 05 — Invariant lane raw output

## Mandatory mental-tool trace

[Feynman: GroveCompounder]
This strategy accepts USDS, puts it into the Sky staking pool, collects GROVE rewards, turns those rewards back into USDS, and counts only staked plus loose USDS as user assets. Reward sales either send GROVE to an auction for later settlement or sell it immediately through a GROVE/USDC market and then the PSM.

[Feynman: GroveCompounder.constructor]
Deployment pins the staking and PSM dependencies, verifies they use the same USDS, approves them to move the relevant tokens, and chooses USDC as the sale intermediary. It starts in auction mode even though no auction has been selected yet.

[Feynman: GroveCompounder.balanceOfAsset]
This reports how much loose USDS the strategy owns right now.

[Feynman: GroveCompounder.balanceOfStake]
This reports how much USDS the staking system attributes to the strategy.

[Feynman: GroveCompounder.balanceOfRewards]
This reports how much GROVE has already reached the strategy wallet.

[Feynman: GroveCompounder.claimableRewards]
This reports how much additional GROVE the staking system says the strategy can collect.

[Feynman: GroveCompounder._deployFunds]
This moves a requested amount of USDS from the strategy into Sky staking and attaches the current referral code.

[Feynman: GroveCompounder._freeFunds]
This asks Sky staking to return an exact requested amount of USDS to the strategy.

[Feynman: GroveCompounder._harvestAndReport]
This collects GROVE, conditionally starts or executes a sale, puts loose USDS back into staking while active, and finally tells the share-accounting runtime how much USDS is staked plus loose. The fuzzy point is timing: valid USDS can arrive from an auction before this keeper-only synchronization runs.

[Socratic: src/GroveCompounder.sol:117 — why?]
Why is loose USDS included only in the keeper report while the imported runtime asks for a live asset estimate before issuing new shares? The implicit belief is that economically earned USDS cannot arrive between reports, but Auction settlement sends it directly to the strategy.

[Inversion: GroveCompounder._harvestAndReport]
1. Settle an already-kicked auction, then deposit before the next keeper report so the deposit is priced without the proceeds. 2. Buy from the auction and make the diluting deposit in the same transaction or following block. 3. Send loose USDS directly to the strategy, deposit against the old accounting value, then wait for the next report to recognize it.

[Feynman: GroveCompounder._emergencyWithdraw]
This returns as much requested principal as possible from staking, capped at the strategy's actual staked balance.

[Feynman: GroveCompounder.availableDepositLimit]
This refuses new deposits while Sky staking is paused and otherwise applies the inherited whitelist and shutdown rules.

[Feynman: GroveCompounder._min]
This picks the smaller of two whole-number amounts.

[Feynman: GroveCompounder.claimRewards]
This lets management move all currently earned GROVE from staking into the strategy wallet without selling it.

[Feynman: GroveCompounder._claimRewards]
This asks the staking system to pay all currently earned GROVE to the strategy.

[Feynman: GroveCompounder.kickAuction]
This lets a keeper collect GROVE when appropriate, measure the chosen token balance, and send that balance to the configured auction when it exceeds the reward-token threshold.

[Socratic: src/GroveCompounder.sol:168 — why?]
Why is every arbitrary `_token` compared with `minAmountToSell[REWARDS_TOKEN]`? The implicit belief is that every auctioned token has the same decimals and economic threshold as GROVE, although the function accepts any non-USDS token.

[Feynman: GroveCompounder._kickAuction]
This refuses to sell principal, sends the full selected token balance to a nonzero auction, and asks that auction to start selling it.

[Inversion: GroveCompounder._kickAuction]
1. Supply USDS itself and confirm the principal guard stops the transfer. 2. Supply a six-decimal token and exploit the GROVE-denominated threshold mismatch to strand it. 3. Change the external auction receiver after strategy configuration and observe that the strategy does not re-check the receiver at kick time.

[Feynman: GroveCompounder.setMinAmountToSell]
This lets management change how much GROVE must accumulate before a sale is attempted.

[Feynman: GroveCompounder.setUniV3Fees]
This lets management choose the GROVE/USDC market fee used by direct reward sales.

[Feynman: GroveCompounder.setAuction]
This lets management select an auction after checking where that auction currently sends proceeds and which token it currently requests, or clear it only after leaving auction mode.

[Inversion: GroveCompounder.setAuction]
1. Try a zero address while auction mode is live. 2. Try an auction whose output token is not USDS. 3. Pass both checks, then have the auction's separate governor change its mutable receiver before the next kick.

[Feynman: GroveCompounder.setUseAuction]
This lets management choose delayed auction settlement or immediate market sale and prevents selecting the auction route without an address.

[Feynman: GroveCompounder.setReferral]
This lets management replace the code attached to future staking deposits.

[Feynman: ISwapRouterWithFactory]
This is the narrow promise that the selected Uniswap router can identify the factory that maps a token pair and fee to a pool.

[Feynman: ISwapRouterWithFactory.factory]
This returns the factory address associated with a router.

[Feynman: UniswapV3SwapSimulator]
This helper estimates the result of a Uniswap V3 trade by reading the pool and replaying how its price would move, without changing the pool.

[Feynman: UniswapV3SwapSimulator.simulateExactInputSingle]
This finds the requested market, decides which token is first by address order, simulates spending the requested input, and reports the output-token amount.

[Inversion: UniswapV3SwapSimulator.simulateExactInputSingle]
1. Pass an absent market so the pool read fails. 2. Pass an input above the largest positive signed amount so its meaning flips when handed to the simulator. 3. Move the pool price immediately before the call because all reads use current state rather than a time average.

[Feynman: UniswapV3SwapSimulator.getPool]
This asks the router's factory for the one market matching the two tokens and fee.

[Feynman: Simulate]
This library mirrors Uniswap V3's step-by-step trade calculation using only market observations.

[Feynman: Simulate.simulateSwap]
This walks price ranges until the requested input is consumed or the price limit is reached, adjusting remaining input, output, current price, current tick, and active liquidity at every step. The delicate point is that its unchecked signed bookkeeping assumes the same input bounds as the original pool.

[Inversion: Simulate.simulateSwap]
1. Start with zero input and confirm it is rejected. 2. Use the minimum signed input and attack the negation and remaining-amount boundaries. 3. Cross an initialized tick whose liquidity change is the minimum signed 128-bit value and compare the result to upstream behavior.

[Feynman: Simulate.nextInitializedTickWithinOneWord]
This searches the current 256-tick bitmap word in the trade direction and returns either the closest marked tick or that word's edge.

[Feynman: Simulate.tickBitmapPosition]
This splits a compressed tick number into the bitmap word and bit that contain it.

[Feynman: GroveCompounderAprOracle]
This estimates annual GROVE yield in USDS by dividing annual reward value by total Sky stake after a hypothetical debt change. It prefers one Uniswap V3 spot quote and consults configured Uniswap V4 markets only when V3 is unavailable.

[Feynman: GroveCompounderAprOracle._onlyManagement]
This rejects configuration changes from anyone other than the stored oracle manager.

[Feynman: GroveCompounderAprOracle.constructor]
This makes the deployer manager and seeds four V4 market identifiers with the expected USDC-first ordering.

[Feynman: GroveCompounderAprOracle.aprAfterDebtChange]
This reads total Sky stake and GROVE emissions, returns zero after emissions end, values GROVE, adds or subtracts the requested strategy debt change from global stake, and rejects results over 50%. The fuzzy point is that it never inspects the strategy even though loose USDS changes how much global stake an actual deposit or withdrawal changes.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:109 — why?]
Why is `_strategy` ignored while `_delta` is applied one-for-one to global staking supply? The implicit belief is that the strategy always holds zero loose USDS, contradicted by auction settlement, shutdown, dust, donations, and the explicit `balanceOfAsset()` path.

[Inversion: GroveCompounderAprOracle.aprAfterDebtChange]
1. Give the strategy 100 USDS of settled auction proceeds and query a 100 USDS debt decrease: the oracle subtracts 100 from stake although withdrawal touches no stake. 2. Query a 100 USDS increase while the same 100 USDS is loose: the next deposit stakes 200 but the oracle adds only 100. 3. Make loose assets exceed global stake and request a valid strategy debt decrease to turn a quote into arithmetic underflow.

[Feynman: GroveCompounderAprOracle.setManagement]
This lets the current manager immediately appoint a nonzero successor.

[Feynman: GroveCompounderAprOracle.setUniV3Fee]
This lets management select a fee tier only when the router's current factory mapping contains a GROVE/USDC pool for it.

[Feynman: GroveCompounderAprOracle.setUniV4Pool]
This replaces all fallback candidates with one nonzero market identifier and a declared token ordering.

[Feynman: GroveCompounderAprOracle.setUniV4Pools]
This forwards a complete replacement list and matching token-order flags to the shared list-validation routine.

[Feynman: GroveCompounderAprOracle.addUniV4Pool]
This appends a nonzero market identifier only if that identifier is not already present.

[Feynman: GroveCompounderAprOracle.removeUniV4Pool]
This removes one candidate by replacing it with the last candidate and shortening the list, while refusing to leave the list empty.

[Feynman: GroveCompounderAprOracle.uniV3Pool]
This reports the factory market currently selected by the stored V3 fee.

[Feynman: GroveCompounderAprOracle.uniV4PoolCount]
This reports how many V4 fallback candidates are configured.

[Feynman: GroveCompounderAprOracle.uniV4Pool]
This reports one configured V4 identifier and the declared location of GROVE in its token ordering.

[Feynman: GroveCompounderAprOracle.groveUsdcV4PoolId]
This reports the first V4 fallback identifier for compatibility with single-pool consumers.

[Feynman: GroveCompounderAprOracle.v4GroveIsToken0]
This reports the first V4 candidate's declared GROVE ordering for compatibility with single-pool consumers.

[Feynman: GroveCompounderAprOracle.bestUniV4Pool]
This reports which acceptable V4 candidate has the largest raw active-liquidity number.

[Feynman: GroveCompounderAprOracle.selectedUniV4Pool]
This reports the selected V4 candidate together with ordering, active liquidity, and computed GROVE price.

[Feynman: GroveCompounderAprOracle._grovePrice]
This trusts the current V3 one-GROVE quote whenever the V3 market passes two static size gates; only a missing, failing, or zero V3 quote reaches the V4 median filter.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:211 — why?]
Why does one V3 spot observation bypass all four independent V4 observations? The implicit belief is that minimum raw liquidity and a 1,000-USDC balance make a current price manipulation-resistant, but neither check measures time persistence or the cost of moving the price.

[Inversion: GroveCompounderAprOracle._grovePrice]
1. Use temporary capital to move the configured V3 price, query the APR in the same transaction, and reverse the trade. 2. Keep the false quote below the 50% APR cap so the manipulated value is returned rather than rejected. 3. Push the quote above the cap to make every consuming operation revert instead of falling back to V4.

[Feynman: GroveCompounderAprOracle._v3PoolHasUsableLiquidity]
This accepts a V3 market when it exists, has at least the configured active-liquidity number, and owns at least 1,000 USDC in total.

[Inversion: GroveCompounderAprOracle._v3PoolHasUsableLiquidity]
1. Donate USDC to satisfy the balance check without adding trading depth. 2. Concentrate the minimum liquidity narrowly around a manipulated current price. 3. Move a legitimately liquid pool within one transaction because the check has no time component.

[Feynman: GroveCompounderAprOracle._v4GrovePrice]
This converts the current V4 square-root price into USDC received for one GROVE and expands six-decimal USDC into an eighteen-decimal value.

[Feynman: GroveCompounderAprOracle._selectedV4Pool]
This gathers nonzero prices from sufficiently liquid configured V4 markets, finds their median, discards quotes more than 10% from it, and selects the remaining quote with the greatest raw liquidity.

[Inversion: GroveCompounderAprOracle._selectedV4Pool]
1. With one configured pool, move that pool because its own price is always its median. 2. With two far-apart pools, place the arithmetic median more than 10% from both and force no selection. 3. Move enough candidates just inside the median band and give the manipulated candidate the largest liquidity value so it wins selection.

[Feynman: GroveCompounderAprOracle._medianPrice]
This copies candidate prices, orders them from low to high, and returns the middle price or the average of the two middle prices.

[Feynman: GroveCompounderAprOracle._withinV4PriceDeviation]
This accepts a candidate whose absolute price distance from the reference is no more than 10% of the reference.

[Feynman: GroveCompounderAprOracle._setUniV4Pools]
This replaces the V4 candidate list only with a nonempty, equally sized set of identifiers and ordering flags, rejecting zero and repeated identifiers.

[Feynman: GroveCompounderAprOracle._hasUniV4Pool]
This scans the current candidate list and reports whether a particular identifier already exists.

[Feynman: GroveCompounderAprOracle._uniV3Pool]
This resolves the V3 market for the currently stored fee.

[Feynman: GroveCompounderAprOracle._uniV3PoolForFee]
This asks the router's factory for the GROVE/USDC market at a supplied fee.

[Feynman: GroveCompounderAprOracle._quoteToken1ForToken0]
This computes how much second-ordered token corresponds to a supplied first-token amount at a square-root price while choosing an intermediate scale that avoids overflow.

[Feynman: GroveCompounderAprOracle._quoteToken0ForToken1]
This computes how much first-ordered token corresponds to a supplied second-token amount at a square-root price while choosing an intermediate scale that avoids overflow.

### Targeted dependency checks

[Feynman: IStaking]
The staking boundary exposes the asset and reward identities, pause and emission state, global and per-account stake, and the actions that stake, withdraw, or collect rewards.

[Feynman: IPsmWrapper]
The PSM boundary identifies USDS and its intermediate token, exposes the sale fee, and converts a requested intermediate-token amount into USDS for a receiver.

[Feynman: UniswapV3Swapper._swapFrom]
This inherited helper spends an exact input through one or two configured V3 markets and accepts any output when the caller supplies a zero minimum. GroveCompounder does supply zero.

[Feynman: BaseHealthCheck.strategyTotalAssets]
This asks the strategy for its live asset estimate and clamps it to the configured profit/loss range. Because GroveCompounder does not replace the internal estimator, the inherited default is the previously recorded amount rather than `balanceOfStake() + balanceOfAsset()`.

[Feynman: BaseHealthCheck.availableDepositLimit]
This inherited gate permits deposits only for an open strategy or an explicitly allowed owner.

[Feynman: Auction._kick]
This records the auction's entire current balance of an enabled sale token as available and timestamps the sale.

[Feynman: Auction.setReceiver]
This lets the auction's separate governor change where future buyer payments go whenever no auction is active.

[Feynman: Auction._take]
This sends sale tokens to a buyer, then pulls the requested USDS-like payment from that buyer directly to the auction's current receiver.

[Feynman: TokenizedStrategy.deposit]
This synchronizes accounting, prices new shares, receives the depositor's assets, and asks the strategy to deploy its entire loose asset balance.

[Feynman: TokenizedStrategy.mint]
This synchronizes accounting, computes how many assets exact new shares cost, receives them, and deploys the entire loose balance.

[Feynman: TokenizedStrategy.withdraw]
This synchronizes accounting, determines shares for an exact asset request, uses loose assets first, and frees only the shortfall from the strategy.

[Feynman: TokenizedStrategy.redeem]
This synchronizes accounting, converts exact shares into assets, uses loose assets first, and frees only any shortfall.

[Feynman: TokenizedStrategy._deposit]
This receives the user's assets and then deploys every loose USDS already in the strategy, not merely the new deposit. This confirms that a positive debt delta can change global stake by more than the delta when auction proceeds are waiting loose.

[Feynman: TokenizedStrategy._withdraw]
This measures loose USDS first and calls the strategy withdrawal hook only when loose USDS is insufficient. This confirms that a negative debt delta can leave global staking supply unchanged.

[Feynman: TokenizedStrategy._accrue]
This compares a strategy-provided live asset estimate with the last recorded amount and updates share accounting, but only once per timestamp. GroveCompounder's inherited estimate returns the old recorded amount, so loose auction proceeds do not enter this comparison.

[Feynman: BaseStrategy._strategyTotalAssets]
The inherited default reports the last recorded asset amount rather than measuring current positions; individual strategies must replace it to opt into live accounting.

[Feynman: TokenizedStrategy.report]
This invokes the strategy's mutable harvest, compares the returned physical assets with the old accounting amount, charges fees, and locks or offsets the difference before recording the new amount.

[Feynman: AprOracle.getStrategyApr]
The wider Yearn oracle routes a strategy address and proposed debt change into this custom oracle, confirming that the result is intended to guide strategy-specific allocation decisions.

## Invariant map and attack results

- **INV-SHARE-1 — Share-pricing conservation:** before minting shares, the asset total used for conversion must include all owned USDS that existing shareholders have already earned. **Broken.** Auction proceeds arrive as loose USDS while GroveCompounder inherits an estimator that returns only the last recorded total.
- **INV-SHARE-2 — Report conservation:** after a successful GroveCompounder report, recorded assets equal `balanceOfStake() + balanceOfAsset()`. **Holds for standard exact-transfer USDS and exact staking accounting.**
- **INV-STAKE-1 — Debt-change coupling:** the staking-supply denominator used for an APR prediction must equal the actual Sky total supply after the same strategy debt change. **Broken whenever the strategy has loose USDS.**
- **INV-PRICE-1 — Atomic-price independence:** a same-transaction reversible pool-price move must not be able to materially change the APR returned to a state-changing consumer. **Broken by the unconditional V3 spot-price preference.**
- **INV-AUCTION-1 — Mode coupling:** `useAuction == true` should imply `auction != 0`. **False only at deployment.** Deposits are closed by default and management can repair the state, so this is not elevated.
- **INV-AUCTION-2 — Principal isolation:** no first-party auction path may transfer USDS principal. **Holds:** `_kickAuction` rejects the strategy asset.
- **INV-V4-1 — Candidate-set integrity:** at least one nonzero, unique V4 pool remains after successful configuration. **Holds across every writer.**
- **INV-SIM-1 — Quote traversal equivalence:** for the fixed 1e18 positive input used by the oracle, tick traversal and amount signs match the pinned upstream V3 calculation. **No exploitable divergence found.**

FINDING | contract: GroveCompounder | function: _strategyTotalAssets (missing override) | bug_class: stale-total-assets-dilution | group_key: GroveCompounder | _strategyTotalAssets | stale-total-assets-dilution
path: public auction buyer settles kicked GROVE → Auction sends earned USDS to GroveCompounder → public depositor calls inherited `deposit` before keeper `report` → inherited live accrual reads the old `lastTotalAssets` because GroveCompounder has no `_strategyTotalAssets` override → depositor receives too many shares → next report recognizes the settled USDS → locked profit later unlocks to incumbent and attacker shares alike → attacker withdraws part of pre-deposit profit
invariant: The asset total used to mint shares must include every unit of USDS already owned for incumbent shareholders, including loose auction proceeds.
violation_path: `Auction._take` transfers USDS to the strategy → wait without a keeper report → attacker `deposit(1_000e18)` → `_accrue` obtains the inherited stale estimate → `_deposit` stakes both proceeds and attacker assets → keeper `report()` recognizes the omitted proceeds → attacker waits for profit unlock and redeems.
proof: Start with 1,000 USDS staked, `lastTotalAssets = 1,000`, and 1,000 incumbent shares. An auction then settles 100 USDS to the strategy, so physical assets are 1,100 but the inherited estimator and `totalAssets()` remain 1,000. An attacker deposits 1,000 USDS and receives 1,000 shares at 1 USDS/share; `_deposit` stakes the full loose 1,100 USDS, bringing physical assets to 2,100. The next report records 100 USDS profit. With zero performance fee, after that profit fully unlocks the 2,000 user-held shares claim 2,100 USDS: the attacker redeems 1,050 USDS, earning 50 USDS, while incumbents receive 1,050 instead of the 1,100 they owned before the attack. The path needs no exact-block race because settlement can remain unreported between keeper calls.
description: Asynchronous USDS auction proceeds are omitted from share pricing until a keeper report, allowing a new depositor to dilute and capture previously earned profit.
fix: Provide a live GroveCompounder asset estimator returning staked plus loose USDS and ensure auction settlement is synchronized into share pricing before any mint (including the runtime's same-timestamp latch case).

FINDING | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: idle-balance-denominator-divergence | group_key: GroveCompounderAprOracle | aprAfterDebtChange | idle-balance-denominator-divergence
path: Auction settles USDS to strategy → allocator queries custom APR for a positive or negative debt change → oracle blindly adds/subtracts the full delta from global Sky stake → inherited deposit/withdraw uses the strategy's loose balance and changes global stake by a different amount → allocator acts on an APR that cannot occur
invariant: For the same debt change, the denominator used by `aprAfterDebtChange` must equal Sky `totalSupply` after GroveCompounder's actual deposit or withdrawal path.
violation_path: Create a valid strategy state with loose USDS (normal auction settlement suffices) → call `aprAfterDebtChange(strategy, delta)` → execute the corresponding ERC-4626 deposit/withdraw → compare the oracle's adjusted `assets` with the actual change in `STAKING.totalSupply()`.
proof: Normalize the annual reward-value numerator to 100, let global Sky stake be 1,000 USDS, and let GroveCompounder hold 100 loose USDS. For `_delta = -100`, the oracle uses denominator 900 and returns 11.111%, but inherited `_withdraw` uses the 100 loose USDS and never calls `_freeFunds`, leaving Sky stake at 1,000 and actual APR at 10%. For `_delta = +100`, the oracle uses denominator 1,100 and returns 9.091%, but inherited `_deposit` passes the entire 200 loose USDS (old 100 plus new 100) to `_deployFunds`, so Sky stake becomes 1,200 and actual APR is 8.333%. If a valid debt decrease exceeds global stake only because the strategy has enough loose assets, the same bug instead underflows and makes the quote revert.
description: Ignoring `_strategy` and its loose USDS breaks the one-to-one coupling assumed between a strategy debt delta and global staking supply.
fix: Validate/query the target GroveCompounder and adjust global stake by the actual stake-changing amount: withdrawals reduce stake only by `max(abs(delta) - looseUSDS, 0)`, while deposits also deploy existing loose USDS under the current runtime path.

FINDING | contract: GroveCompounderAprOracle | function: _grovePrice | bug_class: manipulable-spot-price | group_key: GroveCompounderAprOracle | _grovePrice | manipulable-spot-price
path: attacker obtains temporary capital → swaps against the configured GROVE/USDC V3 pool to move its current price while leaving liquidity and USDC balance above static thresholds → state-changing allocator calls `getStrategyApr`/`aprAfterDebtChange` in the same transaction → oracle unconditionally accepts the simulated one-GROVE spot quote and bypasses all V4 candidates → allocator changes debt using a false APR → attacker reverses the price move
invariant: The APR used for a debt-allocation decision must not materially change solely because of an atomic, reversible move in one permissionless market.
violation_path: Move V3 `slot0` with a flash-funded swap → call the downstream Yearn APR consumer before unwinding → `_v3PoolHasUsableLiquidity` still passes → `simulateExactInputSingle` reads the manipulated state → `_grovePrice` returns immediately without comparing V4 → unwind.
proof: With Sky stake of 100,000,000 USDS and `rewardRate = 1 GROVE/second`, a 1-GROVE quote of 0.026362 USDC yields `price = 0.026362e18` and APR `1e18 * 31,536,000 * 0.026362e18 / 100,000,000e18 = 0.008313e18` (0.8313%). Moving the current V3 quote to 1 USDC per GROVE makes the same call return `0.31536e18` (31.536%), a roughly 38x increase that remains below `MAX_EXPECTED_APR = 50%`. Neither `liquidity() >= 1e12` nor `USDC.balanceOf(pool) >= 1,000e6` constrains observation age or compares the result with V4, so both checks can remain true throughout the atomic manipulation.
description: A manipulable V3 spot quote has absolute priority over the multi-pool V4 filter, allowing atomic inflation, suppression, or denial of strategy APR reads.
fix: Use a manipulation-resistant time-weighted/independent price and require V3 agreement with the V4 median (or another trusted reference) before allowing its early return.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: realized-sale-quote-divergence | group_key: GroveCompounderAprOracle | aprAfterDebtChange | realized-sale-quote-divergence
code_smells: The oracle always values emissions using the marginal output of exactly 1 GROVE on the oracle's configured V3 fee or a V4 spot, while GroveCompounder defaults to an Auction and the direct route sells the entire accumulated GROVE balance using a separately configurable fee. A 1-GROVE marginal quote can materially exceed the average execution price of a threshold-sized sale, and auction proceeds can differ again.
description: The advertised APR is not coupled to the strategy's configured sale route, fee tier, sale size, or realized auction discount; quantifying downstream loss requires the allocator's tolerance and live venue depths.

LEAD | contract: GroveCompounderAprOracle | function: aprAfterDebtChange | bug_class: reward-period-boundary | group_key: GroveCompounderAprOracle | aprAfterDebtChange | reward-period-boundary
code_smells: The expiry check is `block.timestamp > periodFinish`; at exact equality, future reward accrual has ended but the function still annualizes the old `rewardRate` and may return a positive APR for that block.
description: A one-timestamp stale-APR window is proven, but meaningful exploitation depends on a downstream allocation executing exactly at `periodFinish`.

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: cross-token-threshold-mismatch | group_key: GroveCompounder | kickAuction | cross-token-threshold-mismatch
code_smells: `kickAuction` accepts any non-asset token but always compares its raw balance with `minAmountToSell[REWARDS_TOKEN]`; the default 5,000e18 GROVE threshold makes a normal six-decimal token effectively impossible to kick and applies no token-specific economics.
description: Non-GROVE balances can be stranded or kicked at nonsensical sizes, but an exploitable live secondary-token flow and enabled auction were not established in scope.

## Dismissed after invariant testing

- `useAuction=true` with `auction=0` is a real deployment-time invariant violation, but deposits are closed by default and management can restore the coupling before opening the strategy; no untrusted extraction path was established.
- `setAuction` checks receiver only at configuration while the imported Auction receiver is mutable. Exploitation requires the separately privileged Auction governor to redirect proceeds, so this reduces to a trusted/dependency compromise under the stated model.
- Direct reward sale supplies zero minimum output. This is exposed to sandwiching, but it is a standard MEV/slippage tradeoff explicitly excluded by the scan rules and is not reported separately from the oracle-integrity finding.
- Boundary analysis of the simulator found exotic misuse above `int256.max`, but the only in-scope caller fixes input at `1e18`, so no reachable protocol impact exists.
