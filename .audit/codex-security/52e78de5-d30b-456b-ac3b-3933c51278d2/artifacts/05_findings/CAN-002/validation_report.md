# Validation Report: CAN-002 — Primary APR path trusts a manipulable V3 current-state quote

## Identity and disposition

- Candidate ID: `CAN-002`
- Instance key: `oracle-spot-v3:src/periphery/GroveCompounderAprOracle.sol:228`
- Discovery ledger/seed row: `W01-F009` (centralized candidate ledger: `CAN-002`)
- Advisory/source reference: none; repository discovery candidate
- Root control and sink: `src/periphery/GroveCompounderAprOracle.sol:211-245`, especially the first-positive return at line 228
- Affected locations: `src/periphery/GroveCompounderAprOracle.sol:109-132,211-245`; `src/libraries/UniswapV3SwapSimulator.sol:23-46`; `src/libraries/UniswapV3SwapSimulatorCore.sol:61-100`
- Disposition: **deferred**
- Survives validation: **uncertain** (mechanism survives; security-sensitive consumer/realized harm is unproved)
- Confidence: **medium (0.68 overall; high for the in-scope quote-control mechanism, low-to-medium for capital impact)**
- Validation method: exact static source/control/sink trace, bounded repository/deployment adjacency pass, production JSON-RPC state checks, and an executed mock-backed Foundry mechanism test

## Validation rubric

- [x] Attacker market control: the pinned V3 pool implementation exposes external `mint` and `swap`; permissionless LP/trader capital can alter live price/liquidity.
- [x] V3 priority/reachability and thresholds: a qualifying positive V3 quote returns before V4; current production state and activation thresholds were measured.
- [x] Price-integrity controls: the exact path was checked for a TWAP, historical observation, independent-source comparison, and meaningful price-deviation bound; none exists before acceptance.
- [ ] Concrete downstream consumer/impact: no deployed allocator registration or state-changing consumer was established by the bounded adjacency pass.
- [x] Dynamic/static counterevidence: the mechanism test, current zero-liquidity state, deploy artifacts, tests, cap, and missing consumer were evaluated without treating absence as safety proof.

## Exact hypothesis and harm gate

**Exact bug.** `_grovePrice()` reads a simulated one-GROVE output from the V3 pool's current `slot0`, current active liquidity, fee, tick spacing, bitmap, and ticks, then accepts the first positive output at `GroveCompounderAprOracle.sol:228`. The closest checks at lines 239-245 only require `liquidity >= 1e12` and a raw USDC balance of `1,000e6`; the final APR cap at line 132 rejects only values above 50%. None authenticates the price over time or against an independent source.

**Observable mechanism difference.** Holding both eligibility checks and staking inputs constant, changing only current `slot0` changed the externally returned APR from `31,220,639` to `124,882,559` (4.00x) while both results remained under `MAX_EXPECTED_APR`.

**Exact mechanism assertion.** `assertGt(manipulatedApr, baselineApr * 3)` plus `assertLe(manipulatedApr, MAX_EXPECTED_APR)`.

**Claimed harm.** A security-sensitive allocator consumes the manipulated APR and routes or retains materially more capital than it would under an integrity-protected price, causing misallocation, loss, or transaction denial.

The test asserts the mechanism, not that harm. No concrete allocator was found, so the impact hard gate is not satisfied and this is not tagged `[POC-PASS]` for the candidate's financial consequence.

## Preserved source / control / sink / impact tuple

| Element | Exact evidence |
|---|---|
| Source | Permissionless V3 `mint`/`swap` activity can change the live pool state read by the oracle. The pinned `UniswapV3Pool.sol:464-470,605-621` entrypoints are external and do not authenticate the caller; capital/callback payment is required. |
| Reachable entrypoint | `GroveCompounderAprOracle.aprAfterDebtChange` is external and ungated at lines 109-132. It calls `_grovePrice()` at line 118. |
| Closest control | `_v3PoolHasUsableLiquidity()` at lines 239-245 checks active-liquidity units and raw USDC balance. Line 132 caps final APR at 50%. These scope values but do not prove price integrity. |
| Root control/sink | Lines 211-229 call the live-state simulator and return the first positive V3 output multiplied to 1e18 scale. V4 is consulted only after V3 failure/nonpositive output at lines 232-236. |
| Shared state read | `UniswapV3SwapSimulatorCore.sol:69-95` initializes the quote from current `slot0()`, `liquidity()`, `fee()`, and `tickSpacing()`; no observation/TWAP is read. |
| Downstream sink | Line 131 annualizes the accepted price into the external APR. A state-changing allocator consumer is not present in this repository or established by deploy/config evidence. |
| Conditional impact | A same-transaction or stale-before-arbitrage consumer could misallocate or revert. Capital amount, victim loss, and attacker profitability remain unmeasured because the consumer is missing. |

