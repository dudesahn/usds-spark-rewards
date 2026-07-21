# CAN-006 — Late deposits can dilute unreported accrued reward value

## Decision

- **Attack-path policy decision:** reportable
- **Impact:** Medium
- **Likelihood:** Medium, conditional on deposits being open or the attacker being allowlisted
- **Final severity:** Low
- **Priority:** P3
- **Confidence:** High (0.95)

The path is a real cross-depositor economic vulnerability on a production strategy surface. It is not self-only, privileged-only, or dependent on an unrealistic precondition. The final severity is nevertheless Low because the required mechanical policy matrix maps `impact=medium` and `likelihood=medium` to Low. If a specific deployment is closed and its allowlist contains only trusted depositors, likelihood falls to Low and the same matrix would suppress the finding; the repository does not establish that deployment-specific condition.

## Candidate identity and exact affected locations

- **Candidate ID:** `CAN-006`
- **Instance key:** `report-boundary-accounting:src/GroveCompounder.sol:89`
- **Ledger row ID:** `w04-file-001`
- **Entrypoint / observable state** (canonical candidate label: `entrypoint_wrapper`): `src/GroveCompounder.sol:70-72`
- **Root control:** `src/GroveCompounder.sol:89-109`
- **Accounting sink:** `src/GroveCompounder.sol:111-118`
- **Concrete inherited report-boundary control:** `lib/tokenized-strategy/src/BaseStrategy.sol:225-244`
- **Concrete inherited deposit/accounting:** `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540,1096-1117,1400-1514`

These locations are carried forward exactly from validation. Supporting reachability evidence is `lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol:35-39,121-131,189-191`: deposits are public when `open` is true and otherwise require `allowed[receiver]`.

## Service and workflow mapping

`GroveCompounder` is an on-chain Yearn V3 tokenized strategy that accepts USDS, stakes it in a fixed external staking contract, earns GROVE, and realizes GROVE into USDS through an auction or direct swap route. Share issuance and report accounting execute through the directly relied-on TokenizedStrategy implementation. The relevant workflow is:

`USDS deposit -> staked principal -> GROVE accrual -> late share issuance -> authorized report/auction settlement -> profit recognition and unlock -> redemption`.

Depositors and transaction-ordering actors are untrusted under the canonical threat model. Management and keepers retain configuration/report roles, but exploitation does not require either role to be compromised or malicious.

## Factual attack path

1. An incumbent deposits USDS, receives strategy shares, and the strategy stakes the assets. GROVE then accrues for the incumbent-funded position. `claimableRewards()` exposes the accrued amount at `src/GroveCompounder.sol:70-72`, but the inherited `_strategyTotalAssets()` returns only `lastTotalAssets` at `lib/tokenized-strategy/src/BaseStrategy.sol:225-244`.
2. An untrusted actor observes a material claimable reward balance and a forthcoming ordinary report. This uses public on-chain state and transaction ordering; it does not require a keeper key or private information.
3. While deposits are open, or while the actor is an untrusted allowlisted depositor, the actor calls inherited `deposit()` before reward realization. The deposit path at `lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540` prices shares from the report-boundary asset total, and `1096-1117` transfers assets, increments `lastTotalAssets`, and mints the resulting shares. The already-accrued GROVE is not valued or reserved for the pre-entry supply.
4. An authorized keeper performs the normal report sequence. `src/GroveCompounder.sol:89-109` claims the GROVE and sells it or kicks it into the configured auction. In auction mode, the first report can transfer the old reward lot while `src/GroveCompounder.sol:111-118` still reports only idle plus staked USDS; auction inventory is not part of share-price assets.
5. After auction settlement returns USDS, a later authorized report includes those proceeds at `src/GroveCompounder.sol:111-118`. The inherited report logic at `lib/tokenized-strategy/src/TokenizedStrategy.sol:1400-1514` recognizes profit and locks profit shares against the already enlarged share supply.
6. Profit locking delays, but does not reserve, the historical reward entitlement. Once the configured unlock completes, the late depositor redeems its pro-rata share of the USDS derived from GROVE that was claimable before entry, reducing the incumbent's reward yield by the same amount.

