# CAN-007 Validation Report

## Assessment

- Finding: Same-block staking supply changes can manipulate the APR denominator
- Candidate ID: `CAN-007`
- Ledger row: `COV-015`
- Instance key: `oracle-denominator:src/periphery/GroveCompounderAprOracle.sol:111`
- Root control / sink: `src/periphery/GroveCompounderAprOracle.sol:111-125`
- Affected entrypoint: `src/periphery/GroveCompounderAprOracle.sol:109-132`
- Source boundary: `src/interfaces/IStaking.sol:13-25`
- Disposition: **deferred**
- Survives validation: **uncertain**
- Confidence: **medium (0.72) overall**; **high (0.95) that the denominator mechanism and atomic production staking path exist**; **low (0.30) that the claimed downstream allocation harm is established**
- Severity: **unassigned while deferred**. The validated mechanism alone is informational/Low; the repository threat model requires a realistic security-sensitive consumer for Medium and a proven major allocation loss for High.

The production-fork suite mechanically confirms that any user can stake USDS, cause the target source's instantaneous APR to move according to the live `totalSupply`, withdraw in the same block, and recover the full principal without a cooldown or fee. At pinned state, doubling supply halved APR from 7.2119140831426053% to 3.6059570415713026%, and staking `S/9` (24.657693M USDS) moved it by 9.99% relative.

This is not a proof of the claimed harm. The bounded adjacency pass found production APR-registry wiring, but no concrete transaction that consumes the value to rank, deny, or change debt allocation. The PoC therefore proves the mechanism, not a security-sensitive downstream outcome. Under the instance-preserving validation rules, the missing consumer makes this row deferred rather than suppressed.

## Validation Rubric

- [x] Establish a permissionless production `stake`/`withdraw` path that can bracket an APR read in one block.
- [x] Trace the exact denominator and `_delta` logic and verify unrelated supply is not normalized.
- [x] Quantify capital at pinned production state and verify atomic principal return; external access to that capital remains unproven.
- [x] Measure APR movement and bound the 50% cap condition with production constants.
- [ ] Demonstrate a concrete downstream consumer whose security-sensitive allocation decision changes because of the transient APR.

## Exact Claim and Proof Design

1. Exact issue: `aprAfterDebtChange` reads live global `IStaking(STAKING).totalSupply()` at line 111 and adjusts it only by the caller-supplied strategy `_delta` at lines 120-125. An unrelated user's stake or withdrawal before the read is included without any snapshot, averaging, or transaction-local normalization.
2. Observable difference: at block 25,583,822, the target-source oracle returned `72119140831426053`; after an unrelated stake equal to standing supply it returned `36059570415713026`; after withdrawal it returned the exact original value.
3. Exact mechanism assertions: the test requires `supplyDuring == supplyBefore + attackerAmount`, `aprDuring * 2 ~= aprBefore`, exact supply/APR restoration after withdrawal, and full attacker principal restoration. The boundary test requires `999 <= movementBps <= 1001` for `A=S/9`.
4. Claimed harm: a downstream allocator denies or misdirects allocation after reading the transient APR. No executable harm assertion was constructed because the target and bounded adjacent artifacts do not identify that consumer.

## Source / Control / Sink Tuple

- Source: permissionless `stake(uint256,uint16)` and `withdraw(uint256)` calls on production staking `0x4E41488C19cD35EB4de3083Fc3e204854c75c86a`.
- Control: no snapshot or average; only the proposed strategy `_delta` is added/subtracted.
- Sink: `assets` is the denominator of `rewardRate * SECONDS_PER_YEAR * price / assets`, followed by a 50% APR cap.
- Reachable path: attacker stakes -> oracle reads production `totalSupply` -> APR changes -> attacker withdraws in the same Foundry transaction; reverse ordering also executes.
- Boundary: APR is registered in the production Yearn Core APR Oracle, but no state-changing allocation consumer was identified.

## Feasibility Gates

