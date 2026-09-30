# Agent 02 — Access-Control Raw Scan

Scope: access-control, role escalation, initialization, confused-deputy, and guard consistency analysis only. X-ray material was used as orientation and every statement below was independently checked against the supplied source bundle or targeted imported dependency context.

## Mandatory mental-tool trace

[Feynman: GroveCompounder]
This contract accepts USDS through an inherited vault interface, places that USDS into the fixed Sky staking contract, claims GROVE rewards, and converts those rewards back toward USDS. Strategy management chooses sale settings; management or a keeper can perform maintenance. The contract itself never gives an arbitrary caller a direct instruction that names a recipient of principal or rewards.

[Feynman: GroveCompounder.constructor]
Deployment first initializes the inherited Yearn strategy roles to the deployer, then checks that the fixed staking and PSM contracts use the expected USDS token. It gives the fixed staking contract unlimited USDS spending permission and gives the fixed PSM wrapper unlimited USDC spending permission. It starts with auction mode selected but no auction address; that is an operational configuration gap, not a role bypass.

[Socratic: GroveCompounder.sol:43-49 — why?]
Why are unlimited approvals safe from an authority perspective? The implicit belief is that the two hard-coded counterparties remain trusted and cannot use their allowances outside the intended stake/conversion calls.

[Inversion: GroveCompounder.constructor]
1. Deploy through an attacker factory so the attacker factory becomes management: this only works if the legitimate deployer intentionally uses that factory, because construction and role initialization are atomic. 2. Call the TokenizedStrategy implementation's initializer before strategy construction: the implementation constructor has already set its own asset slot to address(1), so this reverts as initialized and cannot affect the strategy's storage. 3. Reenter during the PSM/staking constructor checks: any attempted call targets a contract whose construction has not completed, so there is no externally usable strategy runtime to seize.

[Feynman: GroveCompounder.balanceOfAsset]
This reports how much loose USDS the strategy currently holds and changes nothing.

[Feynman: GroveCompounder.balanceOfStake]
This reports how much USDS the fixed staking contract credits to the strategy and changes nothing.

[Feynman: GroveCompounder.balanceOfRewards]
This reports how much GROVE the strategy currently holds and changes nothing.

[Feynman: GroveCompounder.claimableRewards]
This asks the fixed staking contract how much GROVE the strategy can claim and changes nothing.

[Feynman: GroveCompounder._deployFunds]
This places a caller-specified quantity of strategy USDS into the fixed staking contract. Arbitrary users reach it only after the inherited vault logic has accepted and accounted for their deposit; keepers reach equivalent deployment through the inherited maintenance flow.

[Inversion: GroveCompounder._deployFunds]
1. Call `deployFunds` directly as an attacker: the external wrapper requires the caller to be the strategy itself. 2. Deposit zero or more than the user's balance: inherited accounting and token transfer checks prevent manufacturing strategy USDS. 3. Reenter through staking to call `deployFunds`: the wrapper still sees the staking contract rather than the strategy as caller and rejects it.

[Feynman: GroveCompounder._freeFunds]
This asks the fixed staking contract to return a stated quantity of the strategy's staked USDS. Permissionless users can cause it only inside an inherited withdrawal that accounts for and burns the caller's shares.

[Inversion: GroveCompounder._freeFunds]
1. Call `freeFunds` directly from an EOA: the self-only wrapper rejects the caller. 2. Withdraw against another holder without allowance: inherited share-allowance checks reject the request. 3. Reenter from the staking contract: the reentrant caller is not the strategy itself and cannot invoke the wrapper.

[Feynman: GroveCompounder._harvestAndReport]
This claims GROVE, sells it through either the configured auction or the fixed Uniswap/PSM route when the balance is above the threshold, restakes loose USDS, and returns the sum of staked and loose USDS. It is reached from the inherited report function, which is restricted to the keeper or management, through a self-only callback.

[Socratic: GroveCompounder.sol:93-109 — why?]
Why can reward realization move assets without a local modifier? The implicit belief is that the only external route is `TokenizedStrategy.report`, whose keeper/management guard runs before the strategy calls itself back.

