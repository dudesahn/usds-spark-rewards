# Run Notes

## Isolation

- A new detached worktree was created at commit `f8f796db93c52432cca0ed26861e94f5aaf20975`.
- Existing worktrees and the caller repository were not used for source analysis.
- Existing audit outputs in the caller repository were not read or supplied to any lane.
- The yTranche review was consulted only for operational precedent: x-ray first as orientation, all specialties in two waves, raw-output preservation, validation before promotion, and one final synthesis. No yTranche finding or protocol conclusion was passed to a lane.

## X-ray

- X-ray ran first in the detached worktree and produced its own `x-ray/` directory.
- The x-ray report, entry points, invariants, enumeration, and SVG were frozen into `x-ray-orientation.md` before Solidity-auditor started.
- X-ray's `forge coverage` attempt reached all four suites but their fork-dependent setup reverted without a fork URL; the x-ray report records coverage as unavailable, not as absent tests.
- The SVG was inspected as markup. No SVG renderer was installed, so raster visual QA was skipped as permitted by the x-ray workflow.

## Solidity-auditor

- A single clean source bundle contained only the four in-scope production files.
- Each lane received its own immutable specialty bundle, the same source bundle, and the frozen x-ray orientation.
- Lanes could inspect pinned dependencies for a targeted proof, but could not read other lane outputs, previous audits, or yTranche results.
- Wave 1 completed before Wave 2 began.

### Wave 1

1. Math / precision
2. Access control
3. Economic security
4. Execution trace
5. Invariant
6. Periphery

### Wave 2

7. First principles
8. Asymmetry
9. Boundary
10. Numerical gap
11. Trust gap
12. Flow gap

## Validation and Synthesis

- Raw output contained 18 findings and 35 leads.
- Deduplication was performed only after all 12 outputs were sealed and hashed.
- The final judging pass applied attack execution, reachability, unprivileged trigger, and material victim-harm gates.
- Two findings survived. Six incomplete but source-backed paths were retained as leads.
- Two focused mainnet-fork PoCs passed at fork block 25,612,756.
- The temporary test was removed from `src/test`; the reproducible source is preserved only under `validation/pocs/`.

## Precedent Consulted

- `/Users/dudesahn/Documents/GitHub/codex/review/ytranche/.audit/findings/codex-xray-solidity-auditor-a24f859.md`
- yTranche Plamen run notes for clean-room preflight, raw/scope/config archival, and explicit validation artifacts.

These references influenced run organization and artifact hygiene only.
