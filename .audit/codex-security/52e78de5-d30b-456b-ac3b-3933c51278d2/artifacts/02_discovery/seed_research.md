
## Source: artifacts/deep_discovery/round-01/worker-01/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior finding, or named vulnerability-family seed was supplied for this worker pass. The authoritative scope anchors are the nine rows in the parent-provided `rank_input.jsonl` and `deep_review_input.jsonl`; neither worklist was regenerated, reranked, overwritten, or reinterpreted.

The local frontier pass therefore used the worker threat model to prioritize: strategy principal/accounting, permissioned reward-sale execution, auction token selection, external-call/reentrancy boundaries, live AMM pricing, oracle pool quorum and selection, signed debt-delta arithmetic, Uniswap simulation arithmetic, and management/configuration controls. Tests were consulted only after source-derived hypotheses existed and only as validation/negative-control evidence.


## Source: artifacts/deep_discovery/round-01/worker-02/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, vulnerability-family, or exact source/sink seed was supplied for this worker. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` each contain the same nine production Solidity files. No external advisory lane was opened, and tests were used only as candidate-local validation/negative-control evidence after source-led discovery.

Repository history was consulted only after the frontier pass. Commit `334030f` (`fix: harden grove reward pricing`) established the present V4 multi-pool/deviation controls, the 50% APR cap, and auction-by-default behavior. It confirms that pricing robustness is an intended security control, but it was not treated as proof of any finding.


## Source: artifacts/deep_discovery/round-01/worker-03/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior-report, or vulnerability-family seed was supplied for this worker. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` contain only production-path inventory rows and no advisory metadata. Accordingly, there are no advisory seed anchors to close and no external seed research was performed.

Local discovery remained anchored to the nine coordinator-supplied production rows. Tests were consulted only after source review as negative-control and intended-behavior evidence; they did not seed candidates. Vendored dependency sources at the exact gitlink revisions were consulted only where necessary to establish the behavior of inherited `_swapFrom`, health-check, and keeper-report controls.

## Source: artifacts/deep_discovery/round-01/worker-04/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior finding, vulnerability-family identifier, or exact file/line seed was supplied for this discovery worker. The authoritative production worklists contain nine source files and no advisory metadata. Accordingly, no external advisory lane was opened and no seed row requires closure.

The review remained anchored to the supplied `rank_input.jsonl` and `deep_review_input.jsonl`. Tests were consulted only after production-code candidates existed, to check intended call patterns; they did not seed candidates.

## Source: artifacts/deep_discovery/round-01/worker-05/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior-finding, or vulnerability-family seed was supplied for this worker. The authoritative worklists contain only production paths and no seed metadata. Accordingly, there are no advisory-anchored rows to research or close.

Local history was consulted only after the production frontier review to understand intended controls around reward pricing; it was not used to seed discovery. The checked-out source remains the evidence source of truth.

## Source: artifacts/deep_discovery/round-01/worker-06/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, or vulnerability-family seed was supplied for this worker. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` contain only production inventory rows and no seed metadata. Accordingly, no external advisory lane was opened, and discovery proceeded from the worker-local threat model and exhaustive review of all nine supplied production rows.

Tests were consulted only after code-grounded candidates existed, as negative-control and intended-behavior evidence. With an explicit mainnet fork URL, all 13 tests in `src/test/Oracle.t.sol` passed at the resolved revision. They confirm ordinary V3/V4 pricing, the supported single-pool V4 fallback, current-state median selection, and the post-computation 50% APR cap. The suite does not exercise adversarial price movement, sandwich execution, or tick-density gas growth, so no exploitability claim relies on those passing ordinary-state tests.

## Source: artifacts/deep_discovery/round-02/worker-01/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, vulnerability-family, or exact source/sink seed was supplied for this worker. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` contain nine production-code rows and no advisory metadata. Accordingly, no advisory-led seed lane was opened.

Local history was used only as negative-control context after code-derived review: recent commits show prior hardening of PSM fee handling, auction initialization, and Grove reward pricing. Those commit messages were not treated as findings or as a substitute for reviewing the checked-out code at `f8f796db93c52432cca0ed26861e94f5aaf20975`.

The ordinary production frontier covered strategy asset/reward flows, external staking/PSM/auction boundaries, management and keeper controls, V3/V4 price selection, arithmetic and delta handling, and the V3 simulation loop. Tests were consulted only after hypotheses arose from production code and were used as confirmation/negative controls.

## Source: artifacts/deep_discovery/round-02/worker-02/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, tag, or vulnerability-family seed was supplied for this worker. The authoritative production worklists are the only discovery inventory. Tests were consulted only after candidates were identified, as candidate-local negative/control evidence; they did not seed discovery.

