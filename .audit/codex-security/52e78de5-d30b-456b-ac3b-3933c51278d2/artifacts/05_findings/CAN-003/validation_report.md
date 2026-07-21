# Validation: CAN-003 — V4 fallback accepts mutable spot pricing without a trustworthy quorum

## Disposition

**Validation verdict: CONTESTED. Closure disposition: `deferred`.**

The in-scope oracle-integrity mechanism is mechanically confirmed: the fallback accepts one current V4 quote as its own median, and at pinned Ethereum block `25,583,826` the default V3 path was unavailable while exactly one of four default V4 pools qualified. The executed checked-out implementation selected that quote and used it verbatim in APR arithmetic. A focused boundary test further proved a `2x` sole `sqrtPriceX96` change understates the returned APR by `7,500 bps`; a 256-run fuzz variant showed every tested positive sole quote selects itself.

End-to-end security impact is not closed. The repository identifies neither a deployed address for this checked-out implementation nor a production consumer that makes a security-sensitive allocation from its APR. A full V4 swap replay and cross-tick manipulation-cost measurement was therefore not proportionate to a consumerless, apparently undeployed implementation. Those absences are proof gaps, not safety counterevidence, so the row is deferred rather than suppressed.

- Candidate id: `CAN-003`
- Instance key: `oracle-spot-v4:src/periphery/GroveCompounderAprOracle.sol:290`
- Ledger row id: not supplied
- Root control: `src/periphery/GroveCompounderAprOracle.sol:255-335`
- Configuration reachability: `src/periphery/GroveCompounderAprOracle.sol:95-100,147-163,338-354`
- Fallback entry/sink: `src/periphery/GroveCompounderAprOracle.sol:211-236,118-132`
- External state source: `src/interfaces/IUniswapV4StateView.sol:4-10`
- Confidence: **High (0.94) for the mechanism; Medium (0.64) overall/reportability**
- Evidence status: `[POC-PASS] [PROD-FORK]` for oracle-integrity harm; `[UNPROVEN-EXTERNAL]` for consumer/economic harm

## Validation rubric

- [x] **Fallback reachability:** pinned fork proved V3 active liquidity `0` and only one default V4 quote above the source threshold.
- [x] **Quote-count boundary/self-median:** source trace, unit boundary test, and 256-run fuzz test proved `quoteCount == 1` proceeds and necessarily selects that quote.
- [x] **Attacker manipulation/depth:** public V4 Swap events and current `slot0` establish mutable spot state; current active-range depth is small, but exact cross-tick attack cost remains unmeasured.
- [x] **External consumer impact:** bounded source/package/deploy adjacency found no production caller; only tests invoke `aprAfterDebtChange`.
- [x] **Deployed state/config counterevidence:** live default pools reproduce the one-quote state, but the repository's recorded production oracle addresses do not expose the checked-out V4 implementation.

## Exact bug and proof assertion

1. **Exact bug:** `_selectedV4Pool` continues for any `quoteCount > 0`; `_medianPrice` returns the only price when `quoteCount == 1`; `_withinV4PriceDeviation(price, price)` is tautologically true; and `_grovePrice` feeds the result into APR without a TWAP, independent anchor, normalized value-depth check, or minimum trustworthy quorum.
2. **Observable difference:** with all other oracle inputs held fixed, doubling the sole inverse-oriented `sqrtPriceX96` quarters price and changes APR from `831,352,032,000,000` to `207,822,240,000,000`, a `7,500-bps` understatement after integer rounding.
3. **Assertion:** `(fairApr - manipulatedApr) * 10_000 / fairApr == 7_500`, while the sole quote remains selected.
4. **Claimed harm:** an APR consumer can receive a materially false yet sub-cap return value and make a wrong allocation decision; that consumer action is not present in the supplied repository and remains unproven.

## Source/control/sink assessment

