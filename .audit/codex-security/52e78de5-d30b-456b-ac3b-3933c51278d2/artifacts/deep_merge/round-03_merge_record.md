# Deep Discovery Round 03 Merge Record

Status: complete

All six round-03 workers completed all nine authoritative production rows and were idle before merge. The same remediation-subsumption rule was applied against the full prior canonical inventory.

| Canonical candidate | Round-03 worker candidates | Merge effect |
|---|---|---|
| CAN-001 | DEEP-R03-W01-C003; DS-R03-W02-001; R03W03-C001; CAND-R03-W04-001; DD-R03-W05-003; DSR03W06-003 | repeated and strengthened; no new cluster |
| CAN-002 | DEEP-R03-W01-C002; DS-R03-W02-002; R03W03-C002; CAND-R03-W04-002; DD-R03-W05-001; DSR03W06-001 | repeated and strengthened; no new cluster |
| CAN-003 | DEEP-R03-W01-C001; DS-R03-W02-003; R03W03-C003; CAND-R03-W04-003; DD-R03-W05-002; DSR03W06-002 | repeated and strengthened with current one-pool fallback evidence; no new cluster |
| CAN-004 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-005 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-006 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-007 | DEEP-R03-W01-C004 | new distinct cluster: unrelated same-block staking supply changes affect the instantaneous APR denominator |

CAN-007 is remediation-distinct from the price-integrity candidates. Fixing V3/V4 pricing does not make the staking-supply denominator manipulation-resistant, while averaging or snapshotting the denominator does not secure market quotes.

Novelty versus round 02: one new canonical candidate. Discovery must continue to a later full round.
