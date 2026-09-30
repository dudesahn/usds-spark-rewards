# CAN-006 — Late deposits can dilute unreported accrued reward value

## Validation assessment

- **Candidate ID:** CAN-006
- **Instance key:** `report-boundary-accounting:src/GroveCompounder.sol:89`
- **Discovery ledger row:** `w04-file-001`
- **Root control:** `src/GroveCompounder.sol:89-109`
- **Affected locations:** entrypoint/observable state `src/GroveCompounder.sol:70-72`; accounting sink `src/GroveCompounder.sol:111-118`; directly relied-on inherited deposit/accounting `lib/tokenized-strategy/src/BaseStrategy.sol:225-244` and `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540,1096-1117,1400-1514`
- **Advisory/seed anchor:** none
- **Disposition:** **reportable**
- **Verdict:** **CONFIRMED** `[POC-PASS]` `[PROD-FORK]`
- **Confidence:** **high (0.95)**
- **Severity facts:** Impact **Medium** (repeatable diversion of depositor yield, not principal); likelihood **Medium when deposits are open or the attacker is allowlisted** (observable timing and ordinary capital, but capital must remain through settlement and profit unlock); overall **Medium** under the canonical threat model. Likelihood falls to Low if production remains closed to only trusted depositors.

## Rubric

- [x] Establish deposit reachability and distinguish open, closed-unlisted, and allowlisted modes.
- [x] Determine whether claimable/auction-held rewards enter `totalAssets` under the inherited intended accounting model.
- [x] Execute two-depositor share math from pre-entry reward accrual through real auction settlement and final redemption.
- [x] Measure report and profit-locking effects, including immediate versus fully unlocked redemption value.
- [x] Demonstrate positive attacker profit and assess fee, capital-duration, policy, and configuration counterevidence.

## Exact claim and proof condition

**Exact bug.** `GroveCompounder` does not override the inherited report-boundary `_strategyTotalAssets()`. `TokenizedStrategy.deposit()` therefore prices new shares from `lastTotalAssets`, while GROVE already earned by incumbent capital is neither valued nor reserved. A later report recognizes the resulting USDS over the enlarged share supply.

**Observable difference.** Before the late deposit, the production staking fork showed `151.0226272378771 GROVE` claimable while `totalAssets` remained exactly `10,000 USDS`. An equal late deposit received `10,000` shares at 1:1. After those pre-entry rewards were auctioned and `15.258789062499999856 USDS` was reported, the late depositor's immediate redeemable value remained `10,000 USDS` because profit was locked, but after unlock it became `10,007.629394531249999928 USDS`.

**Harm assertion.** `lateRedemption - lateDeposit > 0`, with the captured amount equal to the late depositor's post-entry share fraction of profit derived from the pre-entry reward lot. The assertion passed.

## Feasibility gates

### F1 — Reachability: PASS with explicit configuration condition

- Public/open path: `deposit()` -> `_accrue()` -> `_convertToShares()` -> `_deposit()` is available when `BaseHealthCheck.open == true`; the repository setup explicitly enables open mode.
- Closed-unlisted negative control: the focused test closed deposits and the late depositor reverted with `ERC4626: deposit more than max`.
- Closed-allowlisted positive control: setting `allowed[lateDepositor] = true` made the same deposit succeed.
- Reports remain keeper/management gated, but the attacker need only observe and time an otherwise authorized report.

### F2 — Math bounds: PASS

For incumbent assets `A`, late capital `B`, and net profit `P` from the old reward lot, the late depositor captures approximately:

`capture = P * B / (A + B)`

The specific fork used `A = B = 10,000 USDS` and `P = 15.258789062499999856 USDS`, producing `7.629394531249999928 USDS` of gross late-depositor capture with fees disabled to isolate redistribution. With the inherited default 10% performance fee restored, capture remained positive at `6.865931249141758529 USDS`. The 32-run bounded variant covered `B` from `1,000` through `50,000 USDS` and confirmed the same share-fraction formula.

