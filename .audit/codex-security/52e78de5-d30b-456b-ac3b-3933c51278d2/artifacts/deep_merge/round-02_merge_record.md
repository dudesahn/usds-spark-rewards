# Deep Discovery Round 02 Merge Record

Status: complete

All six round-02 workers completed all nine authoritative production rows and were idle before merge. The same remediation-subsumption rule was applied against the full prior canonical inventory.

| Canonical candidate | Round-02 worker candidates | Merge effect |
|---|---|---|
| CAN-001 | DS-R02-W01-001; R02-W02-001; W03-C001; W04-CAND-001; W05-001; DSR2-W06-001 | repeated and strengthened; no new cluster |
| CAN-002 | DS-R02-W01-002; R02-W02-002; W03-C002; W04-CAND-002; W05-002; DSR2-W06-003 | repeated and strengthened; no new cluster |
| CAN-003 | DS-R02-W01-003; R02-W02-003; W03-C003; W04-CAND-003; W05-003; DSR2-W06-002 | repeated and strengthened with live single-qualifying-pool evidence; no new cluster |
| CAN-004 | W04-CAND-005; worker-01 deferred coverage row | repeated with proof gap preserved; no new cluster |
| CAN-005 | none | retained unchanged; lack of recurrence is not suppression |
| CAN-006 | W04-CAND-004 | new distinct cluster: pending reward value is excluded from share-price assets before realization, enabling late-depositor dilution under open/allowlisted deposits |

CAN-006 remains separate from CAN-001. A slippage fix for reward liquidation would not reserve pre-existing, unreported rewards for pre-existing shares, while an accounting/reservation fix would not constrain AMM execution price.

Novelty versus round 01: one new canonical candidate. Discovery must continue to a later full round.