The production-fork PoC demonstrated this exact path at Ethereum block `25583450`: 151.0226272378771 pre-entry GROVE became 15.258789062499999856 USDS of reported profit; an equal 10,000-USDS late deposit captured 7.629394531249999928 USDS after unlock with fees disabled and 6.865931249141758529 USDS with the default 10% performance fee. Four tests and the 32-run bounded deposit-size fuzz variant passed.

## Attack Path Facts

- **Assumptions:** Deposits are open or the attacker is individually allowlisted; the attacker can observe a material accrued reward balance and keep capital committed through ordinary auction settlement and profit unlock; an authorized keeper eventually performs normal reports; the fixed external contracts behave as exercised in the production-fork validation. No malicious keeper, management compromise, flash-only funding, or external-contract compromise is assumed.
- **Context:** The impact crosses a meaningful depositor boundary, not a self-only boundary. The fork showed USDS yield derived from the incumbent's pre-entry GROVE moving to the late depositor, with the incumbent receiving correspondingly less of the old reward lot.
- **In-Scope Status According to the Threat Model:** In scope. `GroveCompounder` is an explicitly allowlisted first-party production file, depositor timing is an enumerated attack surface, and invariant 3 specifically requires that late participants not capture pre-entry value absent an explicit policy allowing it.
- **Exposure:** Conditional public on-chain exposure. When `open == true`, any address can reach `deposit()`; when false, only an address with `allowed[receiver] == true` can do so. The repository setup explicitly exercises open mode, but current production `open` and `allowed` state is not recorded. Traditional ports, ingress controllers, and load balancers are not applicable to this Solidity deployment.
- **Identity:** The attacker is an ordinary depositor EOA or contract and needs no protocol role in open mode. In closed mode, the attacker needs depositor allowlist status but no keeper or management privilege. A trusted keeper supplies only the ordinary later `report()` transaction; management alone controls `setOpen` and `setAllowed`.
- **Cross-Boundary Behavior:** Verified. The evidence chain is pre-entry `earned()` GROVE -> stale report-boundary share issuance -> conversion/settlement into USDS -> profit recognition across old and new shares -> positive late-depositor redemption gain and matching incumbent dilution.
- **Vector:** `remote`. The attacker submits ordinary transactions to the public blockchain surface and can use public state/mempool ordering. Reachability remains conditional on the deposit gate.
- **Preconditions:** Plausible but economically constraining. The attacker needs open or allowlisted deposit access, material unreported rewards, sufficient USDS capital, an observable report/settlement sequence, and capital duration through settlement and unlock. Validation demonstrated roughly 40 hours in the tested auction path. Closed-unlisted access is unachievable and was confirmed to revert; small reward lots may be uneconomic after gas and opportunity cost.
- **Attacker Input Control:** Yes. The attacker controls deposit timing, deposit size, sender/receiver identity, and redemption timing. The attacker need not control reward creation or report authorization; it waits for normal accrual and keeper actions.
- **Category:** Economic/accounting flaw; reward checkpoint and share-pricing mismatch (`CWE-682`, `CWE-841`).
- **Mitigations Already Present:** Deposits default closed; management can open deposits or allowlist individual depositors; keeper/management authorization gates reports; profit locking delays newly reported yield; performance/protocol fees reduce distributable profit; health checks constrain exceptional reported profit; reward-sale thresholds avoid uneconomic small sales. None reserves pre-entry reward value for pre-entry shares.
- **Auth Scope:** Public when open; depositor-allowlisted when closed. The exploit is not admin-only. A closed strategy whose allowlist is limited to trusted actors removes the realistic attacker path for that deployment.
- **Impact Surface:** Runtime economic/accounting state and depositor asset entitlement. The proven loss is incumbent reward yield, not USDS principal insolvency, secret disclosure, identity compromise, or control-plane takeover.
- **Target Reach:** Single strategy deployment per exploitation sequence; the code pattern applies to every `GroveCompounder` instance that retains this inherited report-boundary accounting and admits an untrusted depositor under the required timing conditions.
- **Secrets References:** None. No private key, credential, secret reference, or sensitive-data flow is used. Keeper/management keys remain uncompromised.
- **Counterevidence:** The inherited implementation explicitly documents report-boundary accounting as an intentional default; deposits default closed; reports are keeper-gated; and profit locking plus fees reduce or delay extraction. This evidence narrows likelihood and economics, but it does not defeat the demonstrated cross-depositor transfer under the threat model's explicit late-entry invariant. The strongest potentially dispositive fact would be proof that a particular production deployment is closed and all allowlisted depositors are trusted; the repository does not provide that proof.
- **Blindspots:** Current deployed `open`/`allowed` values, keeper/report cadence, typical pending GROVE value, auction price and settlement duration, profit-unlock configuration, gas costs, alternative yield, and whether an explicit external protocol policy grants new shares a portion of pre-entry rewards are not established by the repository. These affect likelihood/economics, not the validated mechanism.
- **Controls:** Deposit gating blocks closed-unlisted actors; role checks prevent the attacker from directly reporting; locked-profit shares prevent immediate post-report extraction; fees and capital duration lower returns. The fork negative control proved the closed-unlisted gate, while the allowlisted positive control and fee-enabled test proved that the remaining path persists when authorized to deposit.
- **Confidence:** High (0.95) in the code path, boundary crossing, and positive extraction because the production-fork and fuzz PoCs passed. Confidence in current-production exploit frequency is lower because live deposit gating and economic inputs remain unknown.