External advisory research was therefore not applicable. No seed row remains open or deferred.


## Source: artifacts/deep_discovery/round-02/worker-03/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, or named vulnerability-family seed was supplied for this worker. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` contain nine production Solidity files and no advisory metadata. No external advisory lane was opened; discovery proceeded from the worker threat model and the supplied worklists.


## Source: artifacts/deep_discovery/round-02/worker-04/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior finding, or explicit vulnerability-family seed was supplied for this worker pass. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` are production-file inventories rather than advisory seeds.

Local history was consulted only after production-source review to understand recently added oracle controls. Commits `872efb4` and `334030f` introduced configurable V3/V4 pricing and later added V4 pool diversity plus an APR cap. Those commits were not treated as finding evidence or as a scope expansion. No exact seed-target rows were opened.


## Source: artifacts/deep_discovery/round-02/worker-05/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior finding, or explicit vulnerability-family seed was supplied to this worker. The authoritative worklists contain only production file rows and no advisory metadata. Therefore no external advisory seed lane was opened. Discovery used the worker threat model, the nine authoritative production rows, and directly required pinned dependency behavior; tests were consulted only after candidates existed as validation/negative-control evidence.


## Source: artifacts/deep_discovery/round-02/worker-06/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior-report, or explicit vulnerability-family seed was supplied for this worker. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` each contain the same nine production paths, so there are no advisory anchor rows to close. Discovery proceeded from the worker-local threat model and the supplied runtime inventory only.

External state was sampled only as candidate-local reachability evidence, not as an advisory seed: at Ethereum block 25,583,448, the configured default V3 pool returned zero active liquidity; among the four configured V4 pool ids, only `0x9fe7...41f` returned nonzero active liquidity (`2,234,678,351,511,442`, above the `1e12` threshold).

## Source: artifacts/deep_discovery/round-03/worker-01/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, package-version warning, or user-supplied vulnerability-family seed was provided for this worker. No advisory-anchored seed rows were therefore opened.

Repository history was used only as local context after the production files had been reviewed. Recent commits `087c8aa` (`fix: guard grove psm swaps`) and `334030f` (`fix: harden grove reward pricing`) were inspected to understand the intended PSM and oracle controls; they were not treated as findings or as scope substitutes.

Candidate-local external evidence was limited to authoritative deployed-contract/source and Ethereum state checks:

- Etherscan identifies `0x4E41488C19cD35EB4de3083Fc3e204854c75c86a` as a verified `StakingRewards` contract exposing permissionless `stake`, `withdraw`, `totalSupply`, and reward functions.
- An Ethereum JSON-RPC state read on 2026-07-21 found the configured V3 pool with zero active liquidity and only 71 raw USDC units, while the four configured V4 pool IDs returned active liquidity `[0, 2234678351511442, 0, 0]`. This makes the V4 selector's one-quote behavior concretely reachable at the observed state, but later centralized validation should re-check mutable chain state.
- Existing fork suites `Oracle.t.sol` and `Operation.t.sol` could not run because their shared `setUp()` reverted against the available latest-state fork. This is recorded as a runtime proof gap rather than suppression evidence.


## Source: artifacts/deep_discovery/round-03/worker-02/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, tag, or explicit vulnerability-family seed was supplied for this worker. The authoritative worklists contain only the nine production Solidity files, so no advisory-anchored seed rows were opened.

Local Git history was consulted only as repository context. Recent commits named `fix: guard grove psm swaps` and `fix: harden grove reward pricing` explain nearby controls, but neither was treated as an advisory or as evidence that the current revision is vulnerable or safe. Every promoted candidate below is independently grounded in the checked-out `f8f796db93c52432cca0ed26861e94f5aaf20975` source.

## Source: artifacts/deep_discovery/round-03/worker-03/seed_research.md

# Seed Research

No advisory, CVE, GHSA, issue, release-note, package-version, or user-specified vulnerability-family seed was supplied for this worker. No external seed lane was opened. Discovery proceeded from the authoritative production worklists and the worker-specific threat model.

## Source: artifacts/deep_discovery/round-03/worker-04/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release-note, package-version, prior-finding, or named vulnerability-family seed was supplied for this worker. The authoritative worklists contain only production Solidity paths and no advisory metadata. Discovery therefore used the worker threat model and a source-driven high-impact frontier pass.

