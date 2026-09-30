# Access Control Lane

Scope reviewed:
- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

Supporting context used for access-control reachability only:
- `lib/tokenized-strategy/src/BaseStrategy.sol`
- `lib/tokenized-strategy/src/TokenizedStrategy.sol`
- `lib/tokenized-strategy/src/libraries/TokenizedStrategyLib.sol`
- `lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol`
- `lib/tokenized-strategy-periphery/src/swappers/BaseSwapper.sol`
- `lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol`
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol`

## Working Markers

[Feynman: GroveCompounder] This contract accepts USDS, stakes it in the fixed Sky staking contract, gathers GROVE rewards, and either sends those rewards to a configured auction or swaps them through Uniswap/PSM back into USDS. The access-control question is who can change reward-sale settings, who can trigger reward movement, and whether any outside caller can make the strategy stake, unstake, harvest, or sell outside the intended roles.

[Feynman: GroveCompounder.constructor] Deployment checks the fixed staking and USDS wrapper addresses, records the reward token, gives fixed external contracts spending permission for the tokens they need, and seeds the default reward-sale thresholds and Uniswap fee. The fuzzy point is that permissions are established to fixed external contracts, so later attack paths must either control those fixed contracts or find an exposed strategy function that can abuse the approval.

[Feynman: balanceOfAsset] This reports how much loose USDS the strategy currently holds.

[Feynman: balanceOfStake] This reports how much USDS the staking contract says this strategy has staked.

[Feynman: balanceOfRewards] This reports how much GROVE reward token sits loose in the strategy.

[Feynman: claimableRewards] This asks the staking contract how much GROVE the strategy could collect now.

[Feynman: _deployFunds] This sends loose USDS into the staking contract using the current referral code.

[Feynman: _freeFunds] This pulls USDS back out of staking.

[Feynman: _harvestAndReport] This collects GROVE rewards, decides whether to auction or swap them, possibly turns received USDS back into staked USDS, and returns the total USDS it controls. The access-control sensitivity is that keepers reach this through `report`, so any action inside it must be acceptable for keeper-triggered execution.

[Feynman: _emergencyWithdraw] This pulls back at most the currently staked USDS when the shared strategy emergency path asks it to.

[Feynman: availableDepositLimit] This closes deposits when the external staking contract is paused, otherwise it applies the inherited open/allowlist deposit gate.

[Feynman: _min] This returns the smaller of two numbers.

[Feynman: claimRewards] This lets management manually collect pending GROVE into the strategy without selling it.

[Feynman: _claimRewards] This asks the fixed staking contract to send this strategy its pending GROVE.

[Feynman: kickAuction] This lets the keeper or management start an auction sale while auction mode is enabled. If the requested token is GROVE, it first collects pending rewards; otherwise it uses whatever balance of that token is already in the strategy. The sharp edge is whether this is only normal keeper maintenance or an unauthorized token-movement deputy.

[Feynman: _kickAuction] This rejects USDS, checks that an auction was configured, sends the token balance to that auction, then tells the auction to start selling that token.

[Feynman: setMinAmountToSell] This lets management change the GROVE amount needed before the strategy sells rewards.

[Feynman: setUniV3Fees] This lets management change the Uniswap V3 fee tier used for the GROVE-to-USDC sale.

[Feynman: setAuction] This lets management choose the auction contract, but only if that auction sends proceeds back to this strategy and sells into the strategy asset. Clearing the auction is allowed only after auction mode is off.

[Feynman: setUseAuction] This lets management choose auction sale mode or Uniswap/PSM sale mode. Turning auction mode on requires a nonzero auction address.

[Feynman: setReferral] This lets management change the referral value used when staking.

[Feynman: BaseStrategy.onlyManagement] This accepts only the strategy's management address as caller.

[Feynman: BaseStrategy.onlyKeepers] This accepts either management or the keeper address as caller.

[Feynman: BaseStrategy.onlyEmergencyAuthorized] This accepts either management or the emergency admin address as caller.

[Feynman: BaseStrategy._initialize] This sets initial strategy roles during construction by forwarding into the shared strategy implementation.

[Feynman: BaseStrategy.deployFunds] This externally visible callback can stake funds only when the caller is the strategy itself.

[Feynman: BaseStrategy.freeFunds] This externally visible callback can free funds only when the caller is the strategy itself.

[Feynman: BaseHealthCheck.harvestAndReport] This externally visible callback can run the strategy's report logic only when the caller is the strategy itself, then enforces the health check.

[Feynman: BaseStrategy.tendThis] This externally visible callback can run tending only when the caller is the strategy itself.

[Feynman: BaseStrategy.shutdownWithdraw] This externally visible callback can run emergency withdrawal only when the caller is the strategy itself.

[Feynman: BaseStrategy.fallback] This forwards unknown calls into the shared TokenizedStrategy implementation while keeping storage in the strategy. The access-control concern is whether forwarded functions like `initialize`, `report`, or setters can be abused.

[Feynman: TokenizedStrategy.initialize] This sets the shared strategy storage once and refuses to run again after the asset has been set.

[Feynman: TokenizedStrategy.report] This lets keeper or management update accounting and call back into the strategy's harvest logic.

[Feynman: TokenizedStrategy.tend] This lets keeper or management call the strategy's tending callback with the loose asset balance.

[Feynman: TokenizedStrategy.shutdownStrategy] This lets management or emergency admin permanently close new deposits.

[Feynman: TokenizedStrategy.setPaused] This lets management or emergency admin pause user-facing actions, but only management can unpause.

[Feynman: TokenizedStrategy.emergencyWithdraw] This lets management or emergency admin pull funds back from the yield source after pause or shutdown.

[Feynman: TokenizedStrategy.setPendingManagement] This lets current management nominate the next management address.

[Feynman: TokenizedStrategy.acceptManagement] This lets only the nominated pending management address take over.

[Feynman: TokenizedStrategy.setKeeper] This lets management set the keeper address.

[Feynman: TokenizedStrategy.setEmergencyAdmin] This lets management set the emergency admin address.

[Feynman: BaseHealthCheck.setProfitLimitRatio] This lets management change the report profit limit.

[Feynman: BaseHealthCheck.setLossLimitRatio] This lets management change the report loss limit.

[Feynman: BaseHealthCheck.setDoHealthCheck] This lets management disable or enable the next report health check behavior.

[Feynman: BaseHealthCheck.setOpen] This lets management open or close deposits globally.

[Feynman: BaseHealthCheck.setAllowed] This lets management set a depositor's whitelist status when deposits are not globally open.

[Feynman: GroveCompounderAprOracle] This contract reports an APR from fixed staking emissions and configurable GROVE/USDC price sources. The access-control question is who can change management and the pricing pools that the oracle will trust.

[Feynman: GroveCompounderAprOracle.onlyManagement] This check accepts only the stored management address as caller.

[Feynman: GroveCompounderAprOracle.constructor] Deployment sets management to the deployer and installs four default Uniswap V4 pool IDs.

[Feynman: aprAfterDebtChange] This reads staking totals, reads a GROVE price, applies a hypothetical debt change, and returns a capped APR. It does not change state.

[Feynman: setManagement] This lets the current oracle management hand the oracle to a nonzero new management address immediately.

[Feynman: setUniV3Fee] This lets oracle management choose a Uniswap V3 fee tier only when the factory has a GROVE/USDC pool for that fee.

[Feynman: setUniV4Pool] This lets oracle management replace the V4 fallback list with one nonzero pool ID and its GROVE side.

[Feynman: setUniV4Pools] This lets oracle management replace the V4 fallback list with a nonempty, same-length, duplicate-free set of nonzero pool IDs.

[Feynman: addUniV4Pool] This lets oracle management append a new nonzero, nonduplicate V4 pool ID.

[Feynman: removeUniV4Pool] This lets oracle management remove one configured V4 pool while keeping at least one pool configured.

[Feynman: uniV3Pool] This reports the current V3 pool address.

[Feynman: uniV4PoolCount] This reports how many V4 fallback pools are configured.

[Feynman: uniV4Pool] This reports one configured V4 pool.

[Feynman: groveUsdcV4PoolId] This reports the first configured V4 pool.

[Feynman: v4GroveIsToken0] This reports the GROVE side for the first configured V4 pool.

[Feynman: bestUniV4Pool] This reports the selected V4 pool by liquidity after price-deviation filtering.

[Feynman: selectedUniV4Pool] This reports the selected V4 pool and its price.

[Feynman: _grovePrice] This first tries the configured V3 price path and falls back to selected V4 pricing.

[Feynman: _selectedV4Pool] This samples all configured V4 pools, filters unusable prices, computes the median price, and selects the most liquid pool close to that median.

[Feynman: _setUniV4Pools] This validates and replaces the entire V4 pool list.

[Socratic: src/GroveCompounder.sol:163 — why?] Why can `kickAuction(REWARDS_TOKEN)` collect rewards when `claimRewards()` is management-only? The implicit belief is that keepers already have reward-harvest authority through `report()`, so manual collection is not exclusively a management action.

[Socratic: src/GroveCompounder.sol:169 — why?] Why is the GROVE threshold used even when `_token` is not GROVE? The implicit belief is that this strategy's normal auctioned token is GROVE and non-asset token kicks are incidental recovery/sale paths governed by the same keeper role plus auction enablement.

[Socratic: src/GroveCompounder.sol:178 — why?] Why transfer before calling `Auction.kick`? The auction records availability from its own balance, so it must receive the tokens before it can start the sale; a later `kick` revert rolls the transfer back.

[Socratic: src/GroveCompounder.sol:209 — why?] Why only check `receiver()` and `want()` for a new auction? The implicit trust boundary is that management chooses the auction contract, while these checks prevent accidentally routing sale proceeds away from the strategy or into the wrong asset.

[Socratic: lib/tokenized-strategy/src/BaseStrategy.sol:509 — why?] Why does the strategy forward unknown calls into a shared implementation? The implicit safety property is that the forwarded implementation owns the role checks and once-only initialization guard, while strategy-specific callbacks are protected by `onlySelf`.

[Socratic: src/periphery/GroveCompounderAprOracle.sol:135 — why?] Why is oracle management transfer single-step while the strategy's management transfer is two-step? The oracle holds no funds and blocks zero management, so the remaining risk is management self-lockout rather than outside privilege escalation.

[Inversion: GroveCompounder.claimRewards] Attacker move 1: call `claimRewards()` from a random address; `onlyManagement` rejects through TokenizedStrategy management. Attacker move 2: call as keeper; direct call still fails because keeper is not management. Attacker move 3: call `kickAuction(REWARDS_TOKEN)` as keeper to collect rewards; this is within keeper maintenance authority because `report()` is also keeper-gated and calls `_harvestAndReport`.

[Inversion: GroveCompounder.kickAuction] Attacker move 1: call from a non-keeper; `onlyKeepers` rejects. Attacker move 2: call with USDS as `_token`; `_kickAuction` rejects `_token == asset`. Attacker move 3: call with a random token; the strategy can only send its existing balance to the management-configured auction, and `Auction.kick` reverts unless that token has been enabled by auction governance.

[Inversion: GroveCompounder._kickAuction] Attacker move 1: configure `auction = address(0)` then kick; only management can clear the auction and only after `useAuction` is false, while kicks require `useAuction`. Attacker move 2: use an auction that pays another receiver; `setAuction` requires `receiver() == address(this)`. Attacker move 3: use an auction that sells into another want token; `setAuction` requires `want() == asset`.

[Inversion: GroveCompounder.setAuction] Attacker move 1: non-management tries to set a malicious auction; `onlyManagement` rejects. Attacker move 2: management tries to set an auction with the wrong receiver; line 211 rejects. Attacker move 3: management tries to unset the auction while auction mode is true; line 214 rejects.

[Inversion: GroveCompounder.setUseAuction] Attacker move 1: non-management tries to force swap mode or auction mode; `onlyManagement` rejects. Attacker move 2: management tries to enable auction mode without an auction; line 225 rejects. Attacker move 3: default `useAuction = true` with no auction causes report liveness risk before setup, but does not grant unauthorized control.

[Inversion: GroveCompounder.callbacks] Attacker move 1: call `deployFunds()` directly to stake arbitrary loose USDS; `onlySelf` rejects. Attacker move 2: call `freeFunds()` directly to pull USDS out of staking; `onlySelf` rejects. Attacker move 3: call `harvestAndReport()` or `shutdownWithdraw()` directly; both require the strategy itself as caller.

[Inversion: TokenizedStrategy.initialize] Attacker move 1: call `initialize()` through fallback after deployment; the strategy asset was set during construction, so the implementation rejects as initialized. Attacker move 2: initialize the shared implementation itself; its constructor stores a nonzero sentinel asset. Attacker move 3: pass attacker roles after deployment; unreachable because the once-only guard is already closed.

[Inversion: GroveCompounderAprOracle.onlyManagement] Attacker move 1: random caller changes V3 fee; `onlyManagement` rejects. Attacker move 2: random caller replaces V4 pools; `onlyManagement` rejects. Attacker move 3: random caller transfers management; `onlyManagement` rejects.

[Inversion: GroveCompounderAprOracle.setManagement] Attacker move 1: current management transfers to `address(0)` and locks the oracle; line 136 rejects. Attacker move 2: pending/accept bypass; there is no pending state and only current management can write management. Attacker move 3: non-management front-runs a management change; line 92 rejects.

[Inversion: GroveCompounderAprOracle.setUniV4Pools] Attacker move 1: non-management installs a malicious pool list; `onlyManagement` rejects. Attacker move 2: management passes mismatched arrays; line 340 rejects. Attacker move 3: management passes duplicate or zero IDs; lines 345 and 348 reject.

## Access-Control Map

### GroveCompounder

- Strategy construction initializes TokenizedStrategy storage with deployer as management, performance fee recipient, and keeper via `BaseStrategy` constructor and `_initialize` (`lib/tokenized-strategy/src/BaseStrategy.sol:133-152`); `TokenizedStrategy.initialize` refuses a second initialization once `S.asset` is set (`lib/tokenized-strategy/src/TokenizedStrategy.sol:460-472`).
- `onlyManagement` resolves to `TokenizedStrategy.requireManagement(msg.sender)` (`lib/tokenized-strategy/src/BaseStrategy.sol:55-57`), and the underlying check requires the caller to equal stored management (`lib/tokenized-strategy/src/TokenizedStrategy.sol:330-331`).
- `onlyKeepers` resolves to `TokenizedStrategy.requireKeeperOrManagement(msg.sender)` (`lib/tokenized-strategy/src/BaseStrategy.sol:64-66`), and the underlying check accepts keeper or management (`lib/tokenized-strategy/src/TokenizedStrategy.sol:343-345`).
- `onlyEmergencyAuthorized` accepts emergency admin or management (`lib/tokenized-strategy/src/BaseStrategy.sol:73-75`, `lib/tokenized-strategy/src/TokenizedStrategy.sol:357-361`).
- Management-only Grove-specific setters are `claimRewards`, `setMinAmountToSell`, `setUniV3Fees`, `setAuction`, `setUseAuction`, and `setReferral` (`src/GroveCompounder.sol:145-146`, `src/GroveCompounder.sol:189-235`).
- Keeper/management Grove-specific entry is `kickAuction`, guarded by `onlyKeepers` and `useAuction` (`src/GroveCompounder.sol:158-170`).
- Management-only inherited controls include health-check limits, health-check toggle, deposit-open flag, and deposit allowlist (`lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol:74-130`).
- Fallback-delegated TokenizedStrategy controls keep management transfer two-step (`lib/tokenized-strategy/src/TokenizedStrategy.sol:1824-1839`), keep keeper/emergency-admin assignment management-only (`lib/tokenized-strategy/src/TokenizedStrategy.sol:1850-1865`), keep `report()` keeper/management-only (`lib/tokenized-strategy/src/TokenizedStrategy.sol:1400-1418`), and keep pause/shutdown/emergency withdraw on management/emergency-admin checks (`lib/tokenized-strategy/src/TokenizedStrategy.sol:1603-1656`).
- Direct callback entry points cannot be invoked by users because `deployFunds`, `freeFunds`, `harvestAndReport`, `tendThis`, and `shutdownWithdraw` require `msg.sender == address(this)` (`lib/tokenized-strategy/src/BaseStrategy.sol:91-92`, `lib/tokenized-strategy/src/BaseStrategy.sol:390-430`, `lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol:138-144`, `lib/tokenized-strategy/src/BaseStrategy.sol:446-463`).

### GroveCompounderAprOracle

- Oracle management is set to deployer in the constructor (`src/periphery/GroveCompounderAprOracle.sol:95-101`).
- The only oracle modifier requires `msg.sender == management` (`src/periphery/GroveCompounderAprOracle.sol:86-93`).
- Oracle management-only setters are `setManagement`, `setUniV3Fee`, `setUniV4Pool`, `setUniV4Pools`, `addUniV4Pool`, and `removeUniV4Pool` (`src/periphery/GroveCompounderAprOracle.sol:135-176`).
- The remaining external functions are views and do not write access-controlled state (`src/periphery/GroveCompounderAprOracle.sol:109-132`, `src/periphery/GroveCompounderAprOracle.sol:178-209`).

## Findings / Leads

No source-backed FINDING blocks and no plausible LEAD blocks were identified in this access-control lane.

Main surfaces reviewed:
- Grove reward collection and sale triggers: `claimRewards`, `kickAuction`, `_harvestAndReport`, `_kickAuction`.
- Grove management setters: reward threshold, UniV3 fee, auction address, auction mode, referral.
- Inherited strategy controls exposed through fallback: management transfer, keeper assignment, emergency admin, report/tend, pause/shutdown/emergency withdraw, deposit allowlist, health-check controls.
- Oracle management and pricing-pool setters.
- Initialization and callback-only entry points.

## Rejected / Notes

- Keeper reward collection via `kickAuction(REWARDS_TOKEN)` is not a reportable guard gap. `claimRewards()` is management-only (`src/GroveCompounder.sol:145-146`), but keeper/management can already run `report()` (`lib/tokenized-strategy/src/TokenizedStrategy.sol:1400-1403`), which reaches `_harvestAndReport()` and `_claimRewards()` (`src/GroveCompounder.sol:84-90`). The direct keeper path also requires auction mode and, above threshold, sends rewards to the configured auction (`src/GroveCompounder.sol:158-170`).
- Keeper-triggered non-asset token auction kicks did not graduate. `kickAuction` is keeper/management-only (`src/GroveCompounder.sol:158`), `_kickAuction` rejects the strategy asset and requires a configured auction (`src/GroveCompounder.sol:174-179`), `setAuction` is management-only and validates receiver/want (`src/GroveCompounder.sol:209-216`), and `Auction.kick` reverts unless the token was enabled by auction governance (`lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-520`).
- Direct callback invocation did not graduate. The externally visible callback functions are present in the ABI, but `onlySelf` requires the caller to be the strategy itself (`lib/tokenized-strategy/src/BaseStrategy.sol:91-92`, `lib/tokenized-strategy/src/BaseStrategy.sol:390-430`, `lib/tokenized-strategy/src/BaseStrategy.sol:446-463`).
- Re-initialization through fallback did not graduate. The constructor initializes storage (`lib/tokenized-strategy/src/BaseStrategy.sol:133-152`), and `TokenizedStrategy.initialize` requires the asset slot to still be zero (`lib/tokenized-strategy/src/TokenizedStrategy.sol:460-472`).
- Oracle single-step management transfer did not graduate. It is narrower than the strategy's two-step management transfer, but `setManagement` is current-management-only and rejects zero (`src/periphery/GroveCompounderAprOracle.sol:91-93`, `src/periphery/GroveCompounderAprOracle.sol:135-138`); the remaining risk is management self-lockout/misconfiguration, not an unauthorized escalation path.

## Local Validation

- `forge inspect src/GroveCompounder.sol:GroveCompounder methods`
- `forge inspect src/periphery/GroveCompounderAprOracle.sol:GroveCompounderAprOracle methods`

No forge tests were run for this lane because no candidate finding required proof execution.
