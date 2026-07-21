# Efficiency Notes For Future Runs

Ways to make this workflow cheaper and faster next time:

1. Provide a run manifest up front:
   - target commit
   - exact scope files
   - exact skill paths
   - desired output folder name
   - whether findings need PoCs or source-only validation is enough

2. Pre-create a clean worktree and initialize dependencies:
   - `git worktree add --detach <path> <commit>`
   - `git submodule update --init --recursive`
   - one explicit fork test command with `--fork-url`

3. Keep one reusable source bundle:
   - primary scope only
   - supporting context clearly labeled
   - x-ray artifacts referenced as orientation only

4. Give the two-wave lane list directly:
   - wave 1: math-precision, access-control, economic-security, execution-trace, invariant, periphery
   - wave 2: first-principles, asymmetry, boundary, numerical-gap, trust-gap, flow-gap

5. Ask lanes to write only raw outputs, then synthesize once:
   - avoids cross-lane contamination
   - keeps raw artifacts auditable
   - reduces repeated "what did another lane find?" tool calls

6. Use explicit validation buckets:
   - Confirmed finding: source trace plus PoC or undeniable source proof
   - Lead: source-backed but missing downstream feasibility/economics
   - Rejected: invalid input, trusted-admin-only, style/gas, or no exploit path

7. For fork-heavy repos, always include the exact fork command:
   - `forge test -vv --fork-url https://ethereum.publicnode.com`
   - `ETH_RPC_URL` alone was not sufficient in this repo's detached run.

8. For recurring strategy-review work, keep a small template directory:
   - `run-manifest.md`
   - `validation-ledger.md`
   - `final-report.md`
   - `efficiency-notes.md`

The biggest avoidable cost in this run was reconstructing the workflow shape from prior yTranche notes and then recovering from fork/coverage/tooling quirks. A pinned scope manifest plus preinitialized detached worktree would cut most of that out.
