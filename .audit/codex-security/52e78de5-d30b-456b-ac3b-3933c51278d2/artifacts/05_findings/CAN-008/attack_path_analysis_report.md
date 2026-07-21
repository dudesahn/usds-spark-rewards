# CAN-008 — Active reward auction can make later strategy reports revert

## Decision

- Candidate ID: `CAN-008`
- Instance key: `report-dos:src/GroveCompounder.sol:108`
- Ledger row IDs: `COV-016` and strengthening row `R05W03-L03`
- Attack-path decision: **reportable**
- Impact: **Medium**
- Likelihood: **High**
- Final severity: **Medium**
- Priority: **P2**
- Confidence: **High (0.95)**

This is a real availability vulnerability in the production reward-sale workflow. An unprivileged address can use the configured Auction's public entrypoint to create the external state that makes an otherwise authorized keeper report revert. The denial is recoverable if renewal stops, and no principal loss was shown, but one unsold wei can renew it once per one-day auction window.

## Exact affected locations

The canonical candidate's labeled locations are preserved exactly:

| Label | Location |
|---|---|
| `entrypoint_wrapper` | `src/GroveCompounder.sol:84-118` |
| `root_control` | `src/GroveCompounder.sol:107-109` |
| `concrete_implementation` | `src/GroveCompounder.sol:174-180` |
| `sink` | `lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-520` |

Validation additionally identified `src/GroveCompounder.sol:209-216` as the configuration control: `setAuction` validates `receiver` and `want`, but not kick permissions or active-auction compatibility.

## Factual attack path

1. Management configures an enabled Auction for the strategy and auction sale mode remains enabled. `useAuction` defaults to true (`src/GroveCompounder.sol:21-22`), while `setAuction` checks only the receiver and wanted asset (`src/GroveCompounder.sol:209-216`).
2. The strategy accumulates more GROVE than its production `5,000e18` sale threshold (`src/GroveCompounder.sol:50-53`). Independently, any address obtains one wei of GROVE and pays gas.
3. The attacker transfers that one wei to the configured Auction and calls public `Auction.kick(GROVE)`. The relied-on Auction defaults `governanceOnlyKick` to false and checks governance only when that flag is true (`Auction.sol:80-82,503-511`). The pinned production-factory fork PoC proved that an arbitrary caller can execute this step.
4. The kick records the Auction as active for GROVE (`Auction.sol:518-520`). The active interval is one day (`Auction.sol:74-75`).
5. A legitimate keeper invokes the inherited strategy `report()` workflow. `_harvestAndReport` claims rewards and, because auction mode is enabled and the balance is above threshold, unconditionally calls `_kickAuction` (`src/GroveCompounder.sol:84-109`).
6. `_kickAuction` transfers all GROVE to the Auction and immediately invokes `Auction.kick(GROVE)` without checking `isActive` (`src/GroveCompounder.sol:174-180`).
7. The Auction rejects the second kick with `"too soon"` because the GROVE auction is active (`Auction.sol:503-520`). The revert propagates and atomically rolls back the strategy's reward claim/transfer and report accounting; the fork PoC observed unchanged `lastReport`.
8. After `auctionLength() + 1`, the attacker can call `kick` again using the same unsold wei and renew the block. If the attacker stops, the keeper can report after an uncontested expiry window; management can also reconfigure the sale path.

The path also occurs naturally if one ordinary reward-bearing report starts the auction and another above-threshold report arrives during the active interval. The permissionless pre-kick variant establishes adversarial reachability without relying on keeper misconduct.

## Attack Path Facts

