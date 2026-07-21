# Security Review: codex-security-usds-spark-rewards-f8f796d-019f8637

## Scope

Deep production-code review of an explicit nine-file first-party Solidity allowlist. Tests and directly relied-on vendored implementations were used only to validate production paths; prior audit material and generated outputs did not seed discovery.

- Scan mode: deep_repository
- Target kind: git_revision
- Target ID: target_sha256_a8b04aa8bc032f52edf942579e0a56f881a39a31961258795c0d6da107c9c302
- Revision: f8f796db93c52432cca0ed26861e94f5aaf20975
- Inventory strategy: custom
- Included paths: .
- Excluded paths: none
- Runtime or test status: Pinned mainnet-fork validation completed for both reportable findings. CAN-008: 3 tests passed including 16 fuzz runs. CAN-006: 4 tests passed including 32 fuzz runs. All Forge output, caches, logs, PoCs, and disposable checkouts remained scan-local.
- Artifacts reviewed: src/GroveCompounder.sol, src/interfaces/IOracle.sol, src/interfaces/IPsmWrapper.sol, src/interfaces/IStaking.sol, src/interfaces/IStrategyInterface.sol, src/interfaces/IUniswapV4StateView.sol, src/libraries/UniswapV3SwapSimulator.sol, src/libraries/UniswapV3SwapSimulatorCore.sol, src/periphery/GroveCompounderAprOracle.sol
- Scan context: Discovery stopped after five complete passes when the latest pass produced no new GroveCompounder cluster, consistent with the user's narrowed saturation condition. Existing oracle and library candidates were still independently validated but were not used to trigger another discovery loop.

Limitations and exclusions:
- The scan did not enumerate every currently deployed strategy/Auction pair or its exact live configuration.
- Oracle candidates remain deferred because no security-sensitive state-changing production consumer or concrete loss was established.
- Tests, scripts, fixtures, vendored dependencies, prior audit artifacts, and generated outputs were excluded from discovery by policy.
- Excluded src/test/\*\*: Tests were excluded from discovery and used only for validation.
- Excluded script/\*\* and broadcast/\*\*: Deployment scripts and broadcast artifacts are not first-party runtime production logic in the requested scope.
- Excluded lib/\*\*: Vendored dependencies were excluded from discovery and read only when directly relied on by an allowlisted production call path.
- Excluded .audit/\*\*, \*\*/.scratchpad/\*\*, x-ray/\*\*, reports, and cached analysis: Prior audit and scanner material was excluded to prevent discovery seeding.
- Excluded fixtures, build/cache outputs, and generated files: Transient or generated material was excluded from production discovery.

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable DSS findings | 2 |
| Report instances | 2 |
| Report severity mix | medium: 1, low: 1 |
| Report confidence mix | high: 2 |
| Coverage | partial |
| Validation mode | Repeated independent discovery followed by semantic reconciliation, centralized counterevidence validation, production-fork PoCs, and independent attack-path severity analysis. |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

The strategy holds depositor USDS, stakes it through fixed external protocols, realizes GROVE rewards through an Auction or direct swap, and exposes inherited share/report accounting. The primary adversaries are unprivileged blockchain accounts and untrusted depositors; management, keepers, and governance are trusted but must remain safe when consuming attacker-influenced external state.

### Assets

- Depositor USDS principal and strategy shares
- Accrued GROVE reward value and its attribution among depositor cohorts
- Report availability, `lastReport`, and timely reward recognition
- Integrity of APR information exposed to downstream consumers

### Trust Boundaries

- Public depositors crossing into inherited share issuance and report-boundary accounting
- Public Auction callers influencing external state consumed by keeper-only reports
- GroveCompounder calls into fixed staking, PSM, Uniswap, and Auction implementations
- Management-controlled configuration crossing into unprivileged runtime behavior

### Attacker Capabilities

- Submit and order public blockchain transactions and observe pending or accrued reward state
- Deposit when the strategy is open or when included on its allowlist
- Acquire and donate dust amounts of GROVE and call public external-contract entrypoints
- Manipulate public market state subject to real capital, liquidity, gas, and timing constraints

