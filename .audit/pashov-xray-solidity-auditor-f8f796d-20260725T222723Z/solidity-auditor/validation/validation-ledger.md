# Validation Ledger

Target: `f8f796db93c52432cca0ed26861e94f5aaf20975`

## Gate Definitions

1. Attack execution is concrete.
2. The path is reachable in the target and pinned dependencies.
3. An unprivileged caller can trigger the path, directly or through public market state.
4. The path causes material victim harm.

## Deduplicated Results

| ID | Converged cluster | Raw lanes | Gate result | Final disposition |
|---|---|---|---|---|
| V-01 | Auction settlement/callback share dilution | 03, 05, 07, 11, 12 | All four gates clear; fork PoC passes. Specific state required: deposits open and auction active. | Finding F-01, Medium, confidence 90 |
| V-02 | Permissionless active-auction report DoS | 04, 12 | All four gates clear; fork PoC proves repeatability with the same one-wei balance. Specific state required: public kicks and reportable rewards. | Finding F-02, Medium, confidence 90 |
| V-03 | Direct-sale zero minimum output / keeper or searcher sandwich | 04, 07, 11 | Execution is plausible, but the shared rules exclude ordinary MEV; the keeper-only variant also fails the unprivileged-trigger gate. | Rejected from report |
| V-04 | V3-priority spot quote manipulation | 04, 05, 06, 07, 08, 09, 11, 12 | Quote corruption is reachable; no in-scope state-changing APR consumer or material sink. | Lead L-01 |
| V-05 | Singleton/raw-liquidity V4 quote manipulation | 01, 03, 04, 07, 08, 09, 10 | A single quote self-validates and raw liquidity is not economic depth; no in-scope sink. | Lead L-02 |
| V-06 | Even-count median empty selection | 03, 10 | Source math proves `[1,2] -> 1.5`, after which both quotes fail the 10% filter; downstream harm not in scope. | Lead L-03 |
| V-07 | APR debt/idle/bulk-sale model divergence | 05, 07, 10, 11 | Forecast divergence is source-backed; allocator policy and victim loss are not in scope. | Lead L-04 |
| V-08 | Cross-token auction threshold and keeper scope | 01, 02, 05, 06, 07, 08, 09, 10 | Unit mismatch and broader-than-automatic token scope are real; no valuable token source or unprivileged extraction path. | Lead L-05 |
| V-09 | `uint256` to `int256` simulator mode flip | 01, 04, 06, 09 | Cast semantics are real; the only in-scope caller uses `1e18`. | Lead L-06 |
| V-10 | Auction receiver can drift after one-time validation | 02 | Requires out-of-scope Auction governance to redirect proceeds; fails Gate 3. | Rejected |
| V-11 | Staking pause can block re-deployment during report | 04, 08 | Requires external privileged pause and has no unprivileged amplifier; fails Gate 3. | Rejected |
| V-12 | Default `useAuction=true` before auction setup | 09 | Intended deployment/setup keeps deposits closed until management configuration; privileged setup issue. | Rejected |
| V-13 | Reward-period equality returns one timestamp of stale APR | 04, 05, 09, 10 | Reachable boundary, but bounded to one timestamp and no material sink. | Rejected as immaterial |
| V-14 | Unbounded negative APR delta reverts | 06, 09 | Caller-supplied out-of-domain view input; no victim or stateful consumer. | Rejected |
| V-15 | Legacy first-V4-pool getters may not describe selected pool | 08 | Interface ambiguity only; no incorrect in-scope state transition or harm. | Rejected |
| V-16 | Active zero reward still invokes pricing | 08 | Operational view liveness only; no material consumer impact. | Rejected |

## Completeness

- Raw structured output: 18 FINDING records and 35 LEAD records across 12 lane files.
- Canonical `(contract, function)` tuples after normalizing compound function labels: 10.
- All 10 tuples are covered by F-01/F-02, L-01 through L-06, or an explicit rejected row above.
- No raw output was silently discarded.