[Inversion: GroveCompounder._harvestAndReport]
1. Call `harvestAndReport()` directly: `onlySelf` rejects every external address. 2. Call inherited `report()` as a depositor: the keeper/management guard rejects the depositor. 3. Reenter while GROVE, Uniswap, PSM, staking, or Auction is being called: a reentrant `report()` fails the inherited reentrancy guard, while a direct callback still fails `onlySelf`.

[Feynman: GroveCompounder._emergencyWithdraw]
This limits the requested rescue amount to what is actually staked, then retrieves that much USDS. The inherited external rescue function restricts entry to management or the emergency administrator and additionally requires the strategy to be paused or shut down.

[Inversion: GroveCompounder._emergencyWithdraw]
1. Call the external emergency method as keeper-only: keeper is not sufficient unless it is also management/emergency admin. 2. Call as emergency admin while live: the paused-or-shutdown requirement rejects it. 3. Call the internal callback directly: there is no ABI entry, and the self-only external wrapper rejectss non-self callers.

[Feynman: GroveCompounder.availableDepositLimit]
This reports zero deposit capacity while the fixed staking contract is paused; otherwise it applies the inherited open/allowlist deposit rule. It changes no authority or balances.

[Feynman: GroveCompounder._min]
This returns the smaller of two numbers and has no authority effect.

[Feynman: GroveCompounder.claimRewards]
This lets strategy management ask the fixed staking contract to send accrued GROVE to the strategy. The rewards remain in the strategy and no caller-selected recipient exists.

[Inversion: GroveCompounder.claimRewards]
1. Call as keeper: the management-only guard rejects it. 2. Call through a contract controlled by management's EOA: the contract address is not the stored management address. 3. Reenter from staking: staking is not management and cannot pass the guard.

[Feynman: GroveCompounder._claimRewards]
This asks the fixed staking contract to pay accrued rewards to the strategy. It is reachable through management's manual claim, keeper/management's manual auction kick for GROVE, or keeper/management's report.

[Feynman: GroveCompounder.kickAuction]
This lets a keeper or management choose a token held by the strategy and send its full balance to the configured Auction when the balance exceeds the GROVE sale threshold. If the chosen token is GROVE, the strategy first claims pending GROVE. The chosen token cannot be USDS, but it is otherwise not restricted to GROVE.

[Socratic: GroveCompounder.sol:158-170 — why?]
Why does the keeper choose any token instead of only GROVE? The implicit belief is that any other token held by the strategy and enabled by Auction governance is safe for a keeper to liquidate into USDS.

[Inversion: GroveCompounder.kickAuction]
1. Keeper passes USDS: `_kickAuction` rejects the strategy asset before transfer. 2. Keeper passes a random unenabled token: the transfer and subsequent Auction revert occur atomically, so no token remains stuck. 3. Keeper passes a valuable non-USDS token that Auction governance has enabled: the full balance is moved into a sale even though the automated report branch would only sell GROVE; this is retained as a lead because no in-scope path establishes such inventory or a loss to an unauthorized recipient.

[Feynman: GroveCompounder._kickAuction]
This refuses to sell principal, checks that an auction address exists, transfers the complete selected token amount to that auction, and asks the auction to start selling it. It relies on receiver and wanted-token checks performed earlier when management selected the auction.

[Socratic: GroveCompounder.sol:174-180 — why?]
Why are the Auction receiver and wanted token not checked again just before value moves? The implicit belief is that those properties cannot change after configuration or that Auction governance is fully trusted forever.

[Inversion: GroveCompounder._kickAuction]
1. Set the auction receiver to an attacker after strategy configuration, then have a keeper kick: the imported Auction permits governance to change `receiver` when no auction is active, so subsequent USDS payment goes to the new receiver. 2. Pass the USDS asset as the token being sold: the local asset check blocks it. 3. Set `auction` to an EOA or incompatible contract: management's configuration-time `receiver()` and `want()` calls revert before storage is written.

[Feynman: GroveCompounder.setMinAmountToSell]
This lets management change the minimum GROVE inventory required before a sale. The only first-party external writer is management-restricted.

[Inversion: GroveCompounder.setMinAmountToSell]
1. Call as keeper: rejected by management guard. 2. Reach the internal setter through another public function: no such entry exists. 3. Reenter during this setter: it makes no external call and the guard checks the original caller.

[Feynman: GroveCompounder.setUniV3Fees]
This lets management select the Uniswap V3 fee tier used for GROVE-to-USDC sales. The internal mapping writer has no weaker first-party external route.