Tests were not used to seed candidates. After the production source independently exposed the zero-slippage reward swap and spot-price APR paths, `src/test/Operation.t.sol`, `src/test/Oracle.t.sol`, and `src/test/utils/Setup.sol` were consulted only as candidate-local validation evidence about configured modes and existing controls. They confirm that direct Uniswap reward selling is supported, that the oracle intentionally consumes live V3/V4 state, and that tests assert only liquidity/reasonableness/cap behavior rather than manipulation resistance.

Local history and external advisory research were not applicable because there was no advisory identifier or seeded regression to resolve.

## Source: artifacts/deep_discovery/round-03/worker-05/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior finding, or vulnerability-family seed was supplied for this worker pass. The authoritative worklists contain only production-file inventory rows. Accordingly, there are no advisory-seeded constructs or open seed rows; discovery proceeded from the worker threat model and the complete nine-row production worklist.

Local Git history was used only as supporting repository context. It shows that revision `334030f` intentionally added APR caps, V3 liquidity/balance thresholds, and V4 median/deviation selection. Those controls were evaluated directly in the pinned source and were not treated as findings or authoritative security guidance.

## Source: artifacts/deep_discovery/round-03/worker-06/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, vulnerability-family, file/line, or prior-finding seed was supplied for this worker. The authoritative `rank_input.jsonl` and `deep_review_input.jsonl` contain only repository production-file rows and no advisory metadata. Accordingly, no external advisory seed lane was opened. Discovery proceeded from the worker-local threat model and the exact authoritative worklists.

Tests were consulted only after production-code candidates were identified, as validation evidence. They did not seed candidate discovery.


## Source: artifacts/deep_discovery/round-04/worker-01/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, prior report, vulnerability-family hint, or release identifier was supplied to this worker. Per the independent-discovery constraint, no prior worker, canonical candidate, reconciliation, validation, attack-path, audit, scanner, scratchpad, x-ray, or cached finding output was read.

The authoritative seeds were only the nine rows in the supplied `rank_input.jsonl` and `deep_review_input.jsonl`, together with `production_allowlist.md`. All nine rows were kept open until full-file review completed.

After the allowlisted call at `src/GroveCompounder.sol:100` produced a concrete zero-minimum-output hypothesis, the exact pinned dependency commit `yearn/tokenized-strategy-periphery@ab942b245c611cf9747e541ab03b36770c610966` was consulted at `src/swappers/UniswapV3Swapper.sol`. It confirmed that the supplied `_minAmountOut` is forwarded unchanged to Uniswap V3's `exactInputSingle`; this dependency trace validated an existing production-code hypothesis and did not seed discovery.

No external advisory search was applicable.

## Source: artifacts/deep_discovery/round-04/worker-02/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior finding, scanner output, or vulnerability-family seed was supplied for this worker. The authoritative inputs contained only the nine production-code worklist rows and the production allowlist. No prior-round, worker, canonical-candidate, audit, report, scanner, x-ray, cache, or finding artifact was read.

Discovery therefore used a code-first frontier pass. Tests were consulted only after hypotheses existed:

- src/test/Operation.t.sol was used after identifying the zero-minimum-output reward-sale hypothesis, confirming that management can select the Uniswap mode and a keeper report reaches it.
- src/test/Oracle.t.sol and src/test/utils/Setup.sol were used after identifying the spot-oracle hypothesis, confirming the intended V3/V4 fallback behavior and single-pool configurations.
- Exact pinned dependency sources at tokenized-strategy-periphery commit ab942b245c611cf9747e541ab03b36770c610966 and tokenized-strategy commit 8c8929f1878e8c5ad78aa0a6dabc877a890f68d9 were consulted only to establish inherited keeper/report authorization, health-check semantics, and swap minimum-output behavior.

Candidate-local live-state check on 2026-07-21 against Ethereum mainnet:

- The configured V3 pool returned zero active liquidity and 71 USDC base units, so its branch was dormant at the observation point.
- Of the four default V4 pool IDs, only pool 0x9fe7...441f returned liquidity above the code's threshold (2,234,678,351,511,442). The other three returned zero, so the median/deviation procedure currently degenerates to a single spot quote.

These observations support reachability/preconditions only; they are not centralized validation and may change with chain state.

## Source: artifacts/deep_discovery/round-04/worker-03/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, vulnerability-family identifier, or external assessment was supplied as discovery input. Per the worker isolation contract, no prior-worker, prior-round, canonical-candidate, reconciliation, validation, attack-path, report, audit, scanner, scratchpad, x-ray, cached-analysis, or finding output was read. No external seed lookup was applicable.

