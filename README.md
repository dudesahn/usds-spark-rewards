# Spark and Grove USDS compounders

This repository contains both Ethereum mainnet strategies and their APR oracles.
They compile and run in one Foundry project; switching branches is unnecessary.

The integration lives on `merge-grove`. The `oracle` branch at `dded1b2` and
`grove` at `5084dee` remain unchanged as standalone comparison snapshots.
`master` at `59cf4ec` has the same tracked contents as `oracle`.

| | Spark | Grove |
| --- | --- | --- |
| Strategy | `src/SparkCompounder.sol` | `src/GroveCompounder.sol` |
| APR oracle | `src/periphery/SparkCompounderAprOracle.sol` | `src/periphery/GroveCompounderAprOracle.sol` |
| Strategy interface | `src/interfaces/ISparkCompounder.sol` | `src/interfaces/IGroveCompounder.sol` |
| Test suite | `src/test/spark/` | `src/test/grove/` |
| Asset / reward | USDS / SPK | USDS / GROVE |
| TokenizedStrategy API | 3.0.4 | 3.1.0 |
| Reward sales | UniV3 + PSM, or a configured auction | Strategy-owned auction |

The interfaces are deliberately separate: Spark has a single minimum-sale amount
and `setOpenDeposits`, while Grove has per-token minimums and `setOpen`.

## Dependencies and build

Use Foundry v1.5.1 and Solidity 0.8.28 (configured in `foundry.toml`). Initialize
the pinned dependencies after cloning or updating this branch:

```sh
git submodule update --init --recursive
make build
```

Spark's `lib/spark-periphery` is pinned to `3bbde241` and includes TokenizedStrategy
`82806289` (3.0.4). Grove keeps `lib/tokenized-strategy-periphery` at `ab942b24` and
`lib/tokenized-strategy` at `8c8929f1` (3.1.0). Explicit import mappings prevent one
strategy from accidentally compiling against the other's dependency version.
Update these pins intentionally; do not replace Spark's legacy dependency merely
to deduplicate the checkout.

## Tests

Export `PUBLICNODE_ETH_RPC_URL` for current Ethereum state, or put it in an
untracked `.env` file. Python 3.10+ is needed for the maintenance tests; they use
standard-library mocks and do not need Brownie, keys, or network access.

```sh
make test               # Both Foundry suites, coexistence, Python, and pool config
make test-spark         # Spark operations, shutdown, function signatures, APR
make test-grove         # Grove operations, shutdown, function signatures, APR
make test-coexistence   # Deposit into both strategies and redeem independently
make test-python       # Grove maintenance policies, fees, and pool rotation
make check-pools       # Generated Solidity pool list matches the JSON registry
```

The default fork uses **current mainnet state** through `PUBLICNODE_ETH_RPC_URL`.
Tests do not roll back to historical blocks. Changes to live integrations should
surface in CI; controlled reward and liquidity cases are created inside tests.
To reproduce a specific failure, opt into `FORK_BLOCK` and an archive-capable
`ETH_RPC_URL`. `FORK_URL` can explicitly override the provider.

```sh
make test-contract contract=SparkOperationTest
make test-contract contract=GroveOracleTest
make test-test test=test_bothStrategiesKeepIndependentPositions
```

The CI test matrix runs Spark, Grove, and coexistence independently. A separate
job runs the Python tests and pool-config check.

## Deployment entry points

| Script | Purpose |
| --- | --- |
| `script/spark/DeploySparkStrategy.s.sol:DeploySparkStrategy` | New Spark strategy with its existing constructor defaults |
| `script/spark/DeploySparkOracle.s.sol:DeploySparkOracle` | Spark APR oracle only |
| `script/grove/DeployGroveStrategy.s.sol:DeployGroveStrategy` | New Grove strategy with its own auction |
| `script/grove/DeployGroveOracle.s.sol:DeployGroveOracle` | Grove APR oracle only, seeded with the registry's pool list |

`script/grove/DeployGroveStrategyAndOracle.s.sol` is retained as a **historical
record**, not a deployment recommendation. Old receipts stay under their
original `broadcast/` paths; the old shared `DeployStrategyAndOracle` name was
used on both branches. Those paths are not current script entry points.

Use `forge script` without `--broadcast` to simulate deployment. Register a newly
deployed oracle in Yearn's APR registry and configure strategy roles/deposits as
appropriate before using it. A new Spark strategy defaults to UniV3 sales;
configure its auction before enabling auction sales.

## Grove maintenance

Use the Brownie environment for these scripts. Preview first:

```sh
brownie run sync_kyber_v4_pools --network mainnet
brownie run refresh_grove_price --network mainnet
```

Add `BROADCAST=true` to apply the proposed transactions. Pool sync records positive
contributions at 10k, 50k, 100k, 500k, and 1M GROVE, plus the oracle's own 10k quote.
When full, it replaces the least recently contributing idle pool. Existing
contributors are protected; pools with unknown contribution history go first.
`APPLY_REGISTRY=true` saves only the local history and deployment pool snapshot.
Default previews do not save observations.

The **500k GROVE** Kyber quote drives the stored-price refresh and auction-floor
recommendation. The 100k and 1M quotes are comparisons. The reference refresh is
due at 36 hours or a 10% price move; the recommended auction floor is 20% below
the reference. `KYBER_QUOTE_AMOUNT` overrides the reference size in whole GROVE.

Maintenance transactions use a **0.01 gwei tip** and a max fee of **3 × base fee +
tip**. A current base fee above **0.5 gwei**, or unavailable fee data, skips the
send with a warning. Gas is checked before account loading and again before
sending. A skipped pool transaction leaves the local pool files unchanged.

Contract loaders preserve Brownie's global deployment cache. Use `VERBOSE=true`
for full addresses and pool history in maintenance output.