[Inversion: GroveCompounder.setUniV3Fees]
1. Call as keeper: rejected. 2. Call an inherited generic fee setter: none is exposed. 3. Use a function-selector collision through fallback: the compiled Grove and TokenizedStrategy ABI selector sets have no collision.

[Feynman: GroveCompounder.setAuction]
This lets management choose an Auction after checking that it currently sends proceeds to the strategy and currently receives USDS; management can clear it only after direct-swap mode is selected.

[Socratic: GroveCompounder.sol:209-216 — why?]
Why is a one-time receiver check sufficient? It assumes the Auction's separate governance cannot or will not later redirect the receiver.

[Inversion: GroveCompounder.setAuction]
1. Non-manager supplies a malicious auction: rejected before external validation calls. 2. Manager supplies zero while auction mode is live: rejected. 3. A previously valid Auction changes receiver after setup: the strategy storage remains unchanged and later kicks do not repeat validation; recorded as a bounded lead.

[Feynman: GroveCompounder.setUseAuction]
This lets management switch between Auction and Uniswap/PSM reward-sale routes. Switching into Auction mode requires a nonzero configured auction.

[Inversion: GroveCompounder.setUseAuction]
1. Keeper switches mode: rejected. 2. Management switches to Auction with address zero: rejected. 3. Attacker makes the configured Auction unusable after the mode switch: this can deny reporting but requires control or failure of the external Auction, not a local authority bypass.

[Feynman: GroveCompounder.setReferral]
This lets management change the referral number supplied on future staking deposits; it cannot redirect assets or grant a role.

[Inversion: GroveCompounder.setReferral]
1. Keeper changes it: rejected. 2. User selects it through deposit calldata: deposit has no referral argument. 3. Reenter from staking to change it: staking is not management.

[Feynman: ISwapRouterWithFactory]
This interface says a router can reveal which factory it uses. It defines no local state or role.

[Feynman: ISwapRouterWithFactory.factory]
This returns the router's factory address and changes nothing.

[Feynman: UniswapV3SwapSimulator]
This stateless helper reads an arbitrary router's factory and pool, then computes a quote without executing a token swap. It holds no roles or funds.

[Feynman: UniswapV3SwapSimulator.simulateExactInputSingle]
This finds the requested pool and walks its current price ranges to estimate how many output tokens a stated input would obtain. It is read-only, so permissionless access cannot change protocol state.

[Inversion: UniswapV3SwapSimulator.simulateExactInputSingle]
1. Supply a malicious router whose `factory()` attempts a write: the static read context prevents state changes. 2. Supply a fake pool: the caller can obtain a fake quote but cannot mutate this stateless library or the oracle's fixed router choice. 3. Reenter the caller through pool reads: static context prevents state mutation.

[Feynman: UniswapV3SwapSimulator.getPool]
This asks the supplied router for its factory and asks that factory for the pool matching the two tokens and fee. It is private and has no independent external entry.

[Feynman: Simulate]
This stateless helper reproduces Uniswap V3's price traversal using data read from a selected pool. It does not store roles, approvals, or balances.

[Feynman: Simulate.simulateSwap]
This starts from the pool's current price, tick, and liquidity, repeatedly walks toward the caller's price limit, and totals the corresponding input and output amounts. It is read-only and cannot grant authority or move tokens.

[Feynman: Simulate.nextInitializedTickWithinOneWord]
This searches one 256-position section of the pool's tick map for the next initialized boundary in the chosen direction. It is private and changes nothing.

[Feynman: Simulate.tickBitmapPosition]
This converts a tick number into the map section and bit position where that tick is recorded. It is private and changes nothing.

[Feynman: GroveCompounderAprOracle]
This contract estimates staking APR from fixed staking data and configurable Uniswap pricing sources. One management address controls every mutable pool choice and can replace itself in one transaction; public callers can only read quotes.

[Feynman: GroveCompounderAprOracle.constructor]
Deployment atomically assigns the deployer as manager and loads four fixed V4 pool identifiers. There is no separate initializer that another caller can front-run.

[Inversion: GroveCompounderAprOracle.constructor]
1. Front-run an initializer: none exists. 2. Deploy through an attacker-controlled factory: the factory is manager only if the intended deployment explicitly uses it. 3. Reenter during construction: no external calls occur.

