# Canonical Threat Model

Repository: `usds-spark-rewards`  
Revision: `f8f796db93c52432cca0ed26861e94f5aaf20975`  
Scope: the explicit nine-file first-party production allowlist; directly relied-on vendored implementations may be inspected only to trace an allowlisted call. Tests are validation-only.

## Overview and assets

`GroveCompounder` is a Yearn V3 tokenized strategy that accepts USDS, stakes it in the fixed Sky/Grove staking contract, claims GROVE rewards, and realizes them through either a configured auction or a Uniswap V3 GROVE/USDC sale followed by the fixed PSM wrapper. `GroveCompounderAprOracle` estimates staking APR from the reward schedule and market prices, preferring a configured V3 pool and falling back to configured V4 pools. The simulator libraries reproduce a V3 swap against current pool state.

Protected assets and properties are depositor USDS principal; withdrawability; share and total-assets accounting; accrued GROVE rewards and sale proceeds; report/maintenance availability; configuration authority; and the integrity and availability of APR values consumed by allocation systems.

## Trust boundaries and attacker capabilities

- Depositors and public callers are untrusted. They may time deposits/withdrawals, donate tokens, compose atomic calls, and exploit public transaction ordering.
- Management and keepers are trusted only for their documented roles. Deliberate malicious management is outside the ordinary attacker model, but missing checks, unsafe supported configurations, and public interference with privileged operations are in scope.
- The fixed staking contract, PSM wrapper, ERC-20s, Uniswap router/factory/pools, V4 StateView, and configured auction are external-call boundaries. Their intended deployed code is assumed, but liveness, mutable balances, prices, liquidity, ticks, reward schedules, and public entrypoints are not trusted.
- AMM traders, LPs, searchers, flash-liquidity users, auction participants, and transaction builders are adversarial. They can manipulate spot state, sandwich reports, donate tokens, and pre-position external state within protocol rules.
- Downstream APR consumers and exported-library callers are external integration boundaries. Financial severity requires proof that a security-sensitive consumer can act on the value; API-only hypotheses require an in-scope reachable caller.
- Inherited Yearn/periphery dependencies are assumed to enforce their documented accounting and authorization, but are inspected where a first-party call depends directly on their concrete behavior.

## Security invariants

1. Idle plus staked USDS must remain solvent, withdrawable, and accurately reflected in strategy accounting.
2. Reward realization must not expose accumulated GROVE to attacker-chosen execution prices, misroute proceeds, or make routine reports permissionlessly unavailable.
3. Deposits and reports must not let a late participant capture value accrued for existing shares without an explicit protocol policy permitting it.
4. Auction configuration and state transitions must preserve receiver/want constraints and tolerate or prevent adversarially active reward-token auctions.
5. APR output must be dimensionally correct, bounded, and based on sufficiently trustworthy and available data; spot-state, supply, timestamp, or resource-complexity manipulation must not cause unsafe allocation decisions.
6. V3/V4 fallback controls must fail closed when independent price evidence is absent and must not treat raw active liquidity or a one-element median as price authenticity.
7. Exported quote APIs must preserve declared exact-input semantics for every accepted input and reject values that cannot be represented safely.
8. All configuration mutations remain restricted to intended authorities, and external failures must not corrupt state or permanently block principal recovery.

## Attack surface and candidate families

- Strategy lifecycle: staking, unstaking, emergency withdrawal, reward claiming, report accounting, deposit timing, and inherited share/health-check interaction.
- Reward sale: public-mempool ordering around direct Uniswap execution, minimum-output enforcement, auction transfer/kick state, token donations, and auction permissions.
- APR oracle: signed debt delta, staking reward period/supply, V3 current-state simulation, V4 quote quorum/median/deviation, pool configuration, decimals/orientation, and the 50% cap.
- Simulator: tick traversal/gas behavior, current pool-state reads, arithmetic boundaries, and the unsigned-to-signed amount conversion.
- Privileged setters and external calls: role enforcement, zero/incompatible configuration, callback/revert behavior, and recovery paths.

Traditional web families such as SQL injection, XSS, SSRF, path traversal, unsafe deserialization, sessions, and templates are not applicable to this Solidity-only production scope.

## Existing controls and assumptions

Existing controls include Solidity checked arithmetic outside deliberate `unchecked` regions, SafeERC20, inherited Yearn roles and health checks, deposit gating and staking-pause checks, an auction asset prohibition plus receiver/want validation, minimum reward-sale thresholds, a zero-PSM-fee check, a 50% APR cap, V3 liquidity/balance gates, V4 liquidity/deviation filters, and management-only pool configuration. Each control must be evaluated on the concrete path; role gating does not stop public market ordering, a raw-liquidity threshold is not an authenticated price, and a later cap does not make an earlier source trustworthy.

## Severity calibration

- Critical: unprivileged theft or irreversible loss of most USDS principal, unbacked share creation/redemption, or strategy-control takeover.
- High: practical major principal/reward loss, or a proven manipulable oracle path that directly causes large downstream allocation loss.
- Medium: meaningful recurring reward loss, repeatable report/maintenance denial, or unsafe APR with realistic liquidity and consumer preconditions.
- Low: bounded/recoverable availability issues, narrow estimation errors, or integration/API weaknesses with unusual or unproven reachability.

Likelihood and impact are calibrated separately. Trusted-operator-only misconfiguration, advisory-only oracle use, absent downstream callers, non-default modes, capital requirements, and short equality/timing windows reduce likelihood or reportability and must be recorded as counterevidence rather than omitted.
