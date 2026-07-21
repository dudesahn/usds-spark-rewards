# Production-Code Discovery Allowlist

Target revision: `f8f796db93c52432cca0ed26861e94f5aaf20975`

The following first-party production Solidity files are the complete discovery scope:

- `src/GroveCompounder.sol`
- `src/interfaces/IOracle.sol`
- `src/interfaces/IPsmWrapper.sol`
- `src/interfaces/IStaking.sol`
- `src/interfaces/IStrategyInterface.sol`
- `src/interfaces/IUniswapV4StateView.sol`
- `src/libraries/UniswapV3SwapSimulator.sol`
- `src/libraries/UniswapV3SwapSimulatorCore.sol`
- `src/periphery/GroveCompounderAprOracle.sol`

Explicitly excluded from discovery:

- `src/test/**` (validation-only)
- `script/**` and `broadcast/**`
- `.github/**`, `.vscode/**`, repository configuration, coverage, and documentation files
- `lib/**` vendored/submodule dependencies (supporting code may be read only when directly required to understand an allowlisted production path)
- `.audit/**`, `**/.scratchpad/**`, `x-ray/**`, reports, cached analysis, fixtures, build/cache outputs, and generated scanner material

The stock deterministic worklist generator was executed first but does not recognize the `.sol` extension in this plugin version. Its rejected output is preserved as `02_discovery/rank_input.generated.jsonl`; it is not authoritative and must not seed discovery.
