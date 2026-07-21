# Run Manifest

Target repository: `usds-spark-rewards`

Target commit: `f8f796db93c52432cca0ed26861e94f5aaf20975`

Detached worktree: `/private/tmp/usds-grove-pashov-f8f796d-20260721T194201Z`

Primary scope:

- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

Supporting context:

- interfaces in `src/interfaces`
- swap simulator libraries in `src/libraries`
- fork tests in `src/test`
- Yearn Tokenized Strategy/periphery dependencies where the scoped contracts call inherited behavior

Workflow:

1. Ran Pashov x-ray first in the detached worktree.
2. Preserved x-ray orientation artifacts under `x-ray/`.
3. Built Solidity Auditor bundles from the target source plus the x-ray orientation pointer.
4. Ran all 12 Solidity Auditor lanes in two clean waves of six:
   - Wave 1: math-precision, access-control, economic-security, execution-trace, invariant, periphery.
   - Wave 2: first-principles, asymmetry, boundary, numerical-gap, trust-gap, flow-gap.
5. Kept each lane output distinct under `solidity-auditor/wave-1/` and `solidity-auditor/wave-2/`.
6. Validated promoted candidates with source review and a focused Foundry PoC where applicable.
7. Wrote final synthesis under `synthesis/`.

Clean-room note:

The x-ray artifacts were used only for orientation: scope, entry points, dependency map, and invariant map. Solidity Auditor lanes were instructed not to treat x-ray statements as evidence and not to read other lanes' outputs.

Verification:

- `forge test -vv --fork-url https://ethereum.publicnode.com`: 26 passed, 0 failed.
- Focused auction-dilution PoC: passed once live; preserved under `validation/auction-dilution-validation.md`.

Tooling notes:

- `forge coverage` pulled dependencies but did not produce useful coverage; fork-test `setUp()` reverted when run without explicit fork configuration.
- The x-ray enumeration script hit macOS/BSD `grep -P` incompatibilities; portable supplemental line counts were used in the x-ray report.
- A later redirected Foundry fork run hit a Foundry/macOS provider panic before test execution; the crash output is preserved in validation artifacts and was not a PoC failure.
