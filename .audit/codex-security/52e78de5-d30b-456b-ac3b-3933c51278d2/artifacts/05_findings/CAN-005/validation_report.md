# Validation: APR remains nonzero at the exact reward-expiry timestamp

## Identity and disposition

- Candidate ID: `CAN-005`
- Ledger row ID: `COV-008`
- Instance key: `reward-expiry-boundary:src/periphery/GroveCompounderAprOracle.sol:114`
- Root control: `src/periphery/GroveCompounderAprOracle.sol:114-116`
- Affected entrypoint/sink: `src/periphery/GroveCompounderAprOracle.sol:109-132`
- Protocol boundary: `src/interfaces/IStaking.sol:19-21`
- Disposition: **deferred**
- Confidence: **high (0.95) that the forecast mismatch exists; low-medium (0.40) that it has a concrete security impact in the supplied scope**
- Severity: **unassigned while deferred**. The strongest evidence-backed effect is a one-timestamp incorrect forecast with no proved allocation/loss sink; if a deployed consumer is later shown to persist a suboptimal debt allocation, current evidence supports a provisional **Low** severity, subject to quantified duration and opportunity cost.

The equality behavior is real and production-reachable, but the supplied target has no downstream allocator or other state-changing consumer. A pinned production fork proves that a new stake made at equality earns zero future reward despite a 7.21% APR forecast. It does not prove depositor loss, attacker profit, denial of service, or a durable misallocation. Under the instance-preserving validation rules, the missing consumer/deployment fact is a proof gap requiring `deferred`, not suppression and not a reportable vulnerability based only on the off-by-one.

## Validation rubric

- [x] **Exact branch semantics:** evaluate the strict `>` condition at `periodFinish - 1`, `periodFinish`, and `periodFinish + 1` against the audited implementation.
- [x] **External reward-rate semantics at equality:** verify production `StakingRewards` accrual clamping and whether stored `rewardRate` becomes zero at expiry.
- [x] **Block-timestamp reachability:** determine whether `periodFinish` can be an actual Ethereum execution timestamp rather than an unreachable arbitrary second.
- [x] **Downstream single-block impact:** search the in-scope production code, validation-only deployment/config evidence, pinned periphery integration, and live registrations for a state-changing consumer and require a direct harm assertion.
- [x] **Counterevidence and precision:** bound the window, distinguish a forecast mismatch from security harm, audit enablers, and avoid treating a contrived mock consumer as proof.

## Claim tuple and pre-verification understanding

- Claimed trigger/source: a transaction executes in a block whose timestamp equals the staking contract's `periodFinish`.
- Closest control: `if (block.timestamp > periodFinish) return 0;` at oracle lines 114-116.
- Sink: lines 118-132 price and annualize the still-stored `rewardRate` as forward APR.
- Preconditions: a block is proposed for the exact scheduled slot, a caller reads the oracle in that block, and a real consumer makes a security-sensitive and sufficiently persistent allocation decision from that read.
- Exact observable: APR is positive at equality and zero at equality plus one second, while a fresh production stake made at equality earns zero thereafter.
- Exact assertions: `aprAtEquality > 0`, `aprAfter == 0`, production `lastTimeRewardApplicable() == periodFinish`, and `earned(freshStaker) == 0` one day after staking at equality.
- Claimed harm: vault capital is allocated to an ended reward schedule and suffers opportunity cost. **That harm cannot be asserted directly without the absent allocator, alternative yield, allocation duration, and depositor-loss accounting.**

### Feasibility gates

| Gate | Result | Evidence |
|---|---|---|
| F1 reachability | Partial pass | `aprAfterDebtChange` is public and equality is a valid scheduled slot. No in-scope state-changing consumer reaches it. |
| F2 bounds | Mechanism passes; harm unbounded/unknown | At the pinned state, equality APR is `72,119,140,506,446,839` (7.2119%) and a 1-USDS fresh stake earns zero after one day. No loss amount can be computed without an allocator and alternative yield. |

## Evidence observed

### 1. Audited branch semantics

`GroveCompounderAprOracle.aprAfterDebtChange` reads `totalSupply` and `rewardRate`, returns zero only when `block.timestamp > periodFinish`, and otherwise annualizes the rate. Therefore equality takes the nonzero branch. [CODE]

Pinned fork results:

| Timestamp | Oracle APR |
|---|---:|
| `periodFinish - 1` | `72119140831426053` |
| `periodFinish` | `72119140831426053` |
| `periodFinish + 1` | `0` |

