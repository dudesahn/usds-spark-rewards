# Orientation

Target worktree: `/private/tmp/usds-grove-pashov-f8f796d-20260721T194201Z`

Target commit: `f8f796db93c52432cca0ed26861e94f5aaf20975`

Primary audit scope:

- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

Supporting context in the source bundle:

- `src/interfaces/IStaking.sol`
- `src/interfaces/IPsmWrapper.sol`
- `src/interfaces/IUniswapV4StateView.sol`
- `src/libraries/UniswapV3SwapSimulator.sol`
- `src/libraries/UniswapV3SwapSimulatorCore.sol`
- selected fork-test context from `src/test/utils/Setup.sol`, `src/test/Operation.t.sol`, and `src/test/Oracle.t.sol`

X-ray artifacts are available at:

- `x-ray/x-ray.md`
- `x-ray/entry-points.md`
- `x-ray/invariants.md`
- `x-ray/architecture.svg`
- `x-ray/git-security-analysis.json`

Use the x-ray artifacts only for orientation: scope, entry points, invariants, dependency map, and live-environment notes. Do not treat x-ray statements as evidence. Every finding or lead must be supported by source code, concrete execution reasoning, or a local validation artifact.

Reporting rule for this run: output both validated FINDING blocks and plausible LEAD blocks. Do not include style notes, gas notes, admin-only-functions-do-admin-things, generic trusted-admin-can-rug claims, or unsupported speculation.