## Intended accounting and policy assessment

`BaseStrategy._strategyTotalAssets()` explicitly defaults to `lastTotalAssets` to preserve report-boundary accounting and says strategies wanting live accounting must override it. `GroveCompounder` does not override it. This is strong counterevidence against calling the exclusion accidental, but it is not an explicit policy assigning rewards earned before entry to future shares. The canonical threat model independently requires that late participants not capture pre-entry value absent such an explicit protocol policy. No repository security guidance or strategy documentation grants that entitlement.

Accordingly, the intended report boundary explains the mechanism but does not defeat the demonstrated depositor-to-depositor value transfer. A safe policy could instead reserve/checkpoint pending rewards for the pre-entry supply, value them conservatively in live accounting, or require settlement before share issuance.

## Report and profit-locking effects

- The first report claimed and kicked the old GROVE lot but reported zero profit because no USDS had returned.
- Auction USDS remained excluded from `totalAssets` until the second report.
- The second report recognized the USDS and minted locked shares, holding the late depositor at principal immediately after report.
- After the configured one-day unlock, those locked shares no longer protected the incumbent's historical entitlement; profit was distributed across both old and new shares.
- Profit locking is therefore a timing delay, not a reservation control.

## Attacker economics and counterevidence

The equal-deposit case yielded `7.629394531249999928 USDS` gross capture with fees disabled and `6.865931249141758529 USDS` with the default 10% performance fee. The late capital remained committed for roughly 40 hours in this sequence (16-hour auction settlement plus one-day unlock). Under the default fee, gross return on `10,000 USDS` was about `0.06866%`, or roughly `15.0%` simple annualized before gas and risk. This proves positive economic extraction, but not that every small reward lot is profitable after gas.

Material counterevidence and scope limits:

- `open` defaults false at construction; permissionless exploitation requires management to open deposits. An allowlisted but untrusted depositor remains sufficient.
- The attacker must supply capital and wait through auction settlement and profit unlock; flash-only capture is not shown.
- Profitability scales with pending reward value, late share fraction, gas, auction price, and alternative yield. Immaterial reward lots may be uneconomic.
- Performance and protocol fees reduce, but do not reserve or eliminate, the captured amount.
- The tested result is reward-yield redistribution, not USDS principal insolvency.

## Historical-pattern validation

