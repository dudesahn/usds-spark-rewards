# Deduped Findings Report — Grove USDS Compounder

Target commit: `f8f796db93c52432cca0ed26861e94f5aaf20975`

Generated: 2026-07-21

## Input Artifacts

| Tool run | Artifact | Scope / note |
|---|---|---|
| Pashov x-ray + solidity-auditor | `.audit/pashov-grove-f8f796d-20260721T194201Z/synthesis/final-report.md` | X-ray orientation plus 12 Solidity Auditor lanes in two waves. |
| Pashov validation ledger | `.audit/pashov-grove-f8f796d-20260721T194201Z/synthesis/validation-ledger.md` | Promotion / rejection ledger for Pashov candidates. |
| ZeroSkills | `.audit/zeroskills-usds-spark-rewards-20260721.md` | `code-sleuth` and `symmetry-sniper`; no validated findings. |
| Codex Security | `.audit/codex-security/52e78de5-d30b-456b-ac3b-3933c51278d2/report.md` | Deep repository scan with independent validation and PoCs. |
| Codex Security findings | `.audit/codex-security/52e78de5-d30b-456b-ac3b-3933c51278d2/findings.json` | Machine-readable canonical findings. |
| Codex Security validation summary | `.audit/codex-security/52e78de5-d30b-456b-ac3b-3933c51278d2/artifacts/05_findings/validation_summary.md` | Reportable, deferred, and suppressed candidate closure table. |

## Executive Summary

The three independent streams collapse into two canonical reportable findings and a set of deferred or conditional leads:

| Canonical ID | Disposition | Severity | Title | Source support |
|---|---|---:|---|---|
| DEDUP-01 | Reportable finding | Low / Medium | Late deposits can capture reward value accrued before entry | Pashov `G-01`; Codex Security `CS-002` / `CAN-006` |
| DEDUP-02 | Reportable finding | Medium | Active reward auctions can block strategy reports | Codex Security `CS-001` / `CAN-008`; Pashov `L-03` |
| DEDUP-03 | Conditional / deferred finding | Low / Medium conditional | Direct UniV3 reward sale path uses zero min-out | Pashov `G-02`; Codex Security `CAN-001`; ZeroSkills suppressed asymmetry note |
| DEDUP-04 | Deferred oracle lead | Needs downstream validation | APR oracle can rely on manipulable spot or singleton pool pricing | Pashov `L-01` / `L-02`; Codex Security `CAN-002` / `CAN-003` / `CAN-004` / `CAN-005` / `CAN-007` |
| DEDUP-05 | Deployment / trust lead | Deployment-dependent | Auction receiver can change after strategy validation | Pashov `L-04` |

ZeroSkills produced no validated findings and no open plausible leads. Its useful contribution here is negative coverage: it independently checked storage persistence, paired operations, ERC-4626 symmetry, pause/withdraw behavior, V4 pool mutation paths, and route asymmetries without validating a persistence or paired-operation exploit.

## Canonical Findings

### DEDUP-01: Late deposits can capture reward value accrued before entry

Severity: Low / Medium.

Status: Reportable finding.

Merged sources:

- Pashov `G-01`: auction-returned rewards can be diluted by just-in-time deposits before accounting sync.
- Codex Security `CS-002` / `CAN-006`: late deposits can capture reward value accrued before entry.

Affected code:

- `src/GroveCompounder.sol:70-72`: pending rewards are observable through `claimableRewards()`.
- `src/GroveCompounder.sol:89-118`: reports claim and realize GROVE, but report only staked and idle USDS.
- `lib/tokenized-strategy/src/BaseStrategy.sol:225-244`: default `_strategyTotalAssets()` returns `lastTotalAssets()`.
- `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540`: deposits mint shares from the current reported accounting baseline.
- `lib/tokenized-strategy/src/TokenizedStrategy.sol:1096-1117`: deposits deploy loose USDS but increment accounting only by the depositor's stated asset amount.
- `lib/tokenized-strategy/src/TokenizedStrategy.sol:1417-1464`: later reports recognize the old reward value across the enlarged supply.

Deduped description:

`GroveCompounder` prices new deposits using report-boundary USDS accounting that excludes economically accrued GROVE, GROVE already sent to auction, and USDS returned from auction before the next report. A depositor who enters during that gap receives shares at a price that omits value earned by the existing position. Once the reward lot is sold, reported, and unlocked, the new shares receive a pro-rata portion of that pre-entry reward value.

Validation:

- Pashov validated the post-auction-returned-USDS variant with `validation/CodexAuctionDilution.t.sol`.
- Codex Security validated the broader pending-reward/report-boundary variant with a pinned mainnet-fork suite and bounded fuzz tests.

Severity reconciliation:

Pashov rated the auction-returned variant Medium because extraction can approach most of a returned reward lot when the late deposit is large. Codex Security rated the generalized finding Low/P3 after calibrating for no principal insolvency, deposit-gate constraints, capital requirements, performance fees, and profit unlock delay. The deduped severity should be treated as Low / Medium depending on the review program's rubric: medium impact on reward attribution, constrained by economic and access preconditions.

Recommended fix:

Prevent deposits from minting against stale accounting while pre-entry rewards are outstanding. Practical mitigations include closing or limiting deposits while reward auctions are active or proceeds are unreported, and considering a read-only live `_strategyTotalAssets()` estimate that includes idle returned USDS. A live estimate alone does not cover active-auction receivables, so an auction-aware deposit gate remains the stronger mitigation.

### DEDUP-02: Active reward auctions can block strategy reports

Severity: Medium.

Status: Reportable finding.

Merged sources:

- Codex Security `CS-001` / `CAN-008`: active reward auctions can repeatedly block strategy reports.
- Pashov `L-03`: reports can revert when a reward auction is still active.

Affected code:

- `src/GroveCompounder.sol:107-109`: report path kicks an auction whenever claimed rewards exceed the threshold.
- `src/GroveCompounder.sol:174-180`: `_kickAuction()` transfers the full reward balance and immediately calls `Auction.kick()`.
- `src/GroveCompounder.sol:209-216`: `setAuction()` validates receiver/want but not active-state compatibility or kick policy.
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-520`: public `kick()` rejects already-active token auctions with `too soon`.

Deduped description:

In auction mode, `_harvestAndReport()` assumes every above-threshold reward balance can start a fresh GROVE auction. If the configured Auction already has an active GROVE auction, `Auction.kick()` reverts and the entire keeper report rolls back. Codex Security additionally validated a permissionless pre-kick route: an unprivileged account can donate one wei of GROVE to the Auction and call public `kick(GROVE)`, making the next reward-bearing strategy report revert.

Validation:

- Codex Security validated the issue with a pinned mainnet-fork suite: normal report collision, arbitrary one-wei pre-kick, repeatable renewal, unchanged `lastReport`, and recovery once renewal stops.
- Pashov independently identified the same unconditional re-kick control as an operational lead, but did not promote it to a full finding without the public pre-kick proof.

Impact:

The demonstrated impact is repeatable denial of keeper reports, delayed reward recognition, stale `lastReport`, and blocked report-time maintenance. No principal loss or withdrawal failure was demonstrated.

Recommended fix:

Make reward realization idempotent with respect to active auctions. Before transferring rewards, check whether the reward-token auction is active or kickable. If active, leave the claimed rewards in the strategy and let the report complete, then kick after expiry. Restricting public kicks is useful defense in depth, but ordinary report-to-report collisions should also be handled.

## Conditional / Deferred Findings And Leads

### DEDUP-03: Direct UniV3 reward sale path uses zero min-out

Disposition: Conditional / deferred.

Severity: Low / Medium conditional.

Merged sources:

- Pashov `G-02`: direct UniV3 reward-sale mode accepts zero minimum output.
- Codex Security `CAN-001`: direct-sale slippage mechanism confirmed but deferred because production-fork sandwich proof did not demonstrate profitable permanent loss, direct mode is non-default, and no deployed direct-mode instance was established.
- ZeroSkills symmetry note: route asymmetry was reviewed and not elevated because auction and direct-sale paths are alternatives rather than inverse operations.

Affected code:

- `src/GroveCompounder.sol:96-105`: direct branch calls `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)` and then converts USDC through the PSM.
- `src/GroveCompounder.sol:224-226`: management can disable auction mode.
- `lib/tokenized-strategy-periphery/src/swappers/UniswapV3Swapper.sol:72-86`: inherited swapper forwards `_minAmountOut` into Uniswap `amountOutMinimum`.

Current status:

The mechanism is source-confirmed and should be fixed before relying on direct UniV3 sales. It is not an unconditional deployed finding while auction mode remains the default and no profitable production direct-mode exploit has been established.

Recommended fix:

Keep auction mode as the default reward realization path. If direct swaps remain supported, require nonzero min-out derived from a TWAP, a manipulation-resistant oracle, or keeper-supplied bounds checked against an oracle/deviation limit.

### DEDUP-04: APR oracle can rely on manipulable spot or singleton pool pricing

Disposition: Deferred oracle lead.

Merged sources:

- Pashov `L-01`: APR oracle prefers V3 spot quote before V4 median checks.
- Pashov `L-02`: V4 fallback median can collapse to one surviving pool.
- Codex Security `CAN-002`: V3 spot mechanism reproduced but no state-changing allocator consumer or loss established.
- Codex Security `CAN-003`: singleton V4 quote behavior reproduced, including a modeled understatement, but no deployed consumer/manipulation-cost proof established.
- Codex Security `CAN-004`: V3 simulator tick traversal gas concern deferred because modeled traversal remained live under tested gas envelopes.
- Codex Security `CAN-005`: exact `periodFinish` equality mismatch reproduced but no persistent consumer action or loss established.
- Codex Security `CAN-007`: instantaneous staking denominator mechanism reproduced, but meaningful movement required large capital and no state-changing consumer was found.

Affected code:

- `src/periphery/GroveCompounderAprOracle.sol:109-132`: APR calculation and debt delta adjustment.
- `src/periphery/GroveCompounderAprOracle.sol:211-245`: V3 quote branch and usability gate.
- `src/periphery/GroveCompounderAprOracle.sol:255-305`: V4 pool quote gathering, median, and selected-pool logic.
- `src/periphery/GroveCompounderAprOracle.sol:333-335`: deviation check.
- `src/libraries/UniswapV3SwapSimulatorCore.sol:69-179`: V3 simulator current-pool-state traversal.

Current status:

The price-integrity mechanisms are real, but all runs agreed that the oracle is view-only in this scope. Promotion requires evidence that a deployed allocator, debt manager, limit module, or other state-changing consumer uses the APR output in a security-sensitive way, plus a concrete manipulation-cost / profit path.

Recommended follow-up:

Trace deployed consumers of `GroveCompounderAprOracle`. If any consumer makes allocation, limit, accounting, or keeper decisions from this APR, validate whether V3 spot and singleton V4 fallback can move the decision enough to create loss. Consider comparing V3 output against V4 median when both exist, requiring more than one valid V4 quote, and adding TWAP/deviation bounds.

### DEDUP-05: Auction receiver can change after strategy validation

Disposition: Deployment / trust lead.

Source:

- Pashov `L-04`: accepted auction receiver can change after `setAuction()` validation.

Affected code:

- `src/GroveCompounder.sol:209-216`: `setAuction()` validates `receiver()` and `want()` only at configuration time.
- `src/GroveCompounder.sol:174-180`: future kicks trust the stored auction.
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:421-428`: auction receiver setter.
- `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:600-604`: settlement pays the current receiver.