## Strongest repository counterevidence and challenges

1. **Intentional report-boundary accounting.** `BaseStrategy.sol:28-30,225-244` expressly says the default preserves report-boundary accounting. This is strong evidence that the accounting mode itself is intentional. It is not dispositive: neither that comment nor repository security guidance explicitly assigns rewards earned before entry to future shares, while threat-model invariant 3 says the opposite absent an explicit policy. The PoC proves an actual cross-user transfer rather than a merely theoretical valuation difference.
2. **Closed-by-default deposit gate.** `BaseHealthCheck.open` defaults false, and validation proved that a closed/unlisted deposit reverts. This is dispositive for an individual deployment that remains closed to only trusted depositors. It does not globally suppress the candidate because the same repository supports and tests open mode, and an untrusted allowlisted depositor reaches the path. The actual live gate state is an explicit residual gap.
3. **Keeper-gated reports.** The attacker cannot call `report()` without a role. This does not defeat reachability because the attacker only times entry before a normal authorized report; no keeper collusion or interference is required.
4. **Profit locking, fees, and capital duration.** These reduce or postpone capture. They are not complete controls: the fork measured positive capture after a one-day unlock and with the default performance fee restored. They justify Medium likelihood and cap impact below principal-loss classes.

## Separate impact calibration

**Impact: Medium.** The vulnerability causes a real, repeatable cross-depositor diversion of accrued reward value and can recur at report boundaries. The captured amount is approximately `P * B / (A + B)`, where `P` is net old reward profit, `A` incumbent assets, and `B` late capital. It is bounded by the old reward lot and late share fraction, and the PoC showed reward-yield redistribution rather than principal insolvency, unbacked shares, strategy takeover, or irreversible loss of most assets. This matches the threat model's Medium class for meaningful recurring reward loss.

## Separate likelihood calibration

**Likelihood: Medium under the stated open-or-allowlisted condition.** The attack uses ordinary deposit/redemption transactions, public observable state, and realistic timing, and the fork demonstrated reachability and positive economics. Likelihood is reduced by the conditional deposit gate, capital requirements, settlement plus unlock duration, uncertain report cadence, gas/opportunity costs, fees, and the need for a material reward lot. If production remains closed and only trusted addresses are allowlisted, likelihood becomes Low and the realistic in-scope attacker path disappears for that deployment.

## Mechanical severity and policy application

1. **Hard suppression:** Not triggered. Impact is cross-depositor rather than self-only; preconditions were achieved in the fork; the attacker does not need keeper, management, operator, developer, or protected-write-path privileges.
2. **Network/exposure weighting:** `remote` supports attacker reach, but conditional deposit access and economic duration keep likelihood at Medium rather than High.
3. **Production/reportability:** The component is a real production strategy surface, and repository evidence establishes a realistic lower-privileged path whenever deposits are open or an untrusted depositor is allowlisted. Missing current deployment state lowers certainty about frequency but does not itself suppress the finding.
4. **Matrix:** `impact=medium` plus `likelihood=medium` maps mechanically to **Low**.
5. **Priority:** Low maps mechanically to **P3**.

**Final policy decision: reportable at Low severity / P3.**