[Feynman: GroveCompounderAprOracle.onlyManagement]
This gate allows a call to continue only when the immediate caller equals the single stored management address.

[Feynman: GroveCompounderAprOracle._onlyManagement]
This compares the immediate caller with the stored manager and rejects every mismatch.

[Inversion: GroveCompounderAprOracle._onlyManagement]
1. Call through an intermediary: the intermediary, not its controller, is checked. 2. Use `tx.origin`: the contract does not use it. 3. Reenter from the fixed Uniswap factory during a setter: the factory address does not equal management unless management deliberately assigned that address.

[Feynman: GroveCompounderAprOracle.aprAfterDebtChange]
This public read estimates APR after adding or subtracting a hypothetical debt amount. It reads pricing and staking state but writes no configuration, roles, or balances.

[Feynman: GroveCompounderAprOracle.setManagement]
This lets the current manager immediately replace itself with any nonzero address. There is no acceptance step, but an arbitrary caller cannot nominate itself.

[Socratic: GroveCompounderAprOracle.sol:135-139 — why?]
Why is management transferred in one step? The implicit belief is that the current manager supplies the intended address correctly and does not need the successor to prove control before authority changes.

[Inversion: GroveCompounderAprOracle.setManagement]
1. Attacker races a legitimate transfer: only the current manager's transaction passes, so ordering does not help. 2. Current manager passes zero: rejected. 3. Current manager passes a wrong nonzero address: authority can be lost, but that is manager self-harm rather than an unauthorized caller escalation.

[Feynman: GroveCompounderAprOracle.setUniV3Fee]
This lets management change the V3 fee tier only if the fixed router's factory currently lists a GROVE/USDC pool for that tier.

[Inversion: GroveCompounderAprOracle.setUniV3Fee]
1. Non-manager chooses a manipulable pool: rejected. 2. Reenter from the fixed factory: factory is not manager under the normal role assignment. 3. Factory removes the pool after configuration: pricing falls back to V4; no caller gains configuration authority.

[Feynman: GroveCompounderAprOracle.setUniV4Pool]
This lets management replace all V4 candidates with one nonzero pool identifier and an asserted token orientation.

[Inversion: GroveCompounderAprOracle.setUniV4Pool]
1. Non-manager replaces the set: rejected. 2. Manager passes zero: rejected. 3. Manipulate the public pool after configuration: this may affect price correctness but does not bypass the manager guard.

[Feynman: GroveCompounderAprOracle.setUniV4Pools]
This lets management replace the candidate list using paired pool identifiers and token-orientation flags. The internal helper requires a nonempty, equal-length, nonzero, duplicate-free list.

[Inversion: GroveCompounderAprOracle.setUniV4Pools]
1. Non-manager supplies arrays: rejected before the helper. 2. Use mismatched arrays to create uninitialized orientation entries: rejected. 3. Include the same pool twice to amplify one vote: rejected.

[Feynman: GroveCompounderAprOracle.addUniV4Pool]
This lets management append one nonzero pool not already in the list.

[Inversion: GroveCompounderAprOracle.addUniV4Pool]
1. Non-manager appends: rejected. 2. Add zero: rejected. 3. Add a duplicate with different orientation: duplicate identity is rejected regardless of orientation.

[Feynman: GroveCompounderAprOracle.removeUniV4Pool]
This lets management remove one candidate while preserving at least one, replacing the removed slot with the last entry.

[Inversion: GroveCompounderAprOracle.removeUniV4Pool]
1. Non-manager removes: rejected. 2. Remove the last remaining pool: rejected. 3. Use an out-of-range index to corrupt storage: rejected.

[Feynman: GroveCompounderAprOracle.uniV3Pool]
This publicly reveals the V3 pool selected by the stored fee tier and changes nothing.

[Feynman: GroveCompounderAprOracle.uniV4PoolCount]
This publicly reveals how many V4 candidates are configured and changes nothing.

[Feynman: GroveCompounderAprOracle.uniV4Pool]
This publicly reveals one candidate's identifier and orientation and changes nothing.

[Feynman: GroveCompounderAprOracle.groveUsdcV4PoolId]
This compatibility getter reveals the first candidate's identifier and changes nothing.

[Feynman: GroveCompounderAprOracle.v4GroveIsToken0]
This compatibility getter reveals the first candidate's asserted GROVE orientation and changes nothing.

