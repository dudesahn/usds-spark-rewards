# Deep Discovery Round 05 Merge Record

Status: complete

Six accepted round-05 workers completed all nine authoritative production rows and were idle before merge. The original worker-04 slot was rejected after it wrote generated files into the target worktree; its output is quarantined and contributes no receipts, candidates, or provenance. A fresh replacement worker completed the full assignment. The remediation-subsumption rule was applied against the full prior canonical inventory.

| Canonical candidate | Accepted round-05 worker candidates | Merge effect |
|---|---|---|
| CAN-001 | R05-W01-C01; R05-W02-C001; R05W03-C01; R05-W04R-C01; R05W05-001; R05-W06-C01 | repeated and strengthened; no new cluster |
| CAN-002 | R05-W01-C02 (V3 instance); R05-W02-C002; R05W03-C03; R05-W04R-C02; R05W05-002; R05-W06-C02 | repeated and strengthened; no new cluster |
| CAN-003 | R05-W01-C02 (V4 instance); R05-W02-C003; R05W03-C04; R05-W04R-C03; R05W05-003; R05-W06-C03 | repeated and strengthened; no new cluster |
| CAN-004 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-005 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-006 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-007 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-008 | R05W03-C02 | repeated and strengthened with permissionless donation/pre-kick evidence |
| CAN-009 | R05W03-C05 | new distinct cluster: unchecked unsigned-to-signed conversion changes exact-input simulation semantics for values at or above 2^255 |

CAN-009 is remediation-distinct from tick-loop availability and oracle pricing. A signed-range check closes the exported API type confusion without bounding tick traversal or authenticating market price, and those fixes do not enforce the API range.

Novelty versus round 04: one new canonical candidate, located only in the oracle-support simulator library. After this round completed, the user directed that repeated discovery continue only for new `GroveCompounder` clusters. Round 05 added zero such clusters, so this is the terminal full round; existing oracle candidates proceed to validation.
