# Attack-Path Analysis Summary

Two validation rows entered attack-path analysis. Both remain reportable after explicit scope, reachability, counterevidence, impact/likelihood calibration, and the mechanical final policy matrix.

| Candidate | Attack path | Impact | Likelihood | Final severity | Priority | Policy |
|---|---|---|---|---|---|---|
| CAN-008 | Public one-wei GROVE donation → permissionless pre-kick → trusted report unconditionally re-kicks → `too soon` revert → daily renewal | Medium | High | Medium | P2 | reportable |
| CAN-006 | Observe accrued-but-unreported GROVE → enter through open/allowlisted deposit → report realizes rewards over enlarged share base → wait through profit unlock → redeem captured pre-entry yield | Medium | Medium | Low | P3 | reportable |

## Counterevidence retained

- CAN-008 does not directly lose principal, a kick interval expires after one day, atomic rollback prevents transfer on the failed report, and recovery occurs if renewal stops or management reconfigures. Those facts cap impact but do not defeat the public repeatable denial.
- CAN-006 requires deposits to be open or the attacker allowlisted, material pending rewards, ordinary report/settlement, and capital through the unlock period. Fees and profit locking reduce or delay capture. Those constraints reduce likelihood and mechanically lower final severity to Low.

Per-finding reports and receipts:

- `artifacts/05_findings/CAN-006/attack_path_analysis_report.md`
- `artifacts/05_findings/CAN-008/attack_path_analysis_report.md`