| Element | Evidence |
|---|---|
| Source | Permissionless V4 swaps update current `sqrtPriceX96`; StateView exposes that current state. `[CODE] [PROD-ONCHAIN]` |
| Closest control | Raw active liquidity must be at least `1e12`; deviation is relative to the same quote set. No minimum quote count beyond one. `[CODE]` |
| Sink | The selected spot `price` is returned by `_grovePrice` and multiplies staking `rewardRate` in `aprAfterDebtChange`. `[CODE] [PROD-FORK]` |
| Reachable path | `aprAfterDebtChange` is permissionless; V3 ineligibility enters `_selectedV4Pool`; one quote passes median/deviation and reaches APR. `[CODE] [PROD-FORK]` |
| Boundary | APR consumers are an external integration boundary under the canonical threat model. `[DOC]` |
| Counterevidence | The `50%` APR cap rejects only sufficiently high final APR; management curates pool ids; known broadcast addresses do not contain the checked-out V4 code. `[CODE] [PROD-ONCHAIN]` |
| Proof gaps | Checked-out deployment address, real security-sensitive consumer, pool key/hook/router path, exact cross-tick manipulation cost, consumer loss/profit. |

### Feasibility gates

- **F1 reachability: partial pass.** The oracle entrypoint is external and permissionless, and the fallback path was live on the fork. No in-scope production consumer reaches an economic sink.
- **F2 bounds: partial pass.** A one-quote live state and arbitrary sub-cap underpricing are feasible. Exact capital/fee/cross-range depth needed to create a chosen distortion was not reproduced.

## PoC attempt

- PoC Required: YES
- PoC Class: integration
- Attempted: YES
- PoC Not Attempted Because: N/A
- Test File: `artifacts/05_findings/CAN-003/validation_artifacts/worktree/src/test/CAN003Validation.t.sol`
- Command: `forge test --match-path src/test/CAN003Validation.t.sol --fork-url https://ethereum.publicnode.com --fork-block-number 25583826 -vv`

### Execution result

- Compiled: YES (2 compile attempts; first failed because the test was incorrectly declared `view`)
- Result: PASS after one assertion-precision retry
- Fuzz variant: PASS, 256 runs
- Output: 3 passed, 0 failed, 0 skipped
- Evidence tag: `[POC-PASS] [PROD-FORK]` for false-APR/oracle-integrity behavior; `[UNPROVEN-EXTERNAL]` for consumer loss

The retry did not change the target function, setup preconditions, or 7,500-bps harm assertion. It added a small absolute tolerance only to the redundant 4:1 ratio assertion because the implementation truncates the price before annualization.

## Evidence audit

| Claim | Evidence source | Tag | Valid for refutation? |
|---|---|---|---|
| One quote is accepted as its own median | Checked-out lines 288-335; executed boundary/fuzz tests | `[CODE] [POC-PASS]` | YES |
| Default fallback had exactly one qualifying quote | Mainnet fork at block 25,583,826 | `[PROD-FORK]` | YES |
| Sole production quote reached APR arithmetic | Deployed checked-out code in the fork with live StateView/staking state | `[PROD-FORK]` | YES |
| A `2x` spot-square-root change causes 75% APR understatement | Focused test with mocked price/staking inputs | `[MOCK]` | NO; mechanism/impact-shape only |
| Public swaps mutate pool spot state | Mainnet PoolManager Swap event, e.g. transaction `0x9bfb...a4abb` | `[PROD-ONCHAIN]` | YES |
| Exact manipulation is economically practical | Not established across initialized tick ranges | `[EXT-UNV]` | NO |
| A real allocator loses funds or misallocates | No consumer found | `[EXT-UNV]` | NO |
| Recorded deployment is the checked-out implementation | Counterevidence: latest broadcast says `SparkCompounderAprOracle`; V4 selectors revert | `[CODE] [PROD-ONCHAIN]` | YES |

## RAG / historical precedent