Current status:

This remains deployment-dependent. If the Auction's governance is the same trusted authority as strategy management, it is a trust/configuration assumption. If those authorities can diverge, sale proceeds can later be redirected after the strategy's one-time receiver check.

Recommended follow-up:

Confirm live Auction governance for the intended deployment. Either require governance alignment or re-check `receiver()` and `want()` before every reward kick / settlement-sensitive path.

## Suppressed Or Non-Reportable Cross-Tool Items

| Item | Sources | Deduped disposition |
|---|---|---|
| Storage slot collision or persistence corruption | ZeroSkills `CS-I-01`, `CS-I-02`; code-sleuth suppressed leads | Suppressed. TokenizedStrategy uses a fixed hash-derived slot, the EIP-1967 slot is an explorer marker rather than upgrade control, and no raw-slot overwrite path was found. |
| ERC-4626 deposit/mint/withdraw/redeem asymmetry | ZeroSkills `SS-I-01` | Informational assurance. Rounding and state updates are conservative mirrors. |
| Staking paused withdrawal lock | ZeroSkills suppressed lead | Disproved by targeted fork test: withdrawals remain available while the external staking contract is paused. |
| V4 pool management add/remove/set parity | ZeroSkills suppressed lead | Suppressed. Management checks, duplicate checks, nonzero constraints, and atomic rollback were validated. |
| Negative APR delta underflow / invalid view query | Pashov rejected item; ZeroSkills suppressed valid-delta note | Suppressed. Invalid out-of-domain view query can revert but no state-changing exploit or forced loss was shown. |
| Reward expiry equality timestamp | Pashov rejected item; Codex Security `CAN-005` | Deferred / not reportable. One-timestamp mismatch reproduced, but no persistent consumer action or loss was established. |
| V3 simulator signed cast with oversized direct input | Codex Security `CAN-009` | Suppressed. Sole supported caller fixes the amount to `1e18`; no attacker-controlled in-scope consumer reaches the oversized range. |
| Non-reward-token `kickAuction()` threshold mismatch | Pashov rejected item | Suppressed. Awkward keeper-gated recovery behavior, but no asset-loss path because asset is rejected and unsupported auction tokens revert atomically. |

## Action-Oriented Remediation Order

1. Fix DEDUP-02 first: reports should not revert when a reward auction is already active or publicly pre-kicked.
2. Fix DEDUP-01 next: prevent stale-accounting deposits while pre-entry rewards, active auctions, or unreported auction proceeds exist.
3. Keep direct UniV3 selling disabled unless DEDUP-03 is fixed with a nonzero, oracle-checked min-out.
4. Treat DEDUP-04 as consumer-dependent: do not rely on the APR oracle for state-changing allocation without additional price integrity checks.
5. Confirm Auction governance / receiver immutability assumptions before deployment.

