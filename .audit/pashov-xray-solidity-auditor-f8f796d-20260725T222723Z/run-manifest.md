# Run Manifest

| Item | Value |
|---|---|
| Run ID | `pashov-xray-solidity-auditor-f8f796d-20260725T222723Z` |
| Started/completed | 2026-07-25 |
| Target commit | `f8f796db93c52432cca0ed26861e94f5aaf20975` |
| Worktree mode | New detached worktree at exact target commit |
| X-ray skill | `codex/skill-research/pashov-skills/x-ray` |
| Solidity-auditor skill | `codex/skill-research/pashov-skills/solidity-auditor` |
| Solidity lanes | All 12 specialties; two waves of six |
| Raw structured results | 18 findings, 35 leads |
| Final results | 2 validated findings, 6 validated leads |
| PoC tests | 2/2 passing at fork block 25,612,756 |
| Repository tests | 26/26 passing at fork block 25,612,780 |

## In-scope Production Files

- `src/GroveCompounder.sol`
- `src/libraries/UniswapV3SwapSimulator.sol`
- `src/libraries/UniswapV3SwapSimulatorCore.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

## Pinned Dependencies Used for Validation

- `lib/forge-std`: `fc560fa34fa12a335a50c35d92e55a6628ca467c`
- `lib/openzeppelin-contracts`: `bd325d56b4c62c9c5c1aff048c37c6bb18ac0290`
- `lib/tokenized-strategy`: `8c8929f1878e8c5ad78aa0a6dabc877a890f68d9`
- `lib/tokenized-strategy-periphery`: `ab942b245c611cf9747e541ab03b36770c610966`
- `lib/uniswap-v3-core`: `d55e297b938e5b56fd1cf9fe668f5bd385be85b5`

## Isolation Guarantees

- X-ray completed before Solidity-auditor started.
- X-ray artifacts were frozen and supplied as orientation only.
- Solidity lanes received identical source and orientation snapshots plus their own specialty instructions.
- Wave 1 finished before Wave 2 began.
- Raw lane outputs were sealed and hashed before cross-lane deduplication.
- Existing audit runs in the caller repository were not read or supplied to tools.
- yTranche material was used only for run structure and artifact hygiene, never as finding input.

## Known Tool Limitation

X-ray's coverage attempt did not receive a fork URL, so fork-dependent setup reverted and coverage was recorded as unavailable. Focused validation and the full original suite were subsequently run successfully with an Ethereum mainnet fork.