### 2. Production staking semantics

The verified production `StakingRewards` source for the bytecode-matched implementation defines `lastTimeRewardApplicable()` as `block.timestamp < periodFinish ? block.timestamp : periodFinish`. Its `notifyRewardAmount` stores a nonzero `rewardRate` and sets `periodFinish = block.timestamp + rewardsDuration`; expiry does not clear the stored rate. Etherscan identifies the target staking bytecode as a similar match to the exact verified implementation at `0x1C72682e2e76A47AEC3987c7327ee41467616E9E`. [PROD-SOURCE]

On the pinned fork, production values were:

- `rewardsDuration = 604800` seconds (7 days)
- `periodFinish = 1785168167`
- `rewardRate = 38844495180111618467`
- `totalSupply = 221919241070963424846369056`

At equality and afterward, `lastTimeRewardApplicable()` remained exactly `periodFinish` while `rewardRate` remained stored and nonzero. A fresh 1-USDS stake at equality earned exactly zero after one day despite a `72119140506446839` APR forecast. [PROD-FORK]

### 3. Equality timestamp is reachable

Ethereum PoS uses twelve-second slots and validates the execution payload timestamp against its slot. The live schedule duration is 604,800 seconds, exactly 50,400 slots. The pinned block timestamp was `1784669807`; `periodFinish - block.timestamp = 498360`, exactly 41,530 slots. Thus `periodFinish` is itself a valid future slot timestamp. A missed slot can skip equality, but the timestamp is not structurally unreachable. The precise actor model is transaction inclusion/scheduling around a known slot, not arbitrary validator timestamp selection. [PROD-ONCHAIN] [DOC]

Primary references:

- Production staking: https://etherscan.io/address/0x4E41488C19cD35EB4de3083Fc3e204854c75c86a#code
- Exact verified bytecode match: https://etherscan.io/address/0x1C72682e2e76A47AEC3987c7327ee41467616E9E#code
- Ethereum slot timing: https://ethereum.org/developers/docs/consensus-mechanisms/pos/block-proposal/
- Consensus timestamp check: https://ethereum.github.io/consensus-specs/capella/beacon-chain/

### 4. Downstream consumer and impact closure

The complete nine-file production allowlist contains no caller of `aprAfterDebtChange`; the oracle is the end of the in-scope call path. [CODE]

The pinned Yearn periphery `AprOracle` can forward a strategy APR to custom integrations, and its README says the interface may be used by on-chain debt allocators or off-chain interfaces. It also explicitly warns that returned values are point-in-time and subject to change. This establishes intended composability, not a concrete deployed harm sink. [CODE] [DOC]

The bounded deployment adjacency check did not identify the audited Grove instance:

- Repository deployment comments name strategy `0xc9f01b5c6048B064E6d925d1c2d7206d4fEeF8a3`, but live calls show that strategy uses staking `0x173e314C7635B45322cd8Cb14f44b312e079F3af`, not audited Grove staking `0x4E414...`.
- The live core APR oracle registration for that commented strategy points to `0xBA7c652BF6359A19D358c54492ac40B20a7B0430`, whose `STAKING()` is also `0x173e314...`.
- No audited Grove strategy address, its core oracle registration, debt allocator, minimum update interval, alternative strategy, or irreversible allocation call is present in the target or located by the bounded exact-address/source search. [PROD-ONCHAIN] [CODE]

Consequently, the fork proves a wrong forecast, not a capital loss. Creating a mock consumer that stores debt whenever APR is positive would assume the missing harm premise and is explicitly rejected as proof.

## Evidence audit

| Claim | Evidence source | Tag | Supports suppression/refutation? |
|---|---|---|---|
| Equality reaches annualization | Audited oracle lines 109-132 and fork test | [CODE] [PROD-FORK] | Yes for mechanism |
| Production accrual stops at equality while `rewardRate` stays stored | Verified production source and pinned fork | [PROD-SOURCE] [PROD-FORK] | Yes |
| Equality can be an Ethereum block timestamp | Pinned schedule values plus consensus slot rules | [PROD-ONCHAIN] [DOC] | Yes for reachability; documentation alone is not used to refute |
| Fresh equality stake earns zero despite positive forecast | Pinned production fork | [PROD-FORK] | Yes for forecast mismatch |
| A consumer loses funds or persistently misallocates debt | No consumer supplied or found | proof gap | No |
| Deployment comments identify current audited Grove integration | Live addresses instead resolve to older staking/oracle | [CODE] [PROD-ONCHAIN] | Counterevidence only; absence is not suppression proof |