## Reachability and bounds

### F1 — reachability

- Mechanism path: **PASS**. Any caller can call `aprAfterDebtChange`; when the V3 checks pass, the V3 simulation is evaluated first and a positive result bypasses V4.
- Harm path: **INCOMPLETE**. No in-scope/deployed state-changing consumer was found.
- Current dynamic state: at block `25,583,834`, the sole factory pool (fee `10000`) had `liquidity = 0` and USDC balance `71` raw units, so the V3 branch was dormant at that snapshot.
- Operational path: the state is not immutable. A permissionless LP/trader can add active liquidity and fund the pool balance; at least `1,000e6` raw USDC must be present, alongside sufficient GROVE/liquidity. The capital and unwind cost for a real sub-cap distortion were not measured.

### F2 — mathematical bounds

- The final bound is broad: `MAX_EXPECTED_APR = 5e17` (50%). Any manipulated positive APR at or below it is accepted.
- The executed test produced a 4x APR amplification with unchanged passing thresholds and a manipulated result of `124,882,559`, far below the cap.
- This establishes that the checks are not a mathematical price bound. It does **not** establish real-market manipulation cost because the test uses controlled mock state.

## Dynamic validation

### PoC Attempt

- PoC Required: YES for the claimed allocator harm
- PoC Class: integration
- Attempted: YES — an offline focused unit/mechanism test against the exact checked-out oracle was compiled and executed
- PoC Not Attempted Because: `EXTERNAL_DEPENDENCY_NO_FORK_OR_ADDRESS` for the harm assertion; no verified deployment of the checked-out Grove oracle plus a concrete state-changing allocator consumer/address was established
- Test File: `artifacts/05_findings/CAN-002/validation_artifacts/worktree/src/test/CAN002Validation.t.sol`
- Command: `forge test --match-test test_CAN002_currentV3StateDirectlyControlsAcceptedApr -vvv`

### Execution Result

- Compiled: YES (1 successful compile run; Solc 0.8.28)
- Result: PASS (mechanism assertion only)
- Fuzz variant: NOT_APPLICABLE — the candidate is deferred on missing integration impact, and no harm-level PoC exists to fuzz
- Output: baseline APR `31,220,639`; manipulated APR `124,882,559`; amplification `40,000 bps`; 1 passed, 0 failed
- Evidence tag: `[CODE-TRACE]` with an executed `[MOCK]` mechanism test; **not** `[POC-PASS]` for harm
- Log: `artifacts/05_findings/CAN-002/validation_artifacts/forge_test.log`

The test holds `liquidity = 1e30`, USDC balance at the exact minimum, and staking inputs constant. Only current `slot0` changes from `Q96` to `Q96/2`. V4's `getLiquidity` is mocked to revert; both calls still succeed, confirming V3 priority when its quote is positive.

## Bounded production/config adjacency pass

The pass searched production files, tests, deploy scripts, broadcast artifacts, README, and package/import references for `GroveCompounderAprOracle`, `aprAfterDebtChange`, oracle registration, allocator, and meta-vault consumers.

- Only the oracle and tests call/reference `aprAfterDebtChange`; no non-test consumer exists in this repository.
- `README.md:66` explicitly says tests are written without integration with a funding meta vault.
- `script/DeployStrategyAndOracle.s.sol:24` deploys the oracle, but lines 30-33 comment out strategy deployment and the script performs no allocator/oracle registration.
- `broadcast/DeployStrategyAndOracle.s.sol/1/run-latest.json:6-7` records `SparkCompounderAprOracle`, not the checked-out Grove oracle. Bytecode exists at the listed historical addresses, but the current `uniV3Pool()` selector reverted at each checked address.
- Current factory state exposes only the fee-10000 pool; fee-500 and fee-3000 pools are zero addresses.

The missing consumer/deployment is a proof gap, not counterevidence that a consumer does not exist elsewhere. Per the validation rule, the row is deferred rather than suppressed.

## Evidence audit