[Feynman: GroveCompounderAprOracle.bestUniV4Pool]
This publicly computes and returns the best acceptable configured V4 candidate and changes nothing.

[Feynman: GroveCompounderAprOracle.selectedUniV4Pool]
This publicly returns the selected V4 candidate and its computed price and changes nothing.

[Feynman: GroveCompounderAprOracle._grovePrice]
This first tries a quote from the configured V3 fee tier, then falls back to the selected V4 candidate, and rejects the request if neither route supplies a usable price. No external caller can directly change the configured sources through this helper.

[Feynman: GroveCompounderAprOracle._v3PoolHasUsableLiquidity]
This checks that the factory currently lists the configured V3 pool and that the pool meets fixed liquidity and USDC-balance thresholds. It changes nothing.

[Feynman: GroveCompounderAprOracle._v4GrovePrice]
This converts a V4 square-root price into USDS-scaled GROVE value using the manager-provided orientation flag. It changes nothing.

[Feynman: GroveCompounderAprOracle._selectedV4Pool]
This reads every configured V4 candidate, ignores unusable ones, computes the median price, and returns the highest-liquidity candidate within ten percent of that median. It changes nothing.

[Feynman: GroveCompounderAprOracle._medianPrice]
This sorts candidate prices in temporary memory and returns their middle value, averaging the middle pair for an even count. It changes no contract state.

[Feynman: GroveCompounderAprOracle._withinV4PriceDeviation]
This checks whether one price lies within ten percent of a reference price and changes nothing.

[Feynman: GroveCompounderAprOracle._setUniV4Pools]
This clears the old V4 candidate list and writes a new nonempty list after checking lengths, nonzero identifiers, and uniqueness. Its only first-party external caller is management-gated.

[Inversion: GroveCompounderAprOracle._setUniV4Pools]
1. Reach it directly: it is internal. 2. Reach it through another unguarded external method: only the management-gated bulk setter calls it. 3. Reenter midway through list replacement: the helper makes no external calls, so no observer can enter during partial state.

[Feynman: GroveCompounderAprOracle._hasUniV4Pool]
This scans the stored list and reports whether an identifier is already present. It changes nothing.

[Feynman: GroveCompounderAprOracle._uniV3Pool]
This resolves the stored fee tier to the current factory-listed V3 pool and changes nothing.

[Feynman: GroveCompounderAprOracle._uniV3PoolForFee]
This asks the fixed router's factory for the GROVE/USDC pool at a supplied fee tier and changes nothing.

[Feynman: GroveCompounderAprOracle._quoteToken1ForToken0]
This converts an amount of the first token into the corresponding second-token amount at a supplied square-root price and changes nothing.

[Feynman: GroveCompounderAprOracle._quoteToken0ForToken1]
This converts an amount of the second token into the corresponding first-token amount at a supplied square-root price and changes nothing.

## Targeted imported-authority verification

[Feynman: BaseStrategy]
This imported base delegates standard vault operations to one fixed TokenizedStrategy implementation and stores all standard roles in a dedicated storage slot belonging to each strategy instance. Its local wrappers call the strategy's internal hooks only when the immediate caller is the strategy itself.

[Feynman: BaseStrategy._initialize]
This invokes the fixed implementation during construction so the new strategy instance stores its asset, manager, fee recipient, and keeper before deployment completes. No external initialization window exists.

[Feynman: BaseStrategy.fallback]
This forwards unknown calls into the fixed TokenizedStrategy code while keeping the strategy's storage and the original external caller. As a result, TokenizedStrategy's own guards evaluate the true caller against this strategy's role storage.

[Socratic: BaseStrategy.sol:509 — why?]
Why does forwarding not expose privileged internal callbacks? The answer is that the callbacks are implemented on the strategy itself and independently require the immediate caller to equal the strategy; a delegate call cannot make an arbitrary EOA become `address(this)`.

[Inversion: BaseStrategy.fallback]
1. Invoke the implementation's `initialize` selector through fallback after deployment: the strategy's asset slot is already nonzero, so it reverts as initialized. 2. Invoke a privileged TokenizedStrategy setter through fallback: delegate call preserves the attacker as `msg.sender`, so the role guard rejects it. 3. Exploit a four-byte collision with a weaker Grove function: compiled selector comparison found no overlap between Grove's explicit ABI and the TokenizedStrategy interface ABI.

