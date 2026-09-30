# Deep Discovery Round 01 Merge Record

Status: complete

All six worker artifact sets were complete, schema-valid, and idle before this merge. The round reviewed all nine authoritative production rows per worker. Semantic grouping used remediation subsumption: candidates were merged only when one remediation would close every absorbed source/control/sink/impact tuple.

| Canonical candidate | Absorbed worker candidates | Remediation-subsumption decision |
|---|---|---|
| CAN-001 | DS-W01-001; DSC-R1W2-003; W03-CAND-001; R01W04-002; DSC-W05-001; DS-R01-W06-C01 | Same exact-input GROVE sale and literal zero minimum-output control. A nonzero execution bound or equivalent protected sale mechanism closes every absorbed tuple. |
| CAN-002 | DS-W01-002; DSC-R1W2-001; W03-CAND-002; R01W04-003; DSC-W05-002; DS-R01-W06-C02 | Same primary V3 current-state quote acceptance before any independent price check. A time-weighted or independent-source validation on that branch closes every absorbed tuple. |
| CAN-003 | DS-W01-003; DSC-R1W2-002; W03-CAND-003; R01W04-004; DS-R01-W06-C03 | Same V4 fallback built from mutable current spot quotes with no minimum trustworthy quorum. A robust quorum/time-weighted fallback closes every absorbed tuple. |
| CAN-004 | W03-CAND-004; R01W04-001; DS-R01-W06-C04 | Same unbounded tick-dependent simulator traversal and failure to isolate gas before fallback. A complexity/gas bound closes every absorbed tuple. |
| CAN-005 | DSC-W05-003 | Unique strict reward-expiry boundary; no other candidate shares its source/control/sink tuple. |

No candidates were merged across rows because the fixes are independent: swap slippage, V3 price integrity, V4 fallback integrity, simulator resource bounds, and expiry-boundary handling do not remediate one another.

Novelty versus the empty prior inventory: five new canonical candidates. Discovery must continue to a later full round.