The sole discovery anchors were the authoritative nine-row `rank_input.jsonl` and `deep_review_input.jsonl`, the production allowlist, the empty resolved `security_guidance.md`, and the worker-local threat model.

## Source: artifacts/deep_discovery/round-04/worker-04/seed_research.md

# Seed Research

No CVE, GHSA, advisory, release, issue, package-version, prior report, or vulnerability-family seed was supplied for this worker. Discovery therefore used only the authoritative nine-file production worklists, the empty resolved `security_guidance.md`, and fresh code-derived hypotheses. Tests were consulted only after production-code hypotheses existed and were used as counterevidence/usage confirmation, not as discovery seeds.

## Source: artifacts/deep_discovery/round-04/worker-05/seed_research.md

# Seed Research

No CVE, GHSA, advisory, prior report, issue, release-note, vulnerability-family identifier, or user-supplied finding seed was provided for this worker. The authoritative nine-row production worklist was therefore reviewed from first principles. No external advisory lookup was used, and no prior-round, worker, canonical, reconciliation, validation, attack-path, report, audit, scanner, scratchpad, x-ray, cached-analysis, or finding output was read.

The only post-hypothesis supporting material read was:

- `src/test/Operation.t.sol` and `src/test/utils/Setup.sol` to confirm that management can select the Uniswap reward-sale path and that keeper-triggered `report()` reaches it.
- `src/test/Oracle.t.sol` to confirm the intended live V3/V4 pricing paths and single-pool V4 configuration.
- The pinned `tokenized-strategy-periphery` implementations of `UniswapV3Swapper`, `Auction`, and `BaseHealthCheck`, solely to trace allowlisted production calls to their delegated sink/control behavior.

These supporting files were used for candidate-local validation only and did not expand or seed discovery scope.

## Source: artifacts/deep_discovery/round-04/worker-06/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, prior finding, or vulnerability-family seed was supplied for this worker. External advisory research was therefore not applicable. Discovery was seeded only from the authoritative nine-row production worklist and independently derived threat model.

Exact local seed rows retained through closure:

- `deep-review:src/GroveCompounder.sol`
- `deep-review:src/interfaces/IOracle.sol`
- `deep-review:src/interfaces/IPsmWrapper.sol`
- `deep-review:src/interfaces/IStaking.sol`
- `deep-review:src/interfaces/IStrategyInterface.sol`
- `deep-review:src/interfaces/IUniswapV4StateView.sol`
- `deep-review:src/libraries/UniswapV3SwapSimulator.sol`
- `deep-review:src/libraries/UniswapV3SwapSimulatorCore.sol`
- `deep-review:src/periphery/GroveCompounderAprOracle.sol`

## Source: artifacts/deep_discovery/round-05/worker-01/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, vulnerability-family, file/line, or source/sink seed was supplied. The authoritative inputs are the nine-row production allowlist and matching JSONL worklists, so there are no advisory-anchor rows to close.

After the production code independently produced an APR-manipulation hypothesis, one primary-source integration statement was checked as candidate-local support: the official Yearn `tokenized-strategy-periphery` repository describes custom APR oracles as integrations for both on-chain debt allocators and off-chain interfaces. This was not used to seed discovery. Source: https://github.com/yearn/tokenized-strategy-periphery

No historical audit, prior worker output, cached analysis, scanner output, report, x-ray output, or scratchpad material was read.


## Source: artifacts/deep_discovery/round-05/worker-02/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version vulnerability hint, comparison report, or vulnerability-family seed was supplied for this worker. The parent-provided production allowlist and its two JSONL worklists are scope inputs, not finding seeds. Therefore no external advisory search was applicable and discovery proceeded from fresh full-file review of all nine rows.

Exact seed-target closure rows: none.

## Source: artifacts/deep_discovery/round-05/worker-03/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, vulnerability-family, or source/sink hint was supplied to this worker. The resolved `security_guidance.md` is empty. Accordingly, no advisory lookup was required and external research was not used to seed discovery.

The independent local frontier pass opened only the nine authoritative production rows. Candidate-local supporting reads were limited to the exact vendored integration definitions needed after hypotheses existed: `UniswapV3Swapper._swapFrom`, `BaseHealthCheck` health-check behavior, and `Auction` permissionless `kick`/active-auction behavior. `src/test/Oracle.t.sol` and the auction setup portion of `src/test/utils/Setup.sol` were read only after the relevant production hypotheses existed, as negative-control/coverage evidence; they did not seed candidates.

Local candidate anchors:

- `src/GroveCompounder.sol:96-105`: the opt-in V3 reward-sale path passes a literal zero minimum output.
- `src/GroveCompounder.sol:174-179`: reward transfer is followed by an unconditional call to the external auction's `kick`.
- `src/periphery/GroveCompounderAprOracle.sol:211-244`: the V3 APR price path consumes current pool state after only liquidity and balance floors.
- `src/periphery/GroveCompounderAprOracle.sol:255-305`: the V4 fallback accepts any positive quote count and filters relative only to that set's median.
- `src/libraries/UniswapV3SwapSimulator.sol:23-46`: an exported exact-input quote converts arbitrary `uint256 amountIn` to signed `int256` without a range check.

## Source: artifacts/deep_discovery/round-05/worker-05/seed_research.md

# Seed Research

No CVE, GHSA, audit issue, release advisory, package-version vulnerability, or user-supplied vulnerability-family seed was provided for this worker. No advisory-derived source file or hunk was used to seed discovery.

After code review independently produced the DEX-price hypotheses, candidate-local confirmation used read-only Ethereum JSON-RPC at block `25583685`:

- the configured Uniswap V3 GROVE/USDC 1% pool returned active `liquidity() == 0`, so the V3 oracle branch was not live at that observation point;
- among the four default V4 pool IDs, only `0x9fe7...341f` returned nonzero active liquidity (`2234678351511442`), while the other three returned zero;
- that singleton pool therefore passed the `1e12` threshold and became the entire effective V4 price set, making its own price its median and defeating any independent-price quorum at that point;
- the observed V4 sqrt price implied approximately `0.013065e18` USDS per GROVE under the contract's formula.

These mutable observations support reachability only. The candidates are grounded in the checked-out Solidity at the target revision, not in current chain state or commit narrative.

## Source: artifacts/deep_discovery/round-05/worker-06/seed_research.md

# Seed Research

No CVE, GHSA, advisory, issue, release, package-version, vulnerability-family identifier, prior audit, scanner result, or user-supplied finding was provided as a discovery seed. No prior worker, prior-round, canonical-candidate, reconciliation, validation, attack-path, report, `.audit`, `.scratchpad`, x-ray, or cached-analysis artifact was read.

The only authoritative scope seeds were the nine rows in the parent-provided `rank_input.jsonl` and exhaustive `deep_review_input.jsonl`, plus `production_allowlist.md`. All nine rows were independently reviewed in full.

After production-code hypotheses existed, candidate-local support used the pinned dependency implementations for the inherited report, health-check, direct swap, and auction call chain, and the repository's `Oracle.t.sol`, `Operation.t.sol`, and `Setup.sol` tests as negative/intent evidence. These supporting files did not add discovery scope.

A read-only Ethereum JSON-RPC check at block 25,583,698 was used only after the V4 spot-price hypothesis existed. It showed the configured V3 pool with zero active liquidity and 71 base units of USDC, three configured V4 pools with zero active liquidity, and configured V4 pool `0x9fe7...441f` with active liquidity `2,234,678,351,511,442`. This is time-sensitive supporting evidence that the fallback can operate with `quoteCount == 1`, not a required premise of the static candidate. Initial `cast call` attempts crashed in this Foundry build during macOS proxy initialization; raw JSON-RPC recovered the read-only check.

## Source: artifacts/deep_discovery/round-05/worker-04-replacement/seed_research.md

# Seed research

No CVE, GHSA, advisory, issue, release, package-version, prior report, or candidate hint was supplied for this replacement discovery worker. The only authoritative seeds were the exact revision, the nine-row production allowlist, and the general high-impact vulnerability families required by the discovery workflow.

The following direct supporting sources were consulted only after local production hypotheses existed:

- The `tokenized-strategy-periphery` sources at gitlink `ab942b245c611cf9747e541ab03b36770c610966` confirmed that `_swapFrom(..., _minAmountOut)` forwards its fourth argument to Uniswap's `amountOutMinimum`, and that the health check compares only reported USDS total assets.
- The `tokenized-strategy` sources at gitlink `8c8929f1878e8c5ad78aa0a6dabc877a890f68d9` confirmed that keeper-only `report()` calls the first-party `_harvestAndReport()` path.
- The official Yearn `tokenized-strategy-periphery` repository documentation states that custom APR oracles are intended for on-chain debt allocators and off-chain interfaces. This was used only to characterize the plausible consumer boundary, not to seed a code finding.
- Existing `src/test/Oracle.t.sol` was read only after the instantaneous-price hypothesis existed. It confirms the intended V3-first/V4-fallback behavior and the 50% APR ceiling, but contains no manipulation test and did not seed discovery.

No external advisory target rows were opened. All candidate and closure rows below arise independently from the allowlisted production code.

