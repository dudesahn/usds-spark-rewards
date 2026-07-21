# Validation: CAN-004 — Unbounded V3 tick traversal can exhaust gas before fallback

## Disposition

**DEFERRED (likely false positive for the pinned/default deployment; medium confidence, 0.74).**

The unbounded-loop mechanism is real in source, and permissionless LPs can construct zero-net initialized ticks. The claimed harmful postcondition did not reproduce: a conservative 2,800-tick model consumed 45,027,130 gas yet the exact oracle call succeeded under the pinned 60,000,000 block limit, and the same call still reached the production V4 fallback with only 5,000,000 gas. However, the maximum dense topology used a pool model, so the mock-evidence rule prevents a final `suppressed`/refuted disposition. No in-repository consumer demonstrates security-sensitive availability harm, and no smaller-spacing GROVE/USDC pool existed at the pinned block.

## Candidate identity

- Candidate ID: `CAN-004`
- Instance key: `denial-of-service:src/libraries/UniswapV3SwapSimulatorCore.sol:98`
- Coverage ledger row: `COV-007`
- Root control and sink: `src/libraries/UniswapV3SwapSimulatorCore.sol:98-179`
- Entrypoint wrapper: `src/libraries/UniswapV3SwapSimulator.sol:23-46`
- Reachable caller: `src/periphery/GroveCompounderAprOracle.sol:211-236`
- Advisory/source seed: none

## Validation rubric (fixed before validation)

- [x] Attacker influence: production-fork mints proved a permissionless LP can create initialized, zero-net tick boundaries and make active liquidity equal the oracle's `1e12` threshold; donating the missing pool balance costs about 1,000 USDC.
- [ ] Resource bound: there is no explicit iteration cap, but the configured 1% pool has tick spacing 200, the direction is fixed, TickMath has a finite range, and the input is fixed at one GROVE. These are effective bounds for the pinned configuration.
- [ ] Gas propagation: the asserted failure did not occur. EIP-150's retained gas plus `try/catch` was enough to execute the production V4 fallback after the modeled V3 quote exhausted or consumed its subcall budget at both 5M and 10M outer gas.
- [ ] Realistic qualifying state: a small qualifying topology was constructed on the deployed pool bytecode and 250 production ticks were measured, but the full 2,800-tick state was modeled rather than minted end to end. Smaller-spacing GROVE/USDC pools (fees 100/500/3000) were absent at the pinned block.
- [ ] Consumer harm: the repository deploys/exports the oracle but contains no allocator or other production consumer of `aprAfterDebtChange`; both harm assertions returned a valid APR instead of reverting.

## Exact hypothesis and harm assertion

- Exact bug claimed: attacker-controlled initialized ticks make the loop at `UniswapV3SwapSimulatorCore.sol:98-179` consume the V3 subcall gas, after which insufficient gas remains for `_grovePrice()`'s catch/fallback path at `GroveCompounderAprOracle.sol:211-236`.
- Observable proof required: with the production baseline and V4 pools held constant, adding a qualifying dense V3 topology changes `aprAfterDebtChange` from success to failure at a realistic transaction budget.
- Exact assertion: `assertFalse(ok, "dense topology did not make the oracle unavailable ...")` after a gas-capped call to `aprAfterDebtChange`.
- Claimed harm: an APR-dependent consumer transaction becomes unavailable even though a valid V4 fallback price exists.

Both the 60M primary harm assertion and the relaxed 5M variant failed because `ok == true` and APR was `72,119,140,831,426,053`.

## Feasibility gates

### F1 — Reachability: pass

`aprAfterDebtChange(address,int256)` is external and unrestricted (`GroveCompounderAprOracle.sol:109-132`). It calls `_grovePrice()`, which enters the V3 simulator when the pool has at least `1e12` active liquidity and 1,000 USDC (`239-245`). Production-fork mints proved public LP operations can create the required active and initialized-tick structure.

### F2 — Real-value/resource bounds: partial / current configuration does not cross the harm threshold

