# Validation Report: CAN-001 — Zero-minimum GROVE reward sale can be sandwiched

## Identity and disposition

- Candidate ID: `CAN-001`
- Instance key: `swap-slippage:src/GroveCompounder.sol:100`
- Discovery ledger/seed row: not provided (centralized candidate ledger: `CAN-001`)
- Advisory/source reference: none; repository discovery candidate
- Root control: `src/GroveCompounder.sol:96-105`, especially the literal-zero bound at line 100
- Affected locations: `src/GroveCompounder.sol:84-118`; pinned `UniswapV3Swapper.sol:67-102`
- Disposition: **deferred**
- Survives validation: **uncertain** (the zero-bound mechanism survives; profitable extraction and permanent loss were not reproduced)
- Confidence: **medium (0.68 overall; high for source-to-sink mechanism, medium-low for economic exploitability)**
- Validation method: exact source/control/sink trace, role and deployment adjacency checks, historical on-chain transaction review, and bounded pinned-mainnet-fork sandwich tests against live integrations

## Validation rubric

- [x] Source and orderability: permissionless GROVE/USDC trades can be ordered around a keeper's public `report()` transaction.
- [x] Exact sink: direct mode forwards literal `0` through the pinned swapper to Uniswap V3 `amountOutMinimum`.
- [x] Realistic preconditions: management-enabled direct mode, the default `5,000 GROVE` threshold, keeper-gated report, principal deposit, and production router/pool/PSM/staking were exercised.
- [ ] Economic harm: no sampled full round trip made the attacker profitable or proved permanent depositor loss after accounting for residual unsold GROVE and gas.
- [x] Reproducibility and counterevidence: commands, source, fork blocks, logs, and bounded parameter-neighborhood results are preserved under validation artifacts.

## Exact hypothesis and harm gate

**Exact bug hypothesis.** When management selects the supported direct-sale mode and accumulated GROVE exceeds the threshold, `_harvestAndReport()` passes `0` to `_swapFrom`. The pinned swapper forwards that value as the router's `amountOutMinimum`. A public-market attacker may therefore front-run the predictable exact-input sale and back-run it without the victim transaction enforcing a minimum exchange rate.

**Exact observable.** On the selected historical production state, a 300-GROVE front-run lowered immediate strategy proceeds for a 6,000-GROVE report from `14.211505 USDS` to `4.750063 USDS`, an immediate realized-proceeds shortfall of `9.461442 USDS`.

**Harm assertion.** After front-running, allowing the report, and buying GROVE back, the attacker must finish with more GROVE-equivalent value than it started with, before gas, while the strategy permanently realizes less reward value.

**Result.** `[POC-FAIL][PROD-FORK]`. The attacker ended with `294.166531460515298320 GROVE` from `300 GROVE`, a loss of `5.833468539484701680 GROVE` (about 1.94%) before gas. The V3 call also left unsold GROVE on the strategy when available liquidity was exhausted, so the immediate USDS shortfall is not itself permanent loss. The candidate's financial-harm gate was not met.

## Preserved source / control / sink / impact tuple

| Element | Exact evidence |
|---|---|
| Source | A permissionless market participant trades GROVE against USDC before and after the keeper transaction; real swaps in the target pool were observed on-chain. |
| Reachable entrypoint | Tokenized Strategy `report()` is keeper-gated. An authorized keeper invokes the ordinary report path, which reaches `_harvestAndReport()`; authorization limits who reports but does not authenticate or freeze preceding market state. |
| Mode control | `[CODE]` `useAuction` defaults to `true` at `GroveCompounder.sol:22`; management can select direct mode through `setUseAuction` at lines 224-227. Thus the tested branch is supported but non-default. |
| Threshold control | `[CODE]` the constructor sets `minAmountToSell[GROVE] = 5,000e18` at lines 50-53; the direct swap runs only when `toSwap` is strictly greater at lines 96-100. |
| Root sink | `[CODE]` line 100 invokes `_swapFrom(REWARDS_TOKEN, base, toSwap, 0)`. The pinned swapper passes `_minAmountOut` into `ExactInputSingleParams.amountOutMinimum` at `UniswapV3Swapper.sol:75-86`. |
| Output path | The received USDC is converted to USDS through the PSM at lines 101-105 and is included in reported total assets. |
| Conditional impact | If a profitable round trip exists for the live pool state, an attacker could transfer a portion of recurring reward value from depositors. Principal USDS is never sold by this path. |

## Reachability, roles, and boundary conditions