## PoC attempt

- PoC Required: YES
- PoC Class: integration
- Attempted: YES
- PoC Not Attempted Because: N/A
- Test File: `validation_artifacts/harness/test/CAN005.t.sol`
- Command: `forge test --root validation_artifacts/harness --match-test test_CAN005 --fork-url https://ethereum.publicnode.com --fork-block-number 25583831 -vv`

### Execution result

- Compiled: YES (first harness attempt failed because a source symlink resolved outside Foundry's allowed paths; copied exact target source into the disposable harness; subsequent compile and final run succeeded)
- Result: PASS, 2 tests; boundary and forecast mismatch mechanically reproduced
- Fuzz variant: NOT_APPLICABLE (candidate is a single exact equality boundary and currently has no Medium+ proved harm)
- Output: `validation_artifacts/forge_output.log`
- Evidence tag: **[PROD-FORK] for mechanism/forecast mismatch; [CODE-TRACE] for claimed downstream harm**. This is not labeled `[POC-PASS]` for capital loss because no harm assertion against a real consumer was possible.

## Historical precedent / RAG fallback

The configured vulnerability-database MCP is unavailable on this Codex backend, so the mandated web fallback was used. No exact historical exploit was found for a one-slot stale APR caused by `block.timestamp == periodFinish`. Broader oracle timestamp/granularity incidents have produced harm only where a concrete consumer persisted invalid settlement/allocation state; for example, the Perennial oracle-timestamp findings in https://github.com/sherlock-audit/2023-07-perennial-judging. Reward-schedule findings located in public audits concerned continuing or miscomputed distributions rather than this one-slot forecast boundary.

- Historical precedent for exact pattern: NO
- Similar exploits: none exact; broader timestamp-oracle consumer incidents only
- Pattern confidence: HIGH for the code smell/forecast mismatch, LOW for security impact without a consumer
- RAG override: not triggered

## Counterevidence, adversarial check, and enablers

- The mismatch exists only at equality; the next second returns zero.
- Production reward accrual itself is correct and capped; no extra GROVE is paid to a fresh equality staker.
- The public oracle call is read-only and moves no funds.
- No in-scope or identified deployed consumer converts this observation into state.
- The integration documentation warns that APR values are instantaneous and subject to change, although it does not specifically document the expiry mismatch.
- Canonical candidates CAN-002, CAN-003, and CAN-007 also affect APR integrity but do not create the missing consumer/deployment postcondition. No inventory finding enables the absent sink.

**Devil's advocate — what would make this exploitable?** A deployed Grove strategy must be registered to this oracle and used by an allocator that can increase debt in the equality block based solely on this APR, leave that debt parked after emissions end, and thereby forgo a quantifiable safer yield. A proposer/searcher could target the known valid expiry slot. The bounded adjacency search checked the target callers, deployment script, pinned integration code, exact deployed addresses, and core-oracle mappings; the required Grove allocator path was not found.

The five-question impact check is therefore incomplete: vault depositors could bear unavoidable opportunity cost and the oracle does not fully satisfy its stated expected-current-APR purpose at equality, but no affected deployed user set, duration, loss amount, or consumer policy is established.

## Remaining uncertainty and minimal next step

Obtain the intended deployed Grove strategy address and allocator/configuration. Verify its core APR-oracle registration, trace the exact allocator transaction at `periodFinish`, record how long debt remains allocated, and quantify opportunity cost versus the strategy the allocator would otherwise select. If that transaction produces durable, nontrivial depositor loss, promote to reportable and assign severity from the measured loss; if no consumer can act or its controls reject/quickly correct the value, suppress with that exact countercontrol.

## Validation closure

| Ledger row id | Instance key | Advisory/source | Seed anchor | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|---|---|
| COV-008 | `reward-expiry-boundary:src/periphery/GroveCompounderAprOracle.sol:114` | Discovery candidate DSC-W05-003 | `src/interfaces/IStaking.sol:19-21` | `src/periphery/GroveCompounderAprOracle.sol:114-116` | Valid expiry slot / public `aprAfterDebtChange` | Annualization at lines 118-132 | deferred | Production-fork mismatch proven; real state-changing consumer, durable allocation, and quantified loss absent | uncertain |

## Artifacts

- `validation_artifacts/harness/test/CAN005.t.sol`
- `validation_artifacts/harness/foundry.toml`
- `validation_artifacts/forge_output.log`
- `validation_artifacts/README.md`