At pinned Ethereum block `25,583,831`:

- block gas limit: 60,000,000;
- default pool tick spacing: 200;
- current tick: 310,799;
- active pool liquidity: 0;
- pool USDC balance: 71 raw units, below the 1,000e6 precheck;
- fee-100, fee-500, and fee-3000 GROVE/USDC pools: absent;
- fixed oracle quote: 1e18 GROVE, moving only in the token1-to-token0/upward direction.

An attacker can make the default pool qualify by supplying narrow liquidity and about 1,000 USDC. On deployed pool bytecode, constructing and traversing 250 initialized ticks cost 2,707,881 quote gas. The 250-tick model cost 4,146,314 gas (53% more), so the large model was conservative at the calibrated point. Even that model's 2,800-tick outer oracle call used 45,027,130 gas and returned successfully below the 60M limit.

## Dynamic validation

### PoC Attempt

- PoC Required: YES
- PoC Class: integration / boundary gas
- Attempted: YES
- PoC Not Attempted Because: N/A
- Test File: `validation_artifacts/repo/src/test/CAN004Validation.t.sol`
- Command: `env ETH_RPC_URL=https://ethereum.publicnode.com forge test --match-contract CAN004ValidationTest -vv`

### Attempts

1. **Production-fork baseline and topology construction [PROD-FORK].** At block 25,583,831 the default pool failed the V3 precheck and the oracle completed through V4 in under a 5M cap. Ordinary V3 `mint` calls then created active liquidity of `1e12`, an initialized first boundary that drops liquidity, and a later initialized boundary with zero `liquidityNet`.
2. **Production 250-tick calibration [PROD-FORK].** The deployed pool bytecode traversed the constructed topology in 2,707,881 quote gas. Output rounded to zero under the intentionally dust-thin post-boundary liquidity, so the oracle would continue to V4.
3. **Large modeled gas curve [MOCK] + exact in-scope simulator/oracle [CODE].** Quote costs were 4,146,314 gas at 250 ticks, 16,641,929 at 1,000, and 34,148,451 at 2,000. A 2,800-tick exact oracle call succeeded with a 60M cap after consuming 45,027,130 gas.
4. **Assertion retry and relaxed variants [POC-FAIL].** The same target and harm assertion were retried at 10M and 5M. Both returned the production V4 APR; the 5M harm assertion failed with `ok == true`.
5. **RPC configuration boundary [PROD-ONCHAIN].** The canonical factory returned address zero for the GROVE/USDC 100, 500, and 3000 fee tiers at the pinned block. Only the 1%/spacing-200 pool existed among the checked standard tiers.

### Execution Result

- Compiled: YES (initial harness compiled on attempt 1; one later logging-overload edit required one compile fix)
- Result: **FAIL — claimed harm assertions failed**
- Fuzz/boundary variant: boundary matrix at 5M, 10M, and 60M; no harm violation found
- Evidence Tag: **[POC-FAIL]** for the claimed harm; [PROD-FORK] for baseline, topology construction, and 250-tick calibration; [MOCK] for the full dense model
- Relevant output:

```text
outer_call_gas_cap 60000000
outer_call_observed_gas 45027130
outer_call_success true
outer_call_apr 72119140831426053

five_million_success true
five_million_apr 72119140831426053
```

## Evidence audit

| Claim | Evidence source | Tag | Valid for refutation? |
|---|---|---|---|
| The loop lacks an explicit iteration/gas cap | In-scope simulator core lines 98-179 | [CODE] | YES |
| The V3 call is wrapped in try/catch before V4 fallback | In-scope oracle lines 211-236 | [CODE] | YES |
| LPs can create active and zero-net initialized ticks | Pinned fork, deployed pool `mint` calls | [PROD-FORK] | YES |
| Production 250-tick quote cost is 2,707,881 gas | Pinned fork, deployed pool bytecode | [PROD-FORK] | YES |
| Pinned block gas limit/config/state values | Ethereum RPC at block 25,583,831 | [PROD-ONCHAIN] | YES |
| Full 2,800-tick path consumes 45,027,130 gas and fallback succeeds | Storage-backed pool model plus exact target simulator/oracle and production V4 | [MOCK] + [CODE] + [PROD-FORK] | **NO for final refutation** |
| EIP-150 retains all but 1/64 for the child call | EIP-150 specification | [DOC] | NO alone; dynamically corroborated |
| No production consumer exists in scope | Repository-wide caller search | [CODE] | YES |