| Claim | Evidence source | Tag | Can support suppression/refutation? |
|---|---|---|---|
| V3 quote begins from current pool state and is returned first | Checked-out oracle/simulator exact lines | `[CODE]` | YES |
| Pinned pool `mint` and `swap` are permissionless subject to payment/callback | Pinned vendored Uniswap V3 source at revision `d55e297...` | `[CODE]` | YES |
| Current sole V3 pool failed both eligibility thresholds | JSON-RPC at block 25,583,834 | `[PROD-ONCHAIN]` | YES, but only for that snapshot |
| Historical script/broadcast addresses are not the checked-out Grove oracle interface | Repository broadcast plus JSON-RPC bytecode/call checks | `[CODE]` + `[PROD-ONCHAIN]` | YES for those addresses |
| A 2x `sqrtPriceX96` reduction produces a 4x accepted APR with controls fixed | Executed Foundry controlled-state test | `[MOCK]` | NO for refutation and NO for harm; mechanism support only |
| No allocator consumer was found in the bounded adjacency pass | Repository-wide search, README, deploy/config artifacts | `[CODE]` | NO; absence is an explicit proof gap |

## RAG / historical precedent

- Historical precedent: **YES**.
- Similar patterns: OpenZeppelin's analysis of the bZx flash-loan incidents describes market manipulation against spot/reserve-derived sources; its oracle guidance warns that directly querying AMM pools is manipulable and describes Uniswap V3 TWAP consultation. OpenZeppelin's Fei postmortem also documents a vulnerable allocation calculation that consumed a current Uniswap price.
- Sources: `https://blog.openzeppelin.com/flash-loans-and-the-advent-of-episodic-finance`, `https://blog.openzeppelin.com/secure-smart-contract-guidelines-the-dangers-of-price-oracles`, `https://blog.openzeppelin.com/fei-post-mortem`
- Pattern confidence: **HIGH** for the generic live-AMM-price manipulation class; historical precedent does not fill this candidate's missing consumer or economics.

## Counterevidence and remaining uncertainty

1. **Current branch inactivity `[PROD-ONCHAIN]`:** zero active liquidity and 71 raw USDC units mean the primary path did not qualify at the observed block.
2. **Activation cost `[CODE]`:** the attacker must capitalize active liquidity and bring raw USDC balance to at least 1,000 USDC; this is not a costless `slot0` write.
3. **Final cap `[CODE]`:** APR above 50% reverts, limiting accepted inflation but also permitting sub-cap manipulation and potential denial.
4. **No verified current deployment/consumer `[CODE]/[PROD-ONCHAIN]`:** historical addresses in this repository correspond to a Spark oracle interface, and no allocator is registered here.
5. **Economics unresolved:** same-transaction manipulation/unwind cost, allocator action, attacker benefit, TVL moved, and victim loss are not quantified.

These facts reduce likelihood and prevent a reportable impact conclusion. They do not prove an integrity control exists.

## Devil's advocate and chain/enabler check

**What would make this exploitable?** A verified deployment of this Grove oracle, a security-sensitive allocator that reads it during a state-changing debt decision, a capitalized V3 state passing both thresholds, a sub-50% distorted APR sufficient to cross the allocator's decision boundary, and an unwind/position that monetizes or causes measurable loss.

The centralized inventory was checked for an enabler that creates the missing consumer. `CAN-007` could compound APR manipulation through the denominator, but it does not create a downstream allocator or deployment. No other candidate supplies that missing integration postcondition. Therefore there is no basis to promote impact, and also no chain-based basis to refute the mechanism.

## Severity facts

- Current disposition has **no final report severity** because harm reachability is deferred.
- If a real allocator uses the value for material debt routing, the canonical threat model supports **Medium** for unsafe APR with realistic liquidity and consumer preconditions.
- **High** would require proof that the manipulation directly causes a large allocation loss; no TVL, attack cost, attacker profit, victim loss, or affected-user count is established.
- With no security-sensitive consumer, this is an integration/API weakness rather than demonstrated fund loss, consistent with the threat model's Low/deferred boundary.

## Minimal next step

Identify the deployed address and exact state-changing consumer/allocator registration for the checked-out Grove oracle. On a pinned mainnet fork, execute: capitalize/manipulate the fee-10000 pool -> invoke the consumer's allocation transaction -> unwind -> assert the exact misallocated debt or victim loss and compute manipulation cost/profit. Until then, preserve `CAN-002` as **deferred**.

## Validation closure

| Ledger row id | Instance key | Advisory/source | Seed anchor | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|---|---|
| `CAN-002` / `W01-F009` | `oracle-spot-v3:src/periphery/GroveCompounderAprOracle.sol:228` | Repository discovery; no advisory | `src/periphery/GroveCompounderAprOracle.sol:109-393` | `src/periphery/GroveCompounderAprOracle.sol:211-245` | External `aprAfterDebtChange`; permissionless V3 live state | First-positive V3 return at 228, annualization at 131; only raw thresholds/cap | `deferred` | Current pool dormant; no verified checked-out deployment or concrete allocator consumer; real economics unmeasured | `uncertain` |
