# X-ray + Solidity-auditor Audit Artifacts

Target commit: `f8f796db93c52432cca0ed26861e94f5aaf20975`

## Outcome

- 2 validated Medium-severity findings
- 6 validated leads with explicitly unproven downstream impact
- 12 independent Solidity-auditor specialty outputs
- 2 focused fork PoCs passed
- All 26 original repository tests passed on a mainnet fork

Start with [`solidity-auditor/security-review-f8f796d.md`](solidity-auditor/security-review-f8f796d.md). The complete disposition of all raw clusters is in [`solidity-auditor/validation/validation-ledger.md`](solidity-auditor/validation/validation-ledger.md).

## Artifact Separation

- `x-ray/` is the complete first tool run.
- `solidity-auditor/` is a separate all-lane run. Its `scope/x-ray-orientation.md` records the only explicit cross-tool input.
- `solidity-auditor/raw/` contains the 12 sealed lane outputs; lanes did not read one another.
- Existing `.audit` runs were neither read nor modified.

The x-ray verdict was **FRAGILE**: unit tests and partial NatSpec exist, but stateful fuzz/formal properties and first-party timelock protections were absent for a dependency-heavy strategy and newly changed pricing subsystem.
