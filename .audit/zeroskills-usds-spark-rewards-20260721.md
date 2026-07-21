# ZeroSkills Audit — usds-spark-rewards

## Executive summary

| Item | Result |
|---|---:|
| Audit date | 2026-07-21 |
| Audited commit | `f8f796db93c52432cca0ed26861e94f5aaf20975` |
| Clean audit worktree | `/private/tmp/zeroskills-usds-spark-rewards-f8f796d-20260721` |
| ZeroSkills lanes | `code-sleuth`, `symmetry-sniper` |
| Validated findings | **0** |
| Plausible leads needing more evidence | **0** |
| Informational notes | **3** |
| Suppressed / disproved leads | **9** |

No storage-persistence or paired-operation vulnerability was validated in the reviewed scope. The strongest symmetry lead was the apparent difference between blocking deposits while the external staking contract is paused and leaving withdrawals locally ungated. A targeted mainnet-fork test disproved the lead: a depositor could still redeem all shares and recover all staked USDS while the staking contract was paused.

No Plamen, Codex Security, sc-auditor, SolidityGuard, solskill, or other audit framework was run. No prior audit report, prior finding, memory-derived finding, or existing synthesis file was used as discovery evidence.

## Methodology and evidence policy

The audit followed the local methodologies at:

- `/Users/dudesahn/Documents/GitHub/codex/skill-research/ZeroSkills/code-sleuth/SKILL.md`
- `/Users/dudesahn/Documents/GitHub/codex/skill-research/ZeroSkills/symmetry-sniper/SKILL.md`

The review used only the requested commit's normal source, interfaces, tests, build configuration, dependency manifests, and the integration-relevant source of pinned dependencies. Prior reports and audit/synthesis artifacts were excluded. Tracked broadcast JSON and `lcov.info` were not used as evidence.

Severity was assessed qualitatively from impact and likelihood:

- Critical / High: practical loss, theft, permanent lock, or privilege compromise with credible reachability.
- Medium: meaningful invariant or accounting failure under realistic conditions.
- Low: constrained security impact or difficult preconditions.
- Informational: useful assurance, maintenance, or test/build observation without a demonstrated security impact.

## Scope reviewed

Primary production scope:

- `src/GroveCompounder.sol`
- `src/periphery/GroveCompounderAprOracle.sol`
- `src/libraries/UniswapV3SwapSimulator.sol`
- `src/libraries/UniswapV3SwapSimulatorCore.sol`
- `src/interfaces/IOracle.sol`
- `src/interfaces/IPsmWrapper.sol`
- `src/interfaces/IStaking.sol`
- `src/interfaces/IStrategyInterface.sol`
- `src/interfaces/IUniswapV4StateView.sol`

Tests and configuration used for intent and verification:

- `src/test/FunctionSignature.t.sol`
- `src/test/Operation.t.sol`
- `src/test/Oracle.t.sol`
- `src/test/Shutdown.t.sol`
- `src/test/utils/Setup.sol`
- `README.md`, `foundry.toml`, `Makefile`, `.gitmodules`, `package.json`

Pinned dependency code reviewed only where it determines storage layout, delegatecall behavior, access checks, asset accounting, or paired operations used by this repository:

- `lib/tokenized-strategy/src/BaseStrategy.sol`
- `lib/tokenized-strategy/src/TokenizedStrategy.sol`
- `lib/tokenized-strategy/src/libraries/TokenizedStrategyLib.sol`
- `lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol`
- `lib/tokenized-strategy-periphery/src/swappers/BaseSwapper.sol`
- `lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol`
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol`

Third-party dependencies were not independently audited beyond these integration surfaces.

---

## Lane 1 — code-sleuth

### Lane verdict

The applicability gates are satisfied: the contracts mutate persistent mappings, packed variables, and a dynamic struct array, while the inherited strategy architecture uses a fixed delegatecall implementation and manual storage slots. No reportable persistence or state-integrity issue was found.

| Classification | Count | Impact | Likelihood | Severity |
|---|---:|---|---|---|
| Validated findings | 0 | None demonstrated | None demonstrated | None |
| Plausible leads | 0 | — | — | — |
| Informational notes | 2 | No direct security impact | N/A | Informational |
| Suppressed leads | 5 | Disproved or non-security-relevant | N/A | Not findings |

### Storage surface and writers

| Component | Persistent state | Main writers | Evidence |
|---|---|---|---|
| `GroveCompounder` | `referral`, `auction`, `useAuction` | constructor; `setReferral`; `setAuction`; `setUseAuction` | `src/GroveCompounder.sol:15-22`, `:38-54`, `:209-236` |
| `UniswapV3Swapper` / `BaseSwapper` | `minAmountToSell`, `base`, `router`, `uniFees` | constructor through `_setMinAmountToSell` / `_setUniFees`; management setters | `lib/tokenized-strategy-periphery/src/swappers/BaseSwapper.sol:10-21`; `lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:25-48`; `src/GroveCompounder.sol:50-53`, `:189-202` |
| `BaseHealthCheck` | `doHealthCheck`, `open`, `allowed`, profit/loss ratios | management setters; one-report health-check reset | `lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol:27-47`, `:74-132`, `:160-163` |
| TokenizedStrategy state | ERC-20 balances/allowances, accounting totals, profit lock, roles, pause/shutdown/reentrancy state | the fixed delegatecall implementation | `lib/tokenized-strategy/src/TokenizedStrategy.sol:222-263`, `:429-436`; schema mirror at `lib/tokenized-strategy/src/libraries/TokenizedStrategyLib.sol:8-46` |
| APR oracle | `management`, `rewardToBaseUniV3Fee`, `v4Pools` | constructor; `setManagement`; pool set/add/remove functions | `src/periphery/GroveCompounderAprOracle.sol:77-101`, `:135-176`, `:338-355` |

`forge inspect` placed all ordinary `GroveCompounder` state in slots `0` through `6`:

- slot 0: `minAmountToSell`
- slots 1–3: `base`, `router`, `uniFees`
- slots 4–6: health-check state and packed `referral`, `auction`, `useAuction`

The oracle uses ordinary slots `0` and `1` (`management` and the packed fee in slot 0, `v4Pools` at slot 1).

TokenizedStrategy data uses the fixed slot:

`keccak256("yearn.base.strategy.storage") - 1 = 0xd2841a5d2692465040bd5e06a6f3b37483952c866e0f304dc0e03f76a1f8a0b0`

The explorer implementation marker uses the standard EIP-1967 slot:

`0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`

The latter is written only during construction to the constant implementation address (`lib/tokenized-strategy/src/BaseStrategy.sol:111-112`, `:133-163`). Runtime fallback delegatecalls also use that constant rather than a mutable or caller-derived slot (`lib/tokenized-strategy/src/BaseStrategy.sol:477-535`).

### Validated findings

None.

There is no demonstrated exploit or failure path that loses, misdirects, or corrupts persistent state.

### Plausible leads needing more evidence

None remain open.

### Informational notes

#### CS-I-01 — Manual storage is fixed and separated from ordinary layout

- **Evidence:** the strategy's ordinary variables occupy slots `0–6`; TokenizedStrategy anchors its complete `StrategyData` struct at a fixed hash-derived slot (`lib/tokenized-strategy/src/TokenizedStrategy.sol:391-436`); the helper library uses the same field order and base slot (`lib/tokenized-strategy/src/libraries/TokenizedStrategyLib.sol:8-46`).
- **Impact:** none observed.
- **Likelihood:** no collision path was identified.
- **Severity:** Informational assurance.
- **Failure path considered:** a mismatched struct definition or overlapping raw slot could redirect accounting/role writes. The two schemas match field-for-field and neither raw slot overlaps ordinary storage.
- **Verification:** `forge inspect GroveCompounder storageLayout`, `forge inspect GroveCompounderAprOracle storageLayout`, and `cast keccak` calculations.

#### CS-I-02 — The EIP-1967 value is an explorer marker, not an upgrade control

- **Evidence:** construction writes the constant TokenizedStrategy address to EIP-1967 (`BaseStrategy.sol:154-163`), but initialization and fallback invoke the compile-time constant directly (`BaseStrategy.sol:111-112`, `:147-152`, `:477-482`, `:509-524`). No upgrade setter exists in the reviewed inheritance chain.
- **Impact:** none observed.
- **Likelihood:** no attacker-controlled implementation selection exists.
- **Severity:** Informational assurance.
- **Failure path considered:** overwrite the EIP-1967 slot and redirect delegatecalls. Runtime delegatecalls do not load their target from that slot, so changing the marker would not redirect execution.
- **Verification:** static trace of both delegatecall sites and the full forked `test_functionCollisions` check.

### False positives and suppressed leads

| Lead | Failure path considered | Evidence / verification | Disposition |
|---|---|---|---|
| `toSwap` and `minRewardAmountToSell` are described as stored “in memory” | Mutate a temporary and lose an intended storage update | They are value-type read caches and are never intended to persist (`src/GroveCompounder.sol:92-109`) | Suppressed: no expected write |
| Oracle copies `v4Pools[i]` into memory | Mutate a copied pool config without persisting it | The copy is read-only inside a `view` selection function (`src/periphery/GroveCompounderAprOracle.sol:255-305`) | Suppressed: view-only use |
| `_setUniV4Pools` deletes before validating every element | A later invalid element leaves the prior pool list erased or partially replaced | Any failed `require` reverts the whole transaction; successful calls repopulate every element before returning (`GroveCompounderAprOracle.sol:338-355`). Existing invalid-input tests pass (`src/test/Oracle.t.sol:90-127`) | Suppressed: atomic rollback |
| `removeUniV4Pool` uses swap-and-pop | Deletion leaves an auxiliary index or count inconsistent | No auxiliary index exists; length and element storage are updated directly (`GroveCompounderAprOracle.sol:166-175`) | Suppressed: no desynchronized state |
| Mapping keys are derived from addresses | Caller chooses a key that overwrites roles/accounting/raw slots | Runtime writes are normal Solidity mapping writes; product configuration mappings are management-restricted, while user-derived balance/allowance keys remain confined to their declared mappings. No raw slot is computed from untrusted calldata | Suppressed: no feasible unrelated-slot write |

### Non-applicable checks

- No diamond or facet architecture.
- No mutable proxy implementation or upgrade function in the reviewed strategy.
- No caller-influenced inline-assembly `sstore` / `sload` slot.
- No bitmap or packed-bit mutation in production storage; simulator bitmaps are external Uniswap pool reads used by a `view` quote.
- No deletion of mappings or structs with an auxiliary on-chain index.

### Open assumptions

- The fixed mainnet TokenizedStrategy address continues to contain immutable code compatible with the pinned `v3.1.0` source. The fork test returned `apiVersion() == "3.1.0"` and all interface/collision checks passed (`src/test/FunctionSignature.t.sol:15-49`).
- The fixed external token, staking, PSM, router, and StateView contracts preserve the interfaces exercised by the tests. Their complete implementations were outside the source-audit scope.

---

## Lane 2 — symmetry-sniper

### Lane verdict

The applicability gate is satisfied by the ERC-4626 deposit/mint/withdraw/redeem family, the strategy's stake/withdraw hooks, APR positive/negative debt deltas, and the oracle's single/batch/add/remove pool-management variants. No attacker-reachable asymmetry that extracts value, bypasses authorization, drifts accounting, or locks funds was validated.

| Classification | Count | Impact | Likelihood | Severity |
|---|---:|---|---|---|
| Validated findings | 0 | None demonstrated | None demonstrated | None |
| Plausible leads | 0 | — | — | — |
| Informational notes | 1 | No direct security impact | N/A | Informational |
| Suppressed leads | 4 | Disproved or non-applicable | N/A | Not findings |

### Candidate pair map

| Pair / variants | Intended invariant | Evidence |
|---|---|---|
| `_deployFunds` / `_freeFunds` | Staking and unstaking the same USDS amount should conserve principal absent an external loss | `src/GroveCompounder.sol:76-82` |
| `deposit` / `mint` vs. `withdraw` / `redeem` | Assets and shares move in opposite directions with conservative rounding and matching pause/reentrancy controls | `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-668`, `:1096-1191` |
| `setUniV4Pool` / `setUniV4Pools` | Single and batch replacement preserve non-empty valid configuration | `src/periphery/GroveCompounderAprOracle.sol:147-156`, `:338-355` |
| `addUniV4Pool` / `removeUniV4Pool` | Add/remove changes one configured pool without duplicates or an empty terminal set | `GroveCompounderAprOracle.sol:158-176` |
| Positive / negative APR debt delta | Adding stake lowers APR; removing stake raises APR for valid deltas | `GroveCompounderAprOracle.sol:109-132`; tests at `src/test/Oracle.t.sol:294-318` |
| `_quoteToken1ForToken0` / `_quoteToken0ForToken1` | Reciprocal quote directions use the same squared price basis | `GroveCompounderAprOracle.sol:374-393` |
| `_swapFrom` / `_swapTo` | Exact-input and exact-output paths reverse token ordering correctly | `lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:67-164` |

### Validated findings

None.

No profitable round trip, asymmetric authorization bypass, forced accounting drift, or permanent lock path was demonstrated.

### Plausible leads needing more evidence

None remain open.

### Informational note

#### SS-I-01 — ERC-4626 rounding and state updates are conservative mirrors

- **Evidence:** `deposit` rounds shares down and `mint` rounds assets up (`TokenizedStrategy.sol:516-567`); `withdraw` rounds shares up and `redeem` rounds assets down (`:578-668`). Both entry variants share `_deposit`, and both exit variants share `_withdraw`, which increments/decrements `lastTotalAssets` and mints/burns shares in opposite directions (`:1096-1191`).
- **Impact:** no value-extraction path observed.
- **Likelihood:** targeted round trip and repository test suite passed.
- **Severity:** Informational assurance.
- **Exploit path considered:** mint shares, immediately withdraw the corresponding assets, and finish with more assets than before because of inconsistent rounding or ledger updates.
- **Verification:** a temporary mainnet-fork test minted `100e18` shares, withdrew the exact assets spent, asserted burned shares were at least minted shares, and asserted the user asset balance did not increase. The test passed and the temporary file was deleted after verification.

### False positives and suppressed leads

| Lead | Failure / exploit path considered | Verification | Disposition |
|---|---|---|---|
| Deposits check `STAKING.paused()` but withdrawals do not | Pause staking after a deposit and trap all user funds because `_freeFunds` cannot exit | Temporary fork test deposited `100e18`, paused staking as its owner, redeemed all user shares, recovered exactly `100e18`, and left zero strategy stake | Disproved; external staking permits withdrawal while paused |
| Add/remove and single/batch V4 pool paths differ | Skip management, duplicate, index, nonzero, or last-pool checks through one variant | `test_managementCanUpdateUniV4Pool`, `test_managementCanSetUniV4Pools`, and `test_managementCanAddAndRemoveUniV4Pool` all passed; source uses `onlyManagement` on every variant (`GroveCompounderAprOracle.sol:147-176`) | Suppressed: parity preserved |
| Positive and negative debt changes use different arithmetic branches | A user-selected sign makes APR move in the wrong direction and influences allocator behavior | `test_oracle` fuzzed both directions for 256 runs and asserted the expected monotonic relationship (`src/test/Oracle.t.sol:294-340`) | Suppressed for valid deltas; out-of-domain deltas only revert this view call |
| Auction and Uniswap reward liquidation have different timing and PSM checks | Switch routes to bypass a required fee or double-count rewards | The paths are alternatives, not inverses: Uniswap realizes USDS in the same report and requires zero PSM fee; auctioning transfers rewards to an asset-denominated auction and realizes returned USDS later (`src/GroveCompounder.sol:84-118`). Both modes' repository tests passed (`src/test/Operation.t.sol:39-82`, `:85-215`) | Suppressed: documented operational asymmetry, no round-trip exploit |

### Additional parity evidence

- `_deployFunds` and `_freeFunds` forward the same amount to `stake` and `withdraw` (`src/GroveCompounder.sol:76-82`). The full fork suite exercised fuzzed deposit/redeem cycles and shutdown exits with no principal deficit (`src/test/Operation.t.sol:217-272`; `src/test/Shutdown.t.sol:11-75`).
- `setAuction(0)` is allowed only after auction use is disabled, while re-enabling auction use requires a nonzero auction (`src/GroveCompounder.sol:209-226`). This prevents either configuration ordering from leaving an active mode with a zero target.
- Withdraw/redeem authorization is centralized in `_withdraw`: a third-party caller must spend share allowance, while the owner path does not (`TokenizedStrategy.sol:1131-1145`). Both exit variants reach the same helper.
- Shutdown prevents new deposits but deliberately keeps exits available; both fuzzed shutdown tests passed for 256 runs (`src/test/Shutdown.t.sol:11-75`).

### Non-applicable checks

- No production batch/multicall entry point exists.
- `_swapTo` is inherited but unreachable from `GroveCompounder`; only `_swapFrom` is used (`src/GroveCompounder.sol:96-105`). A mismatch in the unused internal variant cannot be attacker-reached through this repository's product contract.
- The reciprocal V4 quote functions are `pure` helpers used only for oracle reads. Both round down, so they cannot directly transfer value or mutate accounting.
- `claimRewards` has no meaningful inverse operation.

### Open assumptions

- Valid APR debt deltas are bounded by the staking total supplied by the caller's integration. A negative delta larger than total staked assets or `type(int256).min` reverts the view calculation; no state is changed. This was not elevated because no forced value loss or persistent denial path was established in this repository.
- Mainnet-fork tests used live state rather than a pinned historical block. Results are recorded below, but exact replay should pin the block explicitly.

---

## Verification results

### Build and layout

- `forge build`: passed.
- `forge inspect GroveCompounder storageLayout`: passed; ordinary state occupies slots `0–6`.
- `forge inspect GroveCompounderAprOracle storageLayout`: passed; state occupies slots `0–1`.
- `cast keccak 'yearn.base.strategy.storage'`: returned `0xd284...a0b1`; subtracting one matches the source slot `0xd284...a0b0`.
- `cast keccak 'eip1967.proxy.implementation'`: returned `0x3608...bbd`; subtracting one matches the source slot `0x3608...bbc`.

### Repository fork tests

Command:

```sh
env ETH_RPC_URL=https://ethereum.publicnode.com forge test -vv --fork-url https://ethereum.publicnode.com
```

Result at the then-latest mainnet block reported by Foundry (`25,583,324`):

- 4 suites
- 26 tests passed
- 0 failed
- 0 skipped
- Fuzzed operation, fee, oracle, shutdown, and emergency-withdraw tests ran 256 cases each where configured

### Targeted ZeroSkills symmetry tests

A temporary `src/test/ZeroSkillsSymmetryVerification.t.sol` was created only in the detached audit worktree, run, and deleted. It checked:

1. Mint `100e18` shares, withdraw the exact assets spent, and ensure the user cannot finish with more assets.
2. Deposit `100e18` USDS, pause the fixed staking contract as its owner, redeem all shares, recover exactly `100e18`, and leave no remaining stake.

Command:

```sh
env ETH_RPC_URL=https://ethereum.publicnode.com forge test -vv --fork-url https://ethereum.publicnode.com --match-contract ZeroSkillsSymmetryVerification
```

Corrected result at the then-latest block reported by Foundry (`25,583,333`): 2 passed, 0 failed.

The first paused-withdrawal attempt failed because the test placed a one-shot `vm.prank(user)` before an external `balanceOf` argument evaluation, so the prank was consumed before `redeem`. The test cached the share balance before `vm.prank`, was rerun, and passed. This was a test-harness false positive, not a contract failure.

## Informational build/tooling observation outside the ZeroSkills lanes

`forge build --sizes` compiled successfully but exited nonzero because the imported periphery `Auction` runtime was reported as 24,578 bytes, two bytes above the EIP-170 limit under this repository's compiler/settings. `GroveCompounder` and `GroveCompounderAprOracle` were well below the limit, ordinary `forge build` passed, and tests use the already-deployed AuctionFactory/clone integration. This was not classified as a ZeroSkills finding.

## Commands run — summarized

Repository and worktree integrity:

```sh
git status --short
git cat-file -t f8f796db93c52432cca0ed26861e94f5aaf20975
git show -s --format='%H%n%cs%n%s' f8f796db93c52432cca0ed26861e94f5aaf20975
git worktree list --porcelain
git worktree add --detach /private/tmp/zeroskills-usds-spark-rewards-f8f796d-20260721 f8f796db93c52432cca0ed26861e94f5aaf20975
git submodule update --init --recursive
git submodule status --recursive
git rev-parse HEAD
```

Discovery and evidence collection used `git ls-tree`, `rg`, `rg --files`, `wc -l`, `sed -n`, and `nl -ba` over the scoped source, tests, configuration, and integration-relevant dependency files. Searches covered function inventories, state variables, mappings/arrays/structs, memory/storage references, assembly, raw `sstore`/`sload`, delegatecalls, deletion, push/pop, operation-pair names, access modifiers, and test coverage of each candidate pair.

Build and verification:

```sh
forge build --sizes
forge build
forge inspect GroveCompounder storageLayout
forge inspect GroveCompounderAprOracle storageLayout
cast keccak 'yearn.base.strategy.storage'
cast keccak 'eip1967.proxy.implementation'
env ETH_RPC_URL=https://ethereum.publicnode.com forge test -vv --fork-url https://ethereum.publicnode.com
env ETH_RPC_URL=https://ethereum.publicnode.com forge test -vvvv --fork-url https://ethereum.publicnode.com --match-test test_withdrawRemainsAvailableWhenStakingIsPaused
env ETH_RPC_URL=https://ethereum.publicnode.com forge test -vv --fork-url https://ethereum.publicnode.com --match-contract ZeroSkillsSymmetryVerification
```

## Blockers and environment notes

Resolved blockers:

- The original `/skill-research/ZeroSkills` path was not mounted. The user supplied the correct path under `/Users/dudesahn/Documents/GitHub/codex/skill-research/ZeroSkills`.
- The sandbox initially denied writes to `.git/worktrees` and nested submodule metadata. Approved Git worktree/submodule escalations resolved this.
- The first recursive submodule initialization left one newly cloned nested submodule in a partial checkout. Restoring that temporary nested checkout and rerunning `git submodule update --init --recursive` produced a clean, exact pinned tree.

Non-blocking warnings:

- Foundry could not write its global signature cache under `~/.foundry/cache` in the sandbox.
- The detailed trace's external signature lookup hit public rate limits; the EVM call trace and test result were still produced.
- `forge build --sizes` returned nonzero for the imported Auction size described above; normal build and all relevant tests passed.

No blocker remains for this report.

## New findings, deferred leads, and files written

### New findings

- Validated findings: **none**.
- Plausible leads requiring additional evidence: **none**.

### Suppressed or deferred leads

- Five code-sleuth leads were suppressed as intentional read-only memory use, atomic rollback, consistent swap-and-pop storage, or non-attacker-controlled standard mapping writes.
- Four symmetry leads were suppressed or disproved: paused-staking withdrawal availability, V4 pool-management parity, APR sign parity for valid deltas, and intentional auction-vs-Uniswap timing differences.
- The only open assumptions concern external fixed-contract behavior and unpinned live fork state; neither is a concrete vulnerability lead.

### Exact authored files

Persistent repo-local output:

- `.audit/zeroskills-usds-spark-rewards-20260721.md`

Transient verification file, created in the disposable worktree and deleted after the tests passed:

- `/private/tmp/zeroskills-usds-spark-rewards-f8f796d-20260721/src/test/ZeroSkillsSymmetryVerification.t.sol`

Git also populated the clean worktree and pinned submodules under `/private/tmp/zeroskills-usds-spark-rewards-f8f796d-20260721`; Foundry generated ignored build/cache artifacts there. No production source file was modified.

## Prompting and environment improvements for future audits

1. **Provide the absolute methodology path initially.** The leading `/skill-research/...` path looked like a filesystem-root mount; the actual `/Users/dudesahn/Documents/GitHub/codex/skill-research/...` path would have avoided the initial stop.
2. **Pin an RPC URL and block number.** A fixed fork block makes external-contract behavior, reward periods, pool liquidity, and test results exactly reproducible.
3. **Pre-initialize submodules in the audit worktree or permit scoped `.git/worktrees` writes.** This removes the approval round trips and partial nested-checkout recovery.
4. **Set a writable task-local Foundry cache.** Pointing Foundry cache/signature output into `/private/tmp` would eliminate global cache permission warnings and reduce repeated RPC work.
5. **Specify dependency scope explicitly.** State whether pinned dependencies should receive a full independent ZeroSkills review or only an integration-surface review; this audit used the latter.
6. **Specify whether PoC tests should be retained.** A requested `.audit/pocs/` location would make targeted verification reusable instead of transient.
7. **Include a severity rubric if a particular program's labels are required.** ZeroSkills correctly gates findings but does not define a program-specific impact/likelihood matrix.
8. **Avoid public explorer signature lookups during traces.** Disabling identifier lookup or providing a non-rate-limited API key would keep verbose traces concise and deterministic.