- **External attacker -> keeper/users:** a public trader can alter the AMM state immediately before `report()` and unwind after it. This direction was dynamically exercised.
- **Keeper -> users:** only an authorized keeper can submit `report()`, but keeper timing can expose the deterministic sale. Keeper authorization is not a slippage control.
- **Management boundary:** ordinary users and traders cannot enable direct mode. `useAuction` is `true` by default, and management must call `setUseAuction(false)`.
- **Natural-operation boundary:** claimed/held rewards must exceed `5,000 GROVE`; the principal deposited into the strategy remains staked USDS.
- **External-state boundary:** exploitability depends on active V3 liquidity, tick ranges, transaction order, the 1% pool fee in each direction, and gas. Those values can change independently of repository code.
- **Deployment boundary:** the current deploy script instantiates only the APR oracle; strategy deployment is commented out. The bounded check did not establish a deployment of the checked-out Grove strategy.

## Dynamic validation

### PoC Attempt ledger

| Attempt | State / parameters | Result | Interpretation |
|---|---|---|---|
| A | Mainnet block `25,481,371`; 1,000,000 USDS principal; direct mode; 6,000 GROVE victim sale; 300 GROVE front-run | `[POC-FAIL][PROD-FORK]` | Immediate proceeds fell by 9.461442 USDS, but attacker lost 5.833468539484701680 GROVE before gas. |
| B | Same state and victim sale; 100 GROVE front-run | `[POC-FAIL][PROD-FORK]` | Immediate proceeds fell by about 3.154777 USDS, but attacker ended near 98.1150611883 GROVE from 100 GROVE. |
| C | Same state; 1,000 GROVE front-run | `[POC-FAIL][PROD-FORK]` | Victim swap reverted with `SPL`; no successful extraction. |
| D | Larger tested victim/front-run combinations | `[POC-FAIL][PROD-FORK]` | Price-boundary/partial-fill behavior or reverts occurred; no profitable completed round trip was found. |
| E | Mainnet block `25,583,821`; otherwise realistic direct report | `[PROD-FORK]` | Direct report reverted against a zero-active-liquidity pool snapshot. |

### Execution Result

- PoC required: YES for claimed sandwich extraction
- PoC class: production-fork integration/economic test
- Attempted: YES
- Compiled: YES (Solc 0.8.28)
- Exact test: `test_CAN001_zeroMinimumSaleIsProfitablySandwiched`
- Exact assertion: attacked immediate proceeds must be lower **and** attacker final GROVE must exceed starting GROVE
- Result: FAIL on the attacker-profit assertion
- Fuzz variant: not run; a bounded manual neighborhood was exercised, and the base harm assertion did not pass
- Primary log: `artifacts/05_findings/CAN-001/validation_artifacts/logs/fork_profit_assertion.log`
- Current-state log: `artifacts/05_findings/CAN-001/validation_artifacts/logs/current_pool_direct_mode.log`

The harness deploys the checked-out strategy against production addresses, deposits realistic principal so the inherited health check remains enabled, keeps the repository's default reward threshold, enables the supported non-default direct mode through management, snapshots the same fork state for baseline and attacked executions, and uses the live V3 router/pool plus PSM/staking contracts. The failed assertion is intentionally preserved: a lower immediate conversion amount alone does not prove a profitable sandwich.

## Evidence audit

| Claim | Evidence source | Tag | Dispositive use |
|---|---|---|---|
| Direct sale has a literal-zero output bound | Checked-out `GroveCompounder.sol:96-105` | `[CODE]` | Establishes the control gap |
| Literal zero becomes router `amountOutMinimum` | Exact pinned swapper source, lines 67-102 | `[CODE]` | Establishes the sink |
| Direct mode is supported but management-enabled and non-default | `GroveCompounder.sol:22,224-227` | `[CODE]` | Reduces reachability/likelihood |
| Default threshold and 1% fee tier | `GroveCompounder.sol:50-53` | `[CODE]` | Establishes economic preconditions |
| Sampled sandwich lowered immediate proceeds but lost attacker capital | Executed block-25,481,371 fork test | `[PROD-FORK][POC-FAIL]` | Counterevidence to reportable extraction for sampled state |
| Current snapshot could not execute the direct sale | Executed block-25,583,821 fork test | `[PROD-FORK]` | Snapshot-specific availability counterevidence |
| The pool has carried actual GROVE/USDC swaps | Mainnet transactions `0xb19a…4f0` and `0x574b…2d9` | `[PROD-ONCHAIN]` | Shows the market path is not purely hypothetical; does not prove profit |
| Generic sandwich ordering is historically established | Flash Boys 2.0 and empirical DEX HFT literature | `[DOC]` | Pattern precedent only; cannot close local economics |

## Counterevidence and proof gaps

