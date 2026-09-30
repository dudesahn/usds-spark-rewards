# Deep Discovery Round 04 Merge Record

Status: complete

All six round-04 workers completed all nine authoritative production rows and were idle before merge. The same remediation-subsumption rule was applied against the full prior canonical inventory.

| Canonical candidate | Round-04 worker candidates | Merge effect |
|---|---|---|
| CAN-001 | R04-W01-001; R04-W02-C01; R04-W03-C01; R04-W04-C01; DD-R04-W05-001; R04-W06-C01 | repeated and strengthened; no new cluster |
| CAN-002 | R04-W01-002; R04-W02-C02 (V3 instance); R04-W03-C02; R04-W04-C02; DD-R04-W05-002; R04-W06-C02 | repeated and strengthened; no new cluster |
| CAN-003 | R04-W01-003; R04-W02-C02 (V4 instance); R04-W03-C03; DD-R04-W05-003; R04-W06-C03 | repeated and strengthened; no new cluster |
| CAN-004 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-005 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-006 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-007 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-008 | DD-R04-W05-004 | new distinct cluster: an active auction causes a later reward-bearing report to revert at `kick` |

CAN-008 is remediation-distinct from reward-sale price protection. A slippage floor does not prevent duplicate auction activation, while skipping or combining active auctions does not constrain direct-swap execution price.

Novelty versus round 03: one new canonical candidate. Discovery must continue to a later full round.