The mock-evidence override is why this row is `deferred`, not `suppressed`, despite failed harm assertions.

## RAG / historical precedent

- Historical precedent: **NO direct exploit matching this exact V3-simulator/fallback pattern was found** in the bounded primary-source search.
- Similar mechanisms: Uniswap V3 documents/code-implements initialized tick crossing and tick spacing; crossing more initialized ticks raises gas. EIP-150 defines the 63/64 forwarding rule that preserves caller gas. See [Uniswap v3-core](https://github.com/Uniswap/v3-core) and [EIP-150](https://eips.ethereum.org/EIPS/eip-150).
- Pattern confidence: **MEDIUM** for gas amplification; **LOW** for harmful availability in the pinned/default deployment.

## Counterevidence, devil's advocate, and enablers

Counterevidence is the finite configured tick spacing/range/direction/input, conservative model success below the block limit, successful 5M/10M fallback, absent smaller-fee pools, and missing consumer.

What would make this exploitable: management could select a newly created smaller-spacing GROVE/USDC pool; an attacker could pre-initialize many more dust-liquidity boundaries across multiple transactions; and a real consumer could forward a fixed gas budget so small that the EIP-150 reserve cannot execute its fallback/caller logic. This combination was checked but is not evidenced in the pinned deployment or repository.

Canonical candidate/enabler search found no finding that creates a downstream APR consumer or grants management configuration control. CAN-003 can independently weaken V4 price availability, but it does not defeat EIP-150 or prove CAN-004's gas postcondition.

## Severity facts

- Proven impact: gas amplification only; no reverted oracle or consumer transaction and no fund loss.
- Current/default deployment: no reportable severity established.
- Conditional ceiling: **Medium** only if a smaller-spacing pool is selected and a security-sensitive consumer can be repeatedly denied; this matches the threat model's Medium availability criterion.
- Likelihood: low under pinned configuration (inactive 1% pool, missing 1,000-USDC balance, no alternative standard fee pools, no consumer).

## Remaining uncertainty and minimal next step

The exact full-topology production-pool cost was not executed because the initial direct storage attempt required thousands of fork RPC storage reads and was stopped after bounded retries; the 250-tick production calibration plus conservative large model replaced it. The minimal closure step is a pinned fork test that constructs the maximum economically plausible topology through batched real V3 positions for any actually selected fee tier, then invokes the real downstream allocator/caller with its exact gas envelope. If no such consumer or selected smaller-spacing pool exists, suppress this candidate.

## Artifacts

- `validation_artifacts/repo/src/test/CAN004Validation.t.sol`
- `validation_artifacts/forge_harm_assertions.log`
- `validation_artifacts/forge_gas_curve.log`
- `validation_artifacts/forge_production_250.log`
- `validation_artifacts/rpc_snapshot.json`
- `validation_artifacts/README.md`

## Validation closure

| Ledger row | Instance key | Advisory/source | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|---|
| COV-007 | `denial-of-service:src/libraries/UniswapV3SwapSimulatorCore.sol:98` | none | `src/libraries/UniswapV3SwapSimulatorCore.sol:98-179` | `GroveCompounderAprOracle.aprAfterDebtChange` and attacker-controlled V3 LP topology | uncapped simulation loop before `try/catch` V4 fallback | deferred | Harm assertions failed at 5M/60M; maximum state is modeled, smaller-spacing selected pool and concrete consumer remain unproven | uncertain |