### F1: Reachability — PASS for mechanism

The pinned production staking contract accepted an arbitrary funded address's approval, stake, withdrawal, and re-stake. No role check, cooldown, or withdrawal fee blocked the path. The same-block supply-expansion sequence restored all `221919241070963424846369056` USDS to the attacker.

### F2: Math bounds — PASS for visible movement, constrained by capital

Let `K = rewardRate * secondsPerYear * price`, standing supply be `S`, and unrelated attacker stake be `A`. The output changes from `K/S` to `K/(S+A)`, so relative suppression is `A/(S+A)`.

- Pinned `S`: 221,919,241.070963 USDS.
- `A=S/9`: 24,657,693.452329 USDS -> 9.99% measured relative suppression.
- `A=S`: 221,919,241.070963 USDS -> 50% measured relative suppression.
- Principal is atomically returned, but the harness uses `deal` to provision capital; it does not prove a real flash/borrow source for 24.66M-221.92M USDS.
- At the pinned 7.2119% APR, reaching the 50% cap through withdrawal would require the attacker to own and remove about 85.576172% of standing supply (about 189.91M USDS). That ownership precondition is not established.

## PoC Attempt

- PoC Required: YES
- PoC Class: integration
- Attempted: YES
- PoC Not Attempted Because: N/A
- Test File: `artifacts/05_findings/CAN-007/validation_artifacts/harness/test/CAN007.t.sol`
- Command: `forge test --root <CAN-007>/validation_artifacts/harness --fork-url "$ETH_RPC_PUBLIC" --fork-block-number 25583822 --match-contract CAN007ProductionForkTest -vv`

### Execution Result

- Compiled: YES (initial compile plus one targeted setup correction)
- Result: PASS for mechanism; downstream harm NOT TESTED because no consumer was identified
- Fuzz variant: NOT_APPLICABLE (candidate is deferred with no assigned Medium+ severity; concrete 10% and 50% boundaries were executed)
- Output: 3 passed, 0 failed, 0 skipped
- Evidence Tag: `[PROD-FORK-MECHANISM]` for reachability/math; `[CODE-TRACE]` for impact under the Phase 5 harm gate. This is deliberately not `[POC-PASS]` because no allocation harm was asserted.

Attempt history:

1. Initial suite: supply-expansion and 10% boundary tests passed; reverse-ordering setup reverted with `Usds/insufficient-allowance` because the first stake consumed the exact allowance.
2. Setup-only correction: approve `type(uint256).max` while keeping the same production functions and assertions. Final suite passed all three tests.

Relevant final output:

```text
[PASS] test_CAN007_sameBlockSupplyExpansionMovesApr()
  supplyBefore 221919241070963424846369056
  attackerAmount 221919241070963424846369056
  supplyDuring 443838482141926849692738112
  aprBefore 72119140831426053
  aprDuring 36059570415713026
  aprAfter 72119140831426053
  attackerBalanceAfter 221919241070963424846369056

[PASS] test_CAN007_sameBlockWithdrawalInflatesApr()
  aprWithStandingStake 36059570415713026
  aprDuringWithdrawal 72119140831426053
  aprRestored 36059570415713026

[PASS] test_CAN007_tenPercentMovementCapitalBound()
  capitalForApprox10Percent 24657693452329269427374339
  movementBps 999
```

## Evidence Audit

