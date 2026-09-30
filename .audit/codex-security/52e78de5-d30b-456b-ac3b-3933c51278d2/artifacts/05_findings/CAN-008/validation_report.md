# CAN-008 — Active reward auction can make later strategy reports revert

## Validation assessment

- Candidate ID: `CAN-008`
- Instance key: `report-dos:src/GroveCompounder.sol:108`
- Coverage ledger row: `COV-016`
- Strengthening ledger row: `R05W03-L03` / candidate `R05W03-C02`
- Root control: `src/GroveCompounder.sol:107-109`
- Affected locations: `src/GroveCompounder.sol:84-118,174-180,209-216`
- Directly relied-on sink: `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-520`
- Disposition: **reportable / confirmed**
- Confidence: **high (0.95)**
- Severity: **Medium** (Medium impact, High likelihood under the default public-kick auction configuration)
- Evidence tag: **[POC-PASS] [PROD-FORK]**

The candidate survives validation. A pinned mainnet-fork integration test proved both the ordinary state-machine collision and the permissionless griefing variant. The latter costs one wei of the reward token plus gas, can be renewed after every auction window using the same unsold wei, and prevents `report()` from updating `lastReport`. There is no demonstrated principal loss, and reporting recovers after the active interval if the attacker stops or management reconfigures the sale path.

## Rubric

- [x] Confirm the Auction's exact active-state rejection: `kick()` reaches `_kick()`, which rejects `isActive(_from)` with `"too soon"`.
- [x] Confirm the strategy's unconditional kick path: every auction-mode report with reward balance above threshold transfers the entire balance and calls `Auction.kick()` without checking active state.
- [x] Reproduce normal two-report reachability: with the constructor's `5,000e18` threshold restored, a first reward-bearing report starts an auction and a second report 12 hours later reverts.
- [x] Reproduce permissionless pre-kick/config feasibility: against the production AuctionFactory clone on a mainnet fork, an arbitrary address donates one wei and directly calls `kick()`; no keeper or management privilege is needed.
- [x] Establish duration, maintenance impact, and recovery: the blocked report leaves `lastReport` unchanged; the attacker can renew after `auctionLength() + 1` using the same wei; reporting succeeds if a subsequent window expires without renewal.

## Exact claim, observable harm, and assertion

**Exact bug.** `GroveCompounder._harvestAndReport()` calls `_kickAuction()` whenever `useAuction` is true and claimed rewards exceed the configured threshold. `_kickAuction()` transfers rewards and calls the external Auction without first checking whether the same token auction is active. The Auction rejects a second active kick, reverting the entire keeper report.

**Claimed harm.** Routine keeper reporting, reward recognition, and report-time maintenance are unavailable while an adversarially active reward auction exists, and an unprivileged caller can renew that condition indefinitely at one transaction per auction window.

**Observable proof.** A keeper `report()` call reverts with `"too soon"`; `strategy.lastReport()` remains unchanged; the transfer into the Auction is reverted atomically. After the active window expires without attacker renewal, the same keeper report succeeds and advances `lastReport`.

**Exact assertions.** The PoC uses `vm.expectRevert("too soon")` around the real `strategy.report()` entrypoint and then asserts equality of `lastReport` before and after the blocked attempt. Recovery asserts `lastReport` increases after expiry.

## Source, control, sink, and reachability

| Element | Evidence |
|---|---|
| Attacker source | One wei reward-token transfer to the configured Auction, followed by direct public `Auction.kick(rewardToken)` [PROD-FORK] |
| Natural source | A successful prior strategy report starts the reward auction; real staking emissions continue accruing [PROD-FORK] |
| Closest control | `toSwap > minAmountToSell[REWARDS_TOKEN]`, `useAuction`, and a nonzero configured Auction; none checks auction activity [CODE] |
| Sink | `Auction._kick()` rejects `isActive(_from)` with `"too soon"` [CODE], reproduced against the production factory clone [PROD-FORK] |
| Harm boundary | Keeper-only `report()` is the victim operation; the attacker controls external Auction state rather than keeper credentials [PROD-FORK] |
| Recovery | Wait until the attacker stops and `auctionLength() + 1` elapses, or management changes the auction/sale configuration [CODE]/[PROD-FORK] |