- **Assumptions:** Auction sale mode is enabled; a nonzero Auction configured for this strategy has GROVE enabled; the strategy holds/claims more GROVE than `minAmountToSell`; and the Auction is active when the keeper report reaches it. Permissionless pre-kicking additionally assumes `governanceOnlyKick == false`, which is the relied-on Auction default and was reproduced using a production AuctionFactory clone. Renewal assumes the one-wei lot remains unsold.
- **Context:** The impact is not self-only. A public caller changes shared Auction state and blocks a keeper-only strategy operation used to recognize rewards and update report-time accounting/maintenance. The canonical threat model explicitly protects report/maintenance availability and treats public interference with privileged operations as in scope.
- **In-Scope Status According to the Threat Model:** In scope. `src/GroveCompounder.sol` is first-party production code on the production allowlist; its configured Auction is a directly relied-on external-call boundary. Security invariants 2 and 4 require routine reports to remain permissionlessly available and the Auction integration to tolerate adversarially active reward-token auctions.
- **Exposure:** Public on-chain surface. `Auction.kick(address)` is an external EVM entrypoint and, when `governanceOnlyKick` is false, accepts transactions from arbitrary EOAs/contracts. Conventional ports, HTTP ingress, and load-balancer type are not applicable to this Solidity deployment surface.
- **Identity:** The attacker needs only an arbitrary unprivileged EOA or contract and one wei of GROVE plus transaction gas. The victim operation is performed by an authorized keeper. Management has configuration authority but is not required for exploitation after the vulnerable configuration exists. No service account or managed identity exists in this EVM path.
- **Cross-Boundary Behavior:** Verified. Untrusted public state written in the external Auction crosses into the trusted keeper report path: public donation/kick -> active Auction state -> strategy `_harvestAndReport` -> `_kickAuction` -> active-kick rejection -> report rollback. The pinned fork and bounded fuzz PoCs exercised this boundary.
- **Vector:** `remote`. The attacker reaches the deployed contracts through public blockchain transactions without local, keeper, management, or governance access.
- **Preconditions:** Plausible and low cost: auction mode and a compatible enabled Auction; `governanceOnlyKick == false` for the adversarial pre-kick variant; accrued rewards above the threshold; one wei of GROVE; gas; and transaction timing before the keeper report. The fork used the production `5,000e18` threshold, real staking emissions, and a production AuctionFactory clone.
- **Attacker Input Control:** Yes. The attacker controls the donated GROVE amount (one wei suffices), the public `kick(GROVE)` call, and renewal timing. Fuzz validation covered donations from `1..1e18` and report delays from `0..23 hours`.
- **Category:** Runtime state-machine denial of service / improper sequencing (`CWE-400`, `CWE-841`).
- **Mitigations Already Present:** Keeper authorization prevents the attacker from calling `report()` directly; the sale threshold avoids tiny strategy-originated auctions; active auctions expire after one day; reverts are atomic; and management can change Auction/sale configuration. These bound or recover the impact but do not stop a public caller from pre-positioning the blocking Auction state.
- **Auth Scope:** Public. The attacker's Auction call is unprivileged under the default `governanceOnlyKick == false`; the report itself remains keeper-only. The exploit is the public manipulation of a prerequisite external state, not an authorization bypass on `report()`.
- **Impact Surface:** Runtime availability and data/accounting timeliness. Keeper reports, reward recognition, and report-time maintenance revert; `lastReport` does not advance. No principal loss, withdrawal failure, secret exposure, or permanent state corruption was demonstrated.
- **Target Reach:** Single configured strategy/Auction pair per execution. Any deployed pair using the same public-kick configuration and reaching the reward threshold is affected, but prevalence across all live deployments was not enumerated.
- **Secrets References:** None. No secret, signing key, credential, or sensitive-data flow participates in the path.
- **Counterevidence:** The strongest conflicting evidence is that no exact inventory of live deployed strategy/Auction pairs proves how many currently retain public kick permission. Further, one active period is bounded to one day, reporting recovers if renewal stops, the failed transfer is rolled back, withdrawals were not shown to fail, and management can reconfigure. Deployment prevalence is not dispositive because the first-party integration defaults to auction mode, the relied-on Auction defaults to public kicks, the production-factory fork proves the mechanism and unprivileged reachability, and an ordinary two-report collision exists even without public kick permission. The recovery and no-loss facts are dispositive against High impact, not against reportability of repeatable maintenance denial.
- **Blindspots:** Exact live deployment prevalence and per-instance Auction configuration were not enumerated. The PoC did not prove bidders will always leave the one wei unsold, although an attacker can supply another dust unit if needed. No downstream operational consequence beyond delayed report/reward/accounting maintenance was quantified.
- **Controls:** `onlyKeepers` on strategy reporting/manual auction actions; management-only configuration; Auction token enablement; optional `governanceOnlyKick`; `isActive` rejection; sale threshold; one-day expiry; atomic EVM rollback; and management recovery by selecting a restricted/compatible Auction or another sale mode. The missing control is active-state handling before the strategy transfers and re-kicks.
- **Confidence:** High (`0.95`). Static source/control/sink evidence is confirmed by a pinned mainnet-fork integration suite: three passing tests, including 16 bounded fuzz runs, normal collision, permissionless one-wei pre-kick, renewal, unchanged `lastReport`, and recovery.