| Claim | Evidence source | Tag | Valid for suppression/refutation? |
|---|---|---:|---:|
| Oracle samples live staking supply and only adjusts `_delta` | immutable target `GroveCompounderAprOracle.sol:109-132` | `[CODE]` | YES |
| Production staking accepts same-block stake/withdraw/re-stake and returns principal | fork block 25,583,822; final three-test suite | `[PROD]` | YES |
| Pinned supply/reward schedule and 10%/50% capital bounds | production RPC + fork assertions | `[PROD]` | YES |
| Attacker can source 24.66M-221.92M USDS | Foundry `deal` only | `[MOCK]` | NO |
| Repository-deployed strategy is registered to its deployed custom oracle | Core APR Oracle `oracles(strategy)` at pinned block | `[PROD]` | YES |
| A downstream allocator makes a harmful decision from the read | no consumer found | proof gap | NO |
| Same-block oracle-state manipulation is a recognized DeFi pattern | [SoK: DeFi Attacks](https://arxiv.org/abs/2208.13035), [OWASP SC03](https://scs.owasp.org/sctop10/SC03-PriceOracleManipulation/) | `[DOC]` | NO |

No mock or unverified-external evidence is used to suppress the candidate. The only mock-like step is capital provisioning, which is explicitly why economic feasibility and harm remain unproven.

## RAG / Historical Precedent

- Historical precedent: YES for general atomic oracle-state manipulation; NO exact public exploit was identified for transiently changing a staking-supply APR denominator.
- Similar mechanisms: same-block price/state distortion consumed by DeFi decision logic; these support the pattern class but do not establish this instance's consumer or economics.
- Pattern confidence: MEDIUM for security impact; HIGH for the arithmetic/reachability mechanism.

## Downstream Consumer Pass and Counterevidence

The bounded pass searched first-party source, tests, deploy/broadcast artifacts, README, the directly relied-on periphery APR registry, and exact deployed addresses.

- First-party uses of `aprAfterDebtChange` are the oracle implementation and tests only.
- The production Core APR Oracle maps the repository-recorded deployed strategy `0xc9f01b5c6048B064E6d925d1c2d7206d4fEeF8a3` to deployed oracle `0xba7c652bf6359a19d358c54492ac40b20a7b0430`, and `getStrategyApr(strategy,0)` succeeds. The value is therefore not wholly unused.
- Neither the target nor bounded adjacent artifacts identify a threshold/ranking/debt-update caller that turns the read into denial, misallocation, or loss.
- The cap does not prevent suppression, but the pinned capital requirement is large. Cap-triggering inflation requires ownership of most existing staked supply, not merely an atomic new stake.
- The fork shows no direct attacker profit, victim loss, or persistent state corruption.

## Devil's Advocate and Chain Check

This becomes exploitable if a permissionless, predictable, or MEV-bundleable allocation transaction reads the registered APR and changes strategy debt based on a threshold/ranking while the attacker can source roughly 24.66M USDS for a 10% move (or already owns enough standing stake for withdrawal-driven inflation). The minimum next step is to identify that deployed consumer and execute `stake -> consumer action -> withdraw`, asserting a changed debt/allocation outcome and attacker/victim economics.

No `findings_inventory.md` or completed chain artifact exists in the scan. The canonical candidate inventory was checked: CAN-002/CAN-003 manipulate the price numerator but do not supply CAN-007's missing capital source or downstream consumer. No other candidate establishes the missing precondition.

## Closure

| Ledger row | Instance key | Advisory/source | Seed anchor | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|---|---|
| COV-015 | `oracle-denominator:src/periphery/GroveCompounderAprOracle.sol:111` | N/A | `src/interfaces/IStaking.sol:23-25` | `src/periphery/GroveCompounderAprOracle.sol:111-125` | production permissionless stake/withdraw | live `totalSupply`, `_delta`-only normalization, APR division/cap | deferred | Production mechanism passes, but capital source and a concrete harmful allocation consumer remain unproven | uncertain |

## Artifacts

- `artifacts/05_findings/CAN-007/validation_artifacts/harness/test/CAN007.t.sol`
- `artifacts/05_findings/CAN-007/validation_artifacts/harness/foundry.toml`
- `artifacts/05_findings/CAN-007/validation_artifacts/forge-test.log`
- `artifacts/05_findings/CAN-007/validation_artifacts/production_state.md`
- `artifacts/05_findings/CAN-007/validation_artifacts/adjacency_pass.md`
- `artifacts/05_findings/CAN-007/validation_artifacts/README.md`