### Feasibility gates

- **F1 Reachability: PASS.** The attacker does not need to call `report()`. An arbitrary address can transfer the enabled reward token to the configured Auction and call `kick()` directly. A routine authorized keeper report then reaches `GroveCompounder._harvestAndReport -> _kickAuction -> Auction.kick` and reverts.
- **F2 Bounds: PASS.** The PoC restores the production constructor threshold of `5,000e18`, uses a fresh strategy with `1,000,000e18` USDS staked, and relies on the real reward schedule at block `25583832`. Rewards exceed the threshold after one day and again during the active interval. The griefing input is one wei; the bounded fuzz case covers donations through `1e18` and report delays through 23 hours.

## Dynamic validation

### PoC Attempt

- PoC Required: YES
- PoC Class: integration
- Attempted: YES
- PoC Not Attempted Because: N/A
- Test File: `validation_artifacts/disposable_repo/src/test/CAN008Validation.t.sol`
- Command: `forge test --match-contract CAN008ValidationTest --fork-url https://ethereum.publicnode.com --fork-block-number 25583832 --no-storage-caching --cache-path cache --out out --fuzz-runs 16 -vv`

### Execution Result

- Compiled: YES (two harness iterations; the first removed an invalid deployed-version getter assumption without changing the target or harm assertion)
- Result: PASS
- Fuzz variant: PASS (16 runs; donation `1..1e18`, delay `0..23 hours`)
- Evidence Tag: [POC-PASS] [PROD-FORK]
- Output: 3 passed, 0 failed, 0 skipped

```text
[PASS] testFuzz_CAN008_publicPreKickBlocksThroughoutActiveWindow(uint96,uint32) (runs: 16)
[PASS] test_CAN008_normalTwoReportCollisionAndRecovery()
[PASS] test_CAN008_permissionlessDustPreKickBlocksReportAndRecovery()
Suite result: ok. 3 passed; 0 failed; 0 skipped
```

The harness deploys the target strategy code and creates its Auction through the real mainnet AuctionFactory at the pinned block. All source, build cache, output, PoC, and logs live under this finding's `validation_artifacts/`; the immutable target worktree remained clean.

## Evidence audit

| Claim | Evidence source | Tag | Proof quality |
|---|---|---|---|
| Report unconditionally kicks above threshold | Target `GroveCompounder.sol:84-109,174-180` | [CODE] | Proof-grade |
| Active kick rejects with `"too soon"` | Pinned vendored Auction source and executed production factory clone | [CODE] [PROD-FORK] | Proof-grade |
| Arbitrary caller can pre-kick after one-wei donation | Executed mainnet-fork test against factory clone | [PROD-FORK] | Proof-grade |
| A second normal report collides within 12 hours | Executed mainnet-fork test with real staking emissions and production threshold | [PROD-FORK] | Proof-grade |
| Same unsold wei can renew the denial | Executed mainnet-fork renewal sequence | [PROD-FORK] | Proof-grade |
| Reporting recovers if renewal stops | Executed mainnet-fork recovery sequence | [PROD-FORK] | Proof-grade |

No mock or unverified-external behavior supports the disposition.

## RAG / historical precedent

The Codex environment does not load the vulnerability-database MCP, so the required web fallback searched GitHub for permissionless auction-kick and dust-based operational blocking patterns. No exact historical match for this Yearn Auction integration was found. A related Ajna audit inventory records dust deposits continuously blocking settlement, which supports the general state-griefing class but is not treated as proof of this instance. Historical precedent: **analogous only**. Similar exact exploits: **none found**. Pattern confidence: **HIGH because the local mainnet-fork PoC is conclusive**, not because of RAG.