## Strongest counterevidence and challenges

| Challenged fact | Strongest contrary evidence | Dispositive? |
|---|---|---|
| In-scope/product surface | The Auction implementation is vendored and exact live strategy/Auction prevalence was not inventoried. | **No.** The first-party `GroveCompounder` integration is explicitly allowlisted, the Auction is its directly relied-on production boundary, and the threat model names auction/report availability. |
| Vector/exposure/auth scope | Keeper `report()` is privileged, and Auction governance can enable restricted kicks. | **No.** The attacker never calls `report()`; the fork proved an arbitrary caller can manipulate the default public Auction state that the keeper path consumes. A possible governance hardening setting is mitigation, not a default-path reachability defeat. |
| Cross-boundary behavior | The failed transfer and claim roll back atomically. | **No.** Atomicity limits fund impact but confirms the availability sink: the whole report rolls back and `lastReport` remains unchanged. |
| Preconditions | Rewards must exceed `5,000e18`, auction mode must be active, and a report must occur during the window. | **No.** Real staking emissions exceeded the production threshold in the fork, auction mode defaults true, and public renewal permits sustained timing control. These are configuration/workflow conditions, not privileged attacker requirements. |
| Impact surface | No principal loss or withdrawal failure was demonstrated; a window expires after one day. | **Partly.** This is dispositive against High impact. It is not dispositive against Medium because the denial is repeatable, affects a shared keeper workflow, and the threat model expressly classifies repeatable report/maintenance denial as Medium. |

## Severity calibration

### Impact: Medium

The proven consequence is shared runtime availability loss: authorized reports revert, reward recognition and report-time maintenance are delayed, and `lastReport` remains stale. The attacker can renew the condition indefinitely at one transaction per window. The canonical threat model explicitly places repeatable report/maintenance denial at Medium. Impact does not reach High because principal remains withdrawable in the evidence, no funds are transferred on the reverted path, no control plane is compromised, and recovery takes one uncontested one-day window or management action.

### Likelihood: High

The relevant surface is public and unprivileged; attacker capital is one wei of GROVE plus gas; the relied-on Auction defaults to public kicks; auction mode is the first-party default; and the fork/fuzz PoC proved the path with the production threshold and real emissions. Exact live-deployment prevalence is unknown, but that lowers breadth certainty rather than the exploitability of an affected configured pair.

### Mechanical matrix and policy pass

The policy matrix maps `impact=medium` plus `likelihood=high` to **Medium**. No hard suppression applies: impact crosses a meaningful actor boundary, preconditions are realistic, and exploitation does not require privileged/operator access. The component is a real production workflow and the lower-privileged attacker path is repository-evidenced and dynamically confirmed. Therefore the final decision is **reportable, Medium, P2**.

## Final conclusion

CAN-008 survives attack-path analysis as a **Medium-severity, P2** vulnerability. The strongest counterevidence limits the issue to recoverable availability harm without principal loss, but it does not suppress a public, low-cost, repeatable denial of the protected report/maintenance workflow.