- **Historical precedent:** YES.
- **Similar findings:** Code4rena's Anchor M-05 describes pending yield being stolen because it was not settled to existing users before new balance/shares were issued; Code4rena's Acala M-02 confirms reward accumulation can be sandwiched by temporary deposits. Both were assessed Medium. Sources: [Anchor M-05](https://code4rena.com/reports/2022-02-anchor), [Acala M-02](https://code4rena.com/reports/2024-03-acala).
- **Pattern confidence:** HIGH. The Anchor precedent matches the source, missing checkpoint, share issuance, and reward-capture mechanism directly.

## PoC attempt

- **PoC Required:** YES
- **PoC Class:** integration/property
- **Attempted:** YES
- **PoC Not Attempted Because:** N/A
- **Test File:** `artifacts/05_findings/CAN-006/validation_artifacts/disposable/src/test/CAN006Validation.t.sol`
- **Command:** `forge test --match-contract CAN006ValidationTest --fork-url https://eth.drpc.org --fork-block-number 25583450 --fuzz-runs 32 -vvv`

### Execution result

- **Compiled:** YES (one code compilation; initial runtime attempts were blocked by a sandbox proxy crash and two non-archive/unavailable RPCs before the working archive endpoint)
- **Result:** PASS — 4 tests passed, 0 failed
- **Fuzz variant:** PASS — 32 runs over late deposits from `1,000` to `50,000 USDS`
- **Evidence Tag:** `[POC-PASS]` `[PROD-FORK]`
- **Output:** `artifacts/05_findings/CAN-006/validation_artifacts/forge_full_drpc.log`

The fork uses the production fixed staking contract and production AuctionFactory at Ethereum block `25583450`, while deploying the unmodified target `GroveCompounder` from the immutable revision copy. `deal` funds actors only; staking accrual, share issuance, auction settlement, reports, profit locking, and redemptions execute through original interfaces.

### Key evidence

| Metric | Value |
|---|---:|
| Incumbent deposit | 10,000 USDS |
| Pre-entry claimable/auctioned rewards | 151.0226272378771 GROVE |
| Late deposit | 10,000 USDS |
| Shares issued to late depositor | 10,000 |
| Profit recognized after auction | 15.258789062499999856 USDS |
| Immediate late-depositor redeem value | 10,000 USDS |
| Post-unlock late-depositor redemption | 10,007.629394531249999928 USDS |
| Gross captured pre-entry value, no performance fee | 7.629394531249999928 USDS |
| Gross captured pre-entry value, 10% performance fee | 6.865931249141758529 USDS |
| Incumbent profit instead of full 15.258789062499999856 USDS | 7.629394531249999928 USDS |

## Evidence audit

| Claim | Evidence source | Tag | Valid for refutation? |
|---|---|---|---|
| Claimable GROVE is visible but absent from share-price assets | `GroveCompounder.sol:70-72,89-118`; passing fork assertions | `[CODE]` `[PROD-FORK]` | YES |
| Deposits use inherited report-boundary totals | `BaseStrategy.sol:225-244`; `TokenizedStrategy.sol:516-540,1096-1117` | `[CODE]` | YES |
| Old reward lot becomes USDS profit after actual auction settlement | pinned Auction path and fork log | `[CODE]` `[PROD-FORK]` | YES |
| Profit locking delays but does not prevent late capture | inherited report/unlock logic and final redemptions | `[CODE]` `[PROD-FORK]` | YES |
| Report-boundary accounting is an intentional inherited default | `BaseStrategy.sol:28-30,225-244` comments | `[DOC]` `[CODE]` | Policy counterevidence only |
| Similar reward-checkpoint failures have been assessed Medium | Code4rena Anchor M-05 and Acala M-02 | `[RAG]` | Context only |

No refutation relies on mocks or unverified external behavior.

## Devil's advocate and enabler search

**What makes this exploitable?** Open deposits or an untrusted allowlisted depositor, observable material pre-entry rewards, an authorized report/auction sequence, and capital held through profit unlock. The PoC satisfies each condition.

The canonical deduped candidate inventory was searched for a finding that creates the missing open/allowlisted precondition; none does. CAN-008 can delay reports while an auction is active and may enlarge a timing window, but it is not required. CAN-001 can reduce reward-sale value and therefore weakens rather than enables the captured amount.

## Remaining uncertainty and next step

The validated code path is complete. Remaining deployment questions affect likelihood and economics, not existence: confirm the deployed strategy's current `open`/`allowed` state, keeper/report cadence, typical pending GROVE value, profit-unlock configuration, and transaction costs. Attack-path analysis should preserve the explicit open-or-allowlisted precondition.

## Suggested fix

**Fix:** Architectural change required — checkpoint/reserve pre-entry reward value before minting new shares, or include a conservative read-only value for claimable and auction-pending rewards in share-pricing accounting. No inline diff provided because trustworthy reward/auction valuation and reservation policy span multiple lifecycle states.

## Validation closure

| Ledger row ID | Instance key | Advisory/source | Seed anchor | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|---|---|
| `w04-file-001` | `report-boundary-accounting:src/GroveCompounder.sol:89` | none | none | `src/GroveCompounder.sol:89-109` | open or allowlisted `deposit()` after observable accrual | `src/GroveCompounder.sol:111-118`; inherited stale share conversion | reportable | Intentional report-boundary default, closed-by-default construction, capital/unlock cost; no explicit policy grants pre-entry rewards to new shares | yes |