## Severity facts

- Impact is availability and delayed reward/accounting recognition; no direct principal loss was demonstrated.
- A single active interval is bounded by `auctionLength()` (one day in the relied-on Auction code).
- The attacker can renew after each interval with the same unsold one wei, so the effective denial is repeatable rather than inherently capped at one day.
- Attacker capital is one wei of the reward token; recurring cost is gas for one kick per window.
- Preconditions are the default auction sale mode, an enabled reward token, and a reward-bearing keeper report above the production `5,000e18` threshold.
- Keeper privileges do not prevent the attack because the attacker manipulates the public external Auction before the keeper transaction.
- Recovery requires an uncontested expiry window or management action (for example, changing to a compatible restricted Auction or temporarily changing the sale mode).

These facts place the issue at **Medium** under the canonical threat model's explicit floor for repeatable report/maintenance denial. Lack of fund loss prevents High severity.

## Devil's advocate, chain, and counterevidence

**What makes it exploitable?** A publicly kickable configured Auction, any nonzero donated reward-token balance, and a later above-threshold strategy report. All three were established dynamically. The natural prior-report path independently creates the same active state.

**Bidirectional role analysis.** Keeper-to-user harm is limited to omission/timing because a keeper could choose not to report. User-to-keeper exploitation is proven: an unprivileged user controls the external active-auction precondition and forces an otherwise authorized keeper report to revert. The keeper cannot clear that state through `report()`.

**Chain/enabler search.** The canonical inventory itself supplies both enablers: natural reward accrual/prior reporting and the `R05W03-C02` donation/pre-kick variant. No other candidate is needed to make the attack reachable.

**Counterevidence and scope.** The transfer into the Auction reverts atomically, withdrawals were not shown to fail, and reporting recovers if the attacker stops. Management can reconfigure the sale integration. These facts limit impact but do not suppress the proven repeatable denial.

## Remaining uncertainty

The PoC uses a fresh strategy and Auction clone created through the production factory at the pinned block; it does not inventory every currently deployed strategy instance or its exact live Auction address/configuration. This is a deployment-prevalence gap, not a mechanism or reachability gap: the repository's default setup and factory clone reproduce public kickability, and ordinary two-report collision does not depend on attacker kick permissions.

Minimal further step, if deployment prevalence is required: enumerate deployed strategy/Auction pairs and read each live reward-token enablement and kick-permission configuration.

## Suggested fix

```diff
 function _kickAuction(address _token, uint256 _balance) internal {
     require(_token != address(asset), "!asset");
     address _auction = auction;
     require(_auction != address(0), "!auction");
+    if (Auction(_auction).isActive(_token)) return;
     ERC20(_token).safeTransfer(_auction, _balance);
     Auction(_auction).kick(_token);
 }
```

Fix scope: leave newly claimed rewards in the strategy while that token's Auction is active, allowing the report to complete; a later report transfers and kicks after expiry. Separately restricting public kicks reduces the griefing variant but does not solve the ordinary two-report collision. Verified: NO — the minimal fix was not applied because this validation task writes only finding artifacts.

## Validation closure

| Ledger row ID | Instance key | Advisory/source | Seed anchor | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|---|---|
| COV-016 / R05W03-L03 | `report-dos:src/GroveCompounder.sol:108` | Discovery CAN-008; strengthening R05W03-C02 | `src/GroveCompounder.sol:174-180` | `src/GroveCompounder.sol:107-109` | prior report or public donation + `Auction.kick`; keeper `report()` | unconditional `_kickAuction`; active `Auction.kick` rejection | reportable | Exact deployed-instance prevalence not enumerated; harm is availability, not fund loss | yes |

## Artifacts

- `validation_artifacts/disposable_repo/src/test/CAN008Validation.t.sol`
- `validation_artifacts/forge_test.log`
- `validation_artifacts/attempt_notes.log`
- `validation_artifacts/README.md`