[Feynman: TokenizedStrategy.initialize]
This fills a strategy instance's dedicated storage exactly once and rejects a zero manager or zero fee recipient. The BaseStrategy constructor calls it atomically before the new strategy becomes callable.

[Feynman: TokenizedStrategy.constructor]
This permanently marks the standalone implementation's own asset slot with address(1), preventing anyone from initializing the implementation itself.

[Inversion: TokenizedStrategy.initialize]
1. Initialize the implementation directly: its constructor-set asset makes the call revert. 2. Initialize Grove before its constructor: no external call can target an address whose creation has not completed. 3. Initialize Grove after deployment through fallback: BaseStrategy already set its asset, so the one-time guard rejects it.

[Feynman: TokenizedStrategy.requireManagement]
This accepts only the stored management address supplied as the original caller.

[Feynman: TokenizedStrategy.requireKeeperOrManagement]
This accepts only the stored keeper or management address supplied as the original caller.

[Feynman: TokenizedStrategy.requireEmergencyAuthorized]
This accepts only the stored emergency administrator or management address supplied as the original caller.

[Feynman: TokenizedStrategy.report]
This permits keeper or management to run strategy reporting under a reentrancy guard, then calls the strategy back as itself to reach the harvest hook.

[Inversion: TokenizedStrategy.report]
1. Depositor calls directly: rejected by keeper guard. 2. Keeper reenters during external reward handling: rejected by the entered-state check. 3. External protocol calls the callback directly: rejected because only the strategy's own address can call it.

[Feynman: TokenizedStrategy.tend]
This permits keeper or management to deploy idle funds through a self-only strategy callback under the shared reentrancy guard.

[Feynman: TokenizedStrategy.shutdownStrategy]
This permits management or the emergency administrator to permanently stop new deposits.

[Feynman: TokenizedStrategy.setPaused]
This permits management or the emergency administrator to pause user operations, but only management can unpause them.

[Feynman: TokenizedStrategy.emergencyWithdraw]
This permits management or the emergency administrator to invoke the strategy's rescue hook only after pause or shutdown and under the reentrancy guard.

[Feynman: TokenizedStrategy.setPendingManagement]
This permits current strategy management to nominate a nonzero successor without immediately transferring control.

[Feynman: TokenizedStrategy.acceptManagement]
This transfers strategy management only when the immediate caller is the stored pending successor, then clears the pending slot.

[Inversion: TokenizedStrategy.acceptManagement]
1. Front-run acceptance from another address: rejected by exact-address comparison. 2. Reenter after acceptance: pending address is cleared. 3. Nominate zero to lock management: the nomination setter rejects zero.

[Feynman: TokenizedStrategy.setKeeper]
This permits strategy management to replace or clear the operational keeper. A zero keeper grants nobody because no transaction has a zero sender.

[Feynman: TokenizedStrategy.setEmergencyAdmin]
This permits strategy management to replace or clear the emergency administrator. A zero value grants nobody.

[Feynman: BaseHealthCheck]
This imported base adds management-controlled health limits and deposit allowlisting, and it retains self-only report callbacks. No weaker setter writes the same configuration.

[Feynman: BaseHealthCheck.harvestAndReport]
This self-only callback invokes Grove's internal harvest and checks the result before the inherited report records it.

[Feynman: BaseHealthCheck.availableDepositLimit]
This permits deposits for everyone when open, otherwise only when the address used for the inherited deposit-limit check is allowlisted. A caller depositing to an allowed receiver gives the shares to that receiver, so it does not obtain unauthorized ownership.

[Feynman: Auction]
This imported external venue holds tokens for Dutch-style sales and sends payment in its wanted token to a separately stored receiver. Its governance may change that receiver while no auction is active.

[Feynman: Auction.setReceiver]
This permits Auction governance to replace the payment recipient when no sale is currently active. Grove does not repeat its receiver check after its manager initially selects the Auction.

[Feynman: Auction.kick]
This starts a sale for a token previously enabled by Auction governance, using the Auction's current token balance. Grove calls it after transferring the selected token.

