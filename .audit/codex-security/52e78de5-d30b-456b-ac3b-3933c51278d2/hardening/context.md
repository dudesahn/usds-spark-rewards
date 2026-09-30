# Hardening Analysis Context

Analysis ID: `hardening_final`  
Source scan: `52e78de5-d30b-456b-ac3b-3933c51278d2` (pre-seal final-reporting state)  
Target revision: `f8f796db93c52432cca0ed26861e94f5aaf20975`  
Source root: `/private/tmp/codex-security-usds-spark-rewards-f8f796d-019f8637`  
Source drift: none; `git rev-parse HEAD` matched the target revision and the worktree was clean.

The scan manifest was not yet sealed when this derived analysis was prepared, so no
manifest digest is claimed. The inventory below binds the analysis to the current
canonical findings and detailed writeups. `context.md` is working context and is the
only hardening artifact that contains local absolute paths.

| Evidence | Reader-facing title | Path | SHA-256 |
| --- | --- | --- | --- |
| `SCAN-FINDINGS` | Canonical accepted findings | `<scan-root>/findings.json` | `c20aebaf0537118fff69d32ac00f0a491c1c081d2919a754509db0efbae06095` |
| `F-REPORT-DOS` | An active reward auction can repeatedly block strategy reports (`csf_caa09b28e81d6df8702f4f3b`) | `<scan-root>/findings/permissionless-auction-prekick-report-dos/permissionless-auction-prekick-report-dos.md` | `af24cdee3614fe24d24b2d7e8bdfe8a243418d2c6ff35d684566a5777e4751df` |
| `F-REWARD-DILUTION` | Late deposits can capture reward value accrued before entry (`csf_b51d06995c5b3b21d7a6c516`) | `<scan-root>/findings/late-deposit-reward-dilution/late-deposit-reward-dilution.md` | `21fcb183558280f6a41c37ceb2acca45094cde72b490218f6474e0f877c1b2ed` |
| `THREAT-MODEL` | Canonical threat model | `<scan-root>/artifacts/01_context/threat_model.md` | `a9986dad1b8aaf74ca3c8982ba6eb284fbba4702c333e7245daddd6e40fe1286` |
| `SOURCE-GROVE` | `GroveCompounder` at the affected revision | `<source-root>/src/GroveCompounder.sol` | `1421f5b6a62549430f76f5f37b07f0970bf2690b9dba3b6263e53e1efa1617f6` |

## Inspection Notes

I inspected `src/GroveCompounder.sol`, the two accepted writeups, their canonical
finding records, and the canonical threat model. The relevant first-party boundary
spans `availableDepositLimit()`, `_harvestAndReport()`, `_kickAuction()`, and
`setAuction()`. The source exposes no owned reward-lifecycle abstraction: deposit
admission, share pricing, reward claiming, auction state, and report completion each
consume a different partial view of the same reward lot.

The two findings are not merely adjacent by directory. Both depend on unsettled GROVE
crossing an external lifecycle without a single strategy-owned rule for (a) whether a
report may advance and (b) which share supply owns the pending value. That is enough
to qualify one bounded hardening opportunity. It does not justify a broad protocol
rewrite; the recommendation therefore retains a focused local option and treats the
larger queued-settlement design as conditional on an always-open deposit requirement.