### Security Objectives

- Preserve depositor principal and prevent unauthorized cross-depositor value transfer
- Attribute pre-entry rewards to the share supply that earned them unless an explicit policy states otherwise
- Keep authorized reports and maintenance live under attacker-influenced external states
- Prevent untrusted market state from causing security-sensitive decisions without adequate integrity controls

### Assumptions

- Management, keepers, and governance follow their intended roles and do not intentionally misconfigure or steal assets
- Fixed external protocols are not themselves compromised, while their documented public state transitions remain adversarially reachable
- Economic findings require a concrete cross-actor outcome and realistic capital/timing path, not mechanism-only price movement

## Findings

| Findings | Reports | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- | --- |
| An active reward auction can repeatedly block strategy reports | [CS-001](#finding-1) | medium | high | [Open CS-001](findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md) |
| Late deposits can capture reward value accrued before entry | [CS-002](#finding-2) | low | high | [Open CS-002](findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md) |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] An active reward auction can repeatedly block strategy reports

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | Static source tracing and a pinned mainnet-fork suite confirmed the normal collision, arbitrary one-wei pre-kick, repeatable renewal, unchanged `lastReport`, and recovery when renewal stops; three tests passed including 16 bounded fuzz runs. |
| Category | denial-of-service |
| CWE | CWE-400, CWE-841 |
| Affected lines | src/GroveCompounder.sol:107-109, src/GroveCompounder.sol:174-180, src/GroveCompounder.sol:209-216, lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-520 |

#### Summary

See the [detailed technical write-up](findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md).

#### Validation

See the [detailed technical write-up](findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md).

#### Dataflow

See the [detailed technical write-up](findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md).

#### Reachability

See the [detailed technical write-up](findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md).

#### Severity

See the [detailed technical write-up](findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md).

#### Remediation

See the [detailed technical write-up](findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md).

<a id="finding-2"></a>

### [2] Late deposits can capture reward value accrued before entry

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | high |
| Confidence rationale | A pinned mainnet-fork integration suite and 32 bounded fuzz runs confirmed the share-fraction formula, positive capture before and after the default performance fee, closed-unlisted rejection, allowlisted reachability, and the fact that profit locking delays rather than prevents the transfer. |
| Category | economic-accounting |
| CWE | CWE-682, CWE-841 |
| Affected lines | src/GroveCompounder.sol:70-72, src/GroveCompounder.sol:84-118, lib/tokenized-strategy/src/BaseStrategy.sol:225-244, lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540 |

#### Summary

See the [detailed technical write-up](findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md).

#### Validation

See the [detailed technical write-up](findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md).

#### Dataflow

See the [detailed technical write-up](findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md).

#### Reachability

See the [detailed technical write-up](findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md).

#### Severity

See the [detailed technical write-up](findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md).

#### Remediation

See the [detailed technical write-up](findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md).

## Structural Hardening

The scan also produced derived, unsealed design guidance based on the complete finding collection. These proposals describe options and tradeoffs; they do not indicate that any finding has been remediated.

[Open the structural hardening portfolio](hardening/hardening.md)

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| Strategy lifecycle, custody, authorization, staking, and PSM integrations | Asset custody and privileged control | No issue found | No unprivileged principal-transfer destination, reentrancy bypass, or first-party integration mismatch survived repeated discovery. Evidence: artifacts/03_coverage/repository_coverage_ledger.md |
| Direct reward sale slippage and transaction-ordering exposure | MEV and value realization | Needs follow-up | The zero-minimum mechanism is real, but the production-fork sandwich was unprofitable before gas and permanent loss was not established. Evidence: artifacts/05_findings/CAN-001/validation_report.md |
| APR oracle price, quorum, expiry, denominator, and traversal behavior | Oracle integrity and availability | Needs follow-up | Five candidates were independently validated. Several mechanisms were reproduced, but no security-sensitive state-changing consumer or concrete loss was established. Evidence: artifacts/05_findings/CAN-002/validation_report.md, artifacts/05_findings/CAN-003/validation_report.md, artifacts/05_findings/CAN-004/validation_report.md, artifacts/05_findings/CAN-005/validation_report.md, artifacts/05_findings/CAN-007/validation_report.md |
| Interface declarations and non-EVM vulnerability families | Interface-only and out-of-platform surfaces | Not applicable | ABI-only declarations contain no independent enforcement, and the production scope contains no filesystem, query, HTTP, session, or deserialization surface. Evidence: artifacts/03_coverage/repository_coverage_ledger.md |
| Report-boundary reward accounting and late-depositor value capture | Cross-depositor economic accounting | Reported | A pinned mainnet-fork integration PoC confirmed that a late depositor can capture part of reward value accrued before entry. Evidence: artifacts/05_findings/CAN-006/validation_report.md, artifacts/05_findings/CAN-006/attack_path_analysis_report.md |
| Reward-auction state-machine liveness during strategy reports | Maintenance availability | Reported | A pinned mainnet-fork integration PoC confirmed that an active reward-token auction makes a later report revert and that public dust pre-kicks can renew the denial. Evidence: artifacts/05_findings/CAN-008/validation_report.md, artifacts/05_findings/CAN-008/attack_path_analysis_report.md |
| V3 simulator oversized signed conversion | Numeric type integrity | Rejected | The cast changes semantics at or above 2^255, but the sole supported caller fixes the amount to 1e18 and no attacker-controlled consumer reaches the range. Evidence: artifacts/05_findings/CAN-009/validation_report.md |

## Open Questions And Follow Up

- Does any deployed direct-sale strategy instance make CAN-001 profitable under real liquidity and gas?
  - Follow-up prompt: Enumerate live direct-sale GroveCompounder deployments and run a pinned-fork search over realistic attacker sizes, pool liquidity, and gas.
- Is the APR oracle consumed by any security-sensitive state-changing production decision?
  - Follow-up prompt: Trace all deployed consumers of GroveCompounderAprOracle output and identify allocator, limit, or accounting writes driven by the quoted APR.
- Which deployed strategy/Auction pairs retain public kick permission?
  - Follow-up prompt: Enumerate deployed GroveCompounder strategy/Auction pairs and read each reward-token enablement and governanceOnlyKick configuration.
- The zero-minimum direct-sale mechanism was confirmed, but a production-fork sandwich was unprofitable before gas and permanent loss was not proven.
  - Follow-up prompt: Review deferred unit CAN-001 and close its stated proof gap. Paths: src/GroveCompounder.sol. Surfaces: direct-reward-sale.
- The V3 spot-price mechanism was reproduced, but the live branch was dormant and no state-changing allocator consumer or loss was found.
  - Follow-up prompt: Review deferred unit CAN-002 and close its stated proof gap. Paths: src/periphery/GroveCompounderAprOracle.sol. Surfaces: oracle-integrity.
- The one-quote V4 quorum weakness was reproduced, but no deployed consumer, manipulation-cost proof, or concrete loss was found.
  - Follow-up prompt: Review deferred unit CAN-003 and close its stated proof gap. Paths: src/periphery/GroveCompounderAprOracle.sol. Surfaces: oracle-integrity.
- The modeled traversal stayed live at both 5M and 60M gas, and no selected smaller-spacing pool or consumer gas envelope was established.
  - Follow-up prompt: Review deferred unit CAN-004 and close its stated proof gap. Paths: src/libraries/UniswapV3SwapSimulatorCore.sol. Surfaces: oracle-integrity.
- The reward-expiry equality mismatch was reproduced, but no persistent consumer action or loss was established.
  - Follow-up prompt: Review deferred unit CAN-005 and close its stated proof gap. Paths: src/periphery/GroveCompounderAprOracle.sol. Surfaces: oracle-integrity.
- The instantaneous denominator mechanism was reproduced, but moving APR by 10% required about 24.66M USDS and no state-changing consumer was found.
  - Follow-up prompt: Review deferred unit CAN-007 and close its stated proof gap. Paths: src/periphery/GroveCompounderAprOracle.sol. Surfaces: oracle-integrity.