[Inversion: Auction.setReceiver]
1. Permissionless attacker calls it: governance guard rejects the call. 2. Auction governance changes receiver before Grove's next kick: allowed, and Grove does not detect it. 3. Governance changes receiver during an active auction: the no-active-auction check rejects it, but changing it between auctions is sufficient for the lead sequence.

## Access-control map and consistency result

- Strategy management: initialized atomically to Grove's deployer by BaseStrategy; protected by exact caller equality; later transfers use the imported two-step pending/accept flow. First-party management-only functions are `claimRewards`, `setMinAmountToSell`, `setUniV3Fees`, `setAuction`, `setUseAuction`, and `setReferral`.
- Strategy keeper: initialized to Grove's deployer; later set only by management. It may call imported `report`/`tend` and first-party `kickAuction`. It cannot invoke first-party management setters or imported management/emergency-only methods unless it also holds those roles.
- Strategy emergency administrator: set only by management. It may pause/shutdown and rescue under imported state preconditions, but cannot unpause or change first-party sale configuration.
- Self-only callbacks: `deployFunds`, `freeFunds`, `harvestAndReport`, `tendThis`, and `shutdownWithdraw` require `msg.sender == address(this)`. Their reachable fallback entry points apply the appropriate accounting, role, and reentrancy checks first.
- Oracle management: constructor assigns the deployer; all seven configuration writers use the same exact-address modifier. `setManagement` is one-step but rejects zero. There is no initializer, pending role, secondary writer, or weaker helper route.
- Auction governance: outside first-party control. The strategy verifies `receiver` and `want` when management selects an Auction, but the imported Auction permits its governance to change `receiver` later.
- Initialization: Grove initializes within construction, the TokenizedStrategy implementation disables its own initializer in its constructor, and the oracle has no initializer.
- Selector/callback boundary: no selector overlap was found between Grove's explicit compiled methods and the imported TokenizedStrategy interface; privileged internal callbacks remain self-only.

No concrete untrusted-caller path was found that grants a role, changes a protected configuration variable, reaches a privileged fund-moving callback, or redirects principal.

## Structured output

LEAD | contract: GroveCompounder | function: kickAuction | bug_class: overbroad-keeper-token-scope | group_key: GroveCompounder | kickAuction | overbroad-keeper-token-scope
code_smells: The automated report path auctions only `REWARDS_TOKEN`, but the keeper-facing function accepts any `_token`, reads its full strategy balance, and `_kickAuction` excludes only `asset`; there is no strategy-side reward-token allowlist. The sale threshold also reads `minAmountToSell[REWARDS_TOKEN]` for every selected token rather than a per-token threshold.
guard_gap: Missing `_token == REWARDS_TOKEN` restriction or management-maintained allowlist, whereas the parallel `_harvestAndReport` auction branch hard-codes `REWARDS_TOKEN`.
partial_sequence: Auction governance enables token X; token X with 18 decimals and balance greater than 5,000e18 is present at the strategy; a keeper calls `kickAuction(X)`; Grove transfers the entire X balance to Auction and starts its sale.
description: A keeper can liquidate non-principal token inventory beyond the automated GROVE mandate, but this remains unverified as an exploit because no in-scope path establishes valuable token X inventory and a valid Auction sends sale proceeds back to the strategy.

LEAD | contract: GroveCompounder | function: _kickAuction | bug_class: stale-external-authority-validation | group_key: GroveCompounder | _kickAuction | stale-external-authority-validation
code_smells: `setAuction` checks `Auction.receiver() == address(this)` only when management configures the venue, while the imported Auction exposes governance-only `setReceiver` between active auctions; `_kickAuction` moves rewards without revalidating the receiver.
guard_gap: Missing runtime `require(Auction(auction).receiver() == address(this))` immediately before the reward transfer; the parallel configuration path has this guard only once.
partial_sequence: Strategy management configures Auction A while `A.receiver == Grove`; later A's governance calls `setReceiver(attacker)` while no auction is active; keeper calls `kickAuction(REWARDS_TOKEN)`; Grove transfers GROVE to A and kicks; a taker buys it and Auction pulls USDS from the taker to `attacker`, not Grove.
description: A later Auction-governance receiver change can redirect future reward-sale proceeds, but this is a lead because exploiting it requires control or compromise of an out-of-scope privileged Auction-governance role whose trust assumption was not established in scope.

Summary: 0 FINDINGs; 2 LEADs.