- Historical precedent: **YES** for DEX spot-price oracle manipulation as a vulnerability class.
- Similar exploit pattern: flash-funded manipulation of a DEX spot price followed by same-transaction use by a financial consumer, described in [Chainlink's flash-loan/oracle guidance](https://chain.link/education-hub/flash-loans).
- Defensive precedent: the [Uniswap v2 whitepaper](https://docs.uniswap.org/whitepaper.pdf) explicitly motivates time-weighted price accumulation because current/balance-derived prices can be manipulated.
- Pattern confidence: **HIGH** for the missing time/independent-source control; **MEDIUM** for this instance's exploitability because deployment, consumer, and full depth are unresolved.
- PoC template used: no external template; the test directly exercises the checked-out oracle and production StateView.

## Bounded consumer/config adjacency

- Production-source search outside `src/test`, `broadcast`, and `lib` found no `aprAfterDebtChange` caller or consumer configuration.
- `script/DeployStrategyAndOracle.s.sol` only deploys/logs the oracle.
- The latest broadcast deploys a differently named/implemented `SparkCompounderAprOracle` at `0xba7c...0430`; production calls to the checked-out V4 selectors revert.
- The current source supports one pool through `setUniV4Pool`, and the constructor's four pools degraded to one usable quote on the pinned fork.

The mutable pool snapshot is not suppression evidence; it establishes current reachability but cannot substitute for deployment and consumer proof.

## Devil's advocate and chain check

This becomes end-to-end exploitable if the checked-out implementation is deployed, V3 is unusable, one/few attacker-movable V4 quotes determine the median, the attacker can hold the distortion through the read at acceptable cost, and an allocator acts before correction. The canonical candidate inventory was checked for a matching enabler; no separate finding is required to create the observed one-quote fallback state, which already existed on the pinned fork. No `findings_inventory.md` artifact exists.

## Severity facts

- Impact proven: material false APR output; the focused test demonstrates a `75%` understatement.
- Impact not proven: capital movement, user loss, denial of a deployed operation, or attacker profit.
- Likelihood increasing facts: permissionless spot market; fallback live at the pinned state; one-quote supported configuration; current-median filter vacuous at one quote.
- Likelihood reducing facts: checked-out implementation not located in recorded deployments; no consumer found; exact cross-tick cost and hook behavior unmeasured; `50%` cap rejects sufficiently high APR.
- Severity if deployment plus a security-sensitive allocator is established: **Medium** under the canonical threat model for unsafe APR with realistic consumer/liquidity preconditions; **High** would require quantified large allocation loss.
- Current closure severity: **unassigned/deferred**, not promoted on assumed external behavior.

## Remaining uncertainty and next step

Minimal next step: provide or locate the checked-out oracle deployment and its allocator/registry consumer. Pin a block where that consumer can act, obtain the exact V4 pool key/hook/router path, execute a before/manipulate/consume/restore fork sequence, and assert the consumer's capital decision or loss. If no deployment or consumer exists, close this row as `not_applicable` or `suppressed` with that exact production evidence.

**Fix:** Architectural change required — require a minimum independent usable-source quorum and validate the fallback against a time-weighted or independent price source with value-normalized depth. No inline diff provided.

## Artifacts

- `artifacts/05_findings/CAN-003/validation_artifacts/worktree/src/test/CAN003Validation.t.sol`
- `artifacts/05_findings/CAN-003/validation_artifacts/forge_test.log`
- `artifacts/05_findings/CAN-003/validation_artifacts/production_state.md`
- `artifacts/05_findings/CAN-003/validation_artifacts/README.md`

## Validation closure

| ledger row id | instance key | advisory/source reference | seed anchor | root control | entrypoint/source | sink/control | disposition | counterevidence or proof gap | survives |
|---|---|---|---|---|---|---|---|---|---|
| N/A | `oracle-spot-v4:src/periphery/GroveCompounderAprOracle.sol:290` | N/A | N/A | `src/periphery/GroveCompounderAprOracle.sol:255-335` | permissionless `aprAfterDebtChange`; public V4 spot state | sole quote reaches APR arithmetic | `deferred` | checked-out deployment, consumer action, exact manipulation cost, and economic harm unresolved | uncertain |
