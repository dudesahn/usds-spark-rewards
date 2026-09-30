# Reviewed Surfaces

The deep scan reviewed the nine-file first-party production allowlist at revision `f8f796db93c52432cca0ed26861e94f5aaf20975`. Five complete independent discovery passes produced 270 accepted file-review receipts. A sixth pass was interrupted and excluded after the user narrowed continued discovery to new `GroveCompounder` clusters; the preceding pass had produced no new `GroveCompounder` cluster. Tests and directly relied-on vendored implementations were used only for validation.

| Surface | Final disposition | Evidence |
|---|---|---|
| Strategy lifecycle, custody, authorization, fixed staking/PSM integrations | No issue found | `artifacts/03_coverage/repository_coverage_ledger.md` rows COV-001, COV-003, COV-004 |
| Direct reward-sale slippage | Needs follow-up | CAN-001 validation deferred because the production-fork sandwich was unprofitable before gas and permanent loss was not proven |
| Oracle price, quorum, expiry, supply-denominator, and V3 traversal behavior | Needs follow-up | CAN-002 through CAN-005 and CAN-007 validation reports; mechanisms were reproduced where applicable, but no security-sensitive consumer or concrete loss was established |
| Interface declarations and non-EVM families | Not applicable | `artifacts/03_coverage/repository_coverage_ledger.md` rows COV-011 and COV-012 |
| Report-boundary reward accounting | Reported | CAN-006 validation and attack-path reports |
| Reward-auction state-machine liveness | Reported | CAN-008 validation and attack-path reports |
| Simulator oversized signed conversion | Rejected | CAN-009 validation; no supported caller reaches the range |

## Explicit exclusions

- `src/test/**` was excluded from discovery and used only for validation.
- `script/**`, `broadcast/**`, fixtures, build/cache outputs, generated files, and repository configuration were excluded.
- `lib/**` was excluded except where a concrete implementation was directly required to validate an allowlisted call path.
- `.audit/**`, `**/.scratchpad/**`, `x-ray/**`, reports, cached analysis, and prior scanner material were excluded.

## Deferred questions

- Whether any deployed direct-sale strategy instance makes CAN-001 economically profitable under real liquidity and gas.
- Whether an oracle output is consumed by a state-changing allocator or other security-sensitive production decision.
- Exact live strategy/Auction configuration prevalence; this affects breadth, not the confirmed CAN-008 mechanism.