1. **Round-trip loss:** both successful sampled front-run sizes lost GROVE before gas. The candidate alleges extractable value, so this directly prevents a reportable conclusion for the tested configuration.
2. **Residual GROVE:** concentrated-liquidity exhaustion can make an exact-input swap consume less than the nominal input. Any unsold GROVE remains strategy property; comparing only same-report USDS proceeds overstates permanent loss.
3. **Revert states:** a larger front-run caused the report to revert, while the current snapshot had zero active liquidity and also reverted. These outcomes are denial/timing effects, not demonstrated theft.
4. **Two 1% trading fees plus gas:** the attacker must overcome both round-trip fees, price impact, and gas. No tested point did so.
5. **Non-default mode and no established deployment:** management must disable auctions, and the bounded deployment evidence did not identify the checked-out strategy live.
6. **Mutable liquidity remains unresolved:** current/historical snapshots do not prove every future or attacker-supplied concentrated-liquidity configuration unprofitable. A zero minimum still permits execution at any router-returned amount when a successful swap is possible.

The evidence therefore does not support `reportable`, but it also cannot support `suppressed`: the exact control gap exists, real trading/orderability exists, and mutable liquidity leaves a narrower profitable state-space question open.

## RAG / historical precedent

- Historical precedent: **YES**, for generic AMM sandwich/priority extraction.
- Flash Boys 2.0 documents transaction-ordering dependence and front-running on decentralized exchanges: `https://arxiv.org/abs/1904.05234`.
- High-Frequency Trading on Decentralized On-Chain Exchanges empirically analyzes sandwich and arbitrage activity: `https://arxiv.org/abs/2009.14021`.
- Pattern confidence: **high** for generic ordering risk. These references do not establish profitability in this 1%-fee GROVE/USDC pool or prove that the direct mode is deployed/enabled.

## Devil's advocate and chain/enabler check

**What exact state would make the hypothesis exploitable?** Direct mode must be enabled; reward balance must exceed the threshold; the keeper report must be publicly orderable; active or attacker-supplied concentrated liquidity must allow the victim sale and both attacker legs to complete; victim-induced price movement must exceed both 1% fees plus gas; and total post-sequence strategy value, including residual GROVE, must be lower by an amount captured by the attacker.

The bounded tests checked those conditions on an actual traded historical state and the current state, including smaller and larger front-run neighborhoods. No profitable state was found. The centralized candidates concerning public-AMM spot prices (`CAN-002`/`CAN-003`) do not grant direct-mode permission or supply the missing profitable liquidity postcondition, so no candidate chain closes this proof gap.

Enabler classification:

- External attacker action: front-run/back-run trades or LP-state changes.
- Semi-trusted action: keeper submits `report()`; keeper cannot itself enable direct mode unless separately authorized as management.
- Natural operation: rewards accumulate beyond 5,000 GROVE.
- External event: V3 liquidity/tick state changes.
- Normal user sequence: deposits do not enable direct mode; a privileged management action remains necessary.

## Severity facts

- No final severity is assigned while disposition is deferred.
- The maximum asset exposed by this path is accumulated GROVE reward value, not deposited USDS principal.
- Likelihood is reduced by auction mode being the code default, management authorization to select direct mode, the 5,000-GROVE threshold, 1% fee tier, and sampled unprofitable/reverting states.
- If a profitable, repeatable live configuration is later proven with material recurring reward loss, the canonical threat model supports **Medium**. **High** is not supported without quantified major loss.
- The observed immediate timing/availability effect alone is insufficient to elevate the candidate into a financial vulnerability.

## Minimal next step

Obtain a verified deployment/configuration showing direct mode enabled, then search or construct a realistic pinned-fork liquidity state in which every leg fully settles. Value the strategy's final USDS plus residual GROVE and the attacker's final portfolio after gas. Promote only if the same atomic/orderable sequence proves positive attacker profit paired with permanent strategy value loss.

## Validation closure

| Ledger row id | Instance key | Advisory/source | Seed anchor | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|---|---|
| `CAN-001` (source row not provided) | `swap-slippage:src/GroveCompounder.sol:100` | Repository discovery; no advisory | `src/GroveCompounder.sol:84-118` | `src/GroveCompounder.sol:96-105` | Keeper `report()` plus permissionless public-market ordering | `_swapFrom(..., toSwap, 0)` -> V3 `amountOutMinimum = 0` | `deferred` | Tested rounds were attacker-negative/reverting; residual GROVE prevents equating immediate proceeds with permanent loss; deployment/direct-mode state and profitable mutable liquidity remain unresolved | `uncertain` |

## Artifacts

- Harness/test: `artifacts/05_findings/CAN-001/validation_artifacts/harness/src/test/CAN001.t.sol`
- Reproduction notes: `artifacts/05_findings/CAN-001/validation_artifacts/README.md`
- Primary execution log: `artifacts/05_findings/CAN-001/validation_artifacts/logs/fork_profit_assertion.log`
- Current-state execution log: `artifacts/05_findings/CAN-001/validation_artifacts/logs/current_pool_direct_mode.log`
- Relocated Forge RPC cache used for reproducibility: `artifacts/05_findings/CAN-001/validation_artifacts/rpc_cache/`

