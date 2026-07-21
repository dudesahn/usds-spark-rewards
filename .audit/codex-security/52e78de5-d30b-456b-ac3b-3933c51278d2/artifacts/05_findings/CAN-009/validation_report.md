# Validation: CAN-009 — Oversized exact-input quote is reinterpreted as exact-output mode

## Disposition

**Suppressed; survives: no. Confidence: high (0.94).**

The signed-conversion mechanism is real and was reproduced against the
original target wrapper, but the required product-boundary source is absent.
The only in-repository consumer supplies a compile-time `1e18`, no public
parameter can alter it, and the bounded caller/import/deployment pass found no
supported consumer that accepts an attacker-controlled amount. Directly
calling the stateless library quote with an absurd amount returns data only to
that caller and causes no in-scope state change or asset effect. Under the
canonical threat model's explicit rule that API-only hypotheses require an
in-scope reachable caller, this is an unreachable type quirk rather than a
reportable vulnerability.

## Candidate identity

- Candidate ID: `CAN-009`
- Absorbed candidate: `R05W03-C05`
- Instance key: `signed-cast:src/libraries/UniswapV3SwapSimulator.sol:37`
- Ledger row ID: `R05W03-L07`
- Entrypoint: `src/libraries/UniswapV3SwapSimulator.sol:23-26`
- Root control: `src/libraries/UniswapV3SwapSimulator.sol:34-46`
- Mode control/sink: `src/libraries/UniswapV3SwapSimulatorCore.sol:88`
- Sole supported caller: `src/periphery/GroveCompounderAprOracle.sol:213-224`

## Validation rubric (fixed before evidence review)

- [x] Deterministic sign/mode transition: `2^255` converts to
  `type(int256).min`, and the core changes from exact-input to exact-output
  mode when the signed value becomes negative.
- [x] API/compiler semantics: the ABI accepts any `uint256`; Solidity 0.8.28
  explicit conversion preserves the 256-bit representation rather than
  range-checking it.
- [ ] In-scope/directly-relied caller reachability: no supported caller lets an
  attacker choose the quote amount; the only caller fixes `amountIn = 1e18`.
- [x] Concrete quote/revert effect: the focused harness observed a non-monotonic
  quote collapse from `49,996,250,312,472` at `int256.max` to `1` at
  `uint256.max`; no in-scope consumer harm or availability failure followed.
- [x] Counterevidence: all target callsites, imports, deployment scripts,
  broadcasts, package metadata, and candidate enablers were checked; none
  supplies the missing arbitrary-amount consumer.

## Pre-verification understanding

1. **Exact bug mechanism.** The wrapper converts unrestricted
   `params.amountIn` with `int256(params.amountIn)` at line 37. Values
   `>= 2^255` become negative, while the core decides exact-input versus
   exact-output solely through `amountSpecified > 0` at line 88.
2. **Observable difference.** In the deterministic one-tick harness,
   `int256.max` and `2^255` both reached the price limit and returned
   `49,996,250,312,472`; `uint256.max` became signed `-1` and returned an
   exact-output quote of one unit.
3. **Exact assertions.** The test asserts the three signed boundary values,
   equality of the two saturated quotes, `quote(uint256.max) == 1`, and
   `quote(int256.max) > quote(uint256.max)`.
4. **Claimed harm premise.** A supported security-sensitive consumer would
   need to accept the attacker amount, trust this result as an exact-input
   quote, and use it for a transaction bound or allocation action. The target
   has no such path, so the executed test is mechanism proof rather than
   product-harm proof.

## Feasibility gates

### F1 — Reachability: fails at the supported consumer boundary

- The library function itself is externally callable and has no access check.
- Its direct call is read-only and returns the quote only to the caller.
- The sole target consumer is `GroveCompounderAprOracle._grovePrice`, which
  constructs the struct internally and fixes `amountIn: 1e18`.
- The oracle's public `aprAfterDebtChange(address,int256)` parameters do not
  flow into that amount.
- No other tracked Solidity caller, interface, script, documented package
  surface, or deployment artifact exposes a variable quote amount.

Therefore an attacker can reproduce the arithmetic curiosity but cannot make
the supported product consume it.

### F2 — Math/domain bounds: mechanism passes; product input domain fails

- ABI/compiler boundary: `2^255` is accepted as `uint256` and converts to
  `int256.min`; `uint256.max` converts to `-1`.
- Product boundary: the only actual source is `1e18`; the transition is
  about `5.79e76` base units, or `5.79e58` units for an 18-decimal token,
  and the source literal cannot be influenced by a caller.
- A quote-only direct caller need not own the nominal tokens, but that does not
  create a protocol loss or denial condition.

## Evidence observed

### Source/control/sink trace

- [CODE] `UniswapV3SwapSimulator.sol:23-26` accepts unrestricted `uint256`.
- [CODE] `UniswapV3SwapSimulator.sol:37` explicitly converts it to
  `int256` without a range check.
- [CODE] `UniswapV3SwapSimulatorCore.sol:88` selects exact-input only when
  the signed amount is positive.
- [CODE] `GroveCompounderAprOracle.sol:213-224` is the sole caller and fixes
  `amountIn: 1e18`.
- [CODE] The repository-wide tracked-Solidity and bounded import/deployment
  adjacency search found no second consumer.

The Solidity documentation warns that explicit conversions can bypass compiler
security properties and demonstrates same-width signed/unsigned two's
complement reinterpretation
([Solidity types documentation](https://docs.soliditylang.org/en/latest/types.html#explicit-conversions)).
Uniswap V3's canonical swap implementation likewise uses the sign of
`amountSpecified` as the mode bit
([Uniswap V3 pool source](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol)).

### Historical precedent / RAG fallback

The bundled vulnerability-database MCP was unavailable in this Codex backend,
so the required historical check used web fallback:

- A Spearbit review of Uniswap V4 Periphery specifically noted that an unsafe
  signed cast could change an exact-input swap to exact-output and rated the
  instance Low
  ([review, section 5.2.2](https://unpkg.com/%40uniswap/universal-router%402.0.0-beta.2/lib/v4-periphery/audits/DRAFT_Spearbit_audit_periphery.pdf)).
- ChainSecurity's EulerSwap review identified out-of-range
  `uint256 -> int256` casts as silent unsafe casts and rated the corrected
  design issue Low
  ([EulerSwap assessment, CS-EULSWP-004](https://reports.chainsecurity.com/Euler/ChainSecurity_Euler_EulerSwap_Audit.pdf)).

Historical precedent: **yes** for the mechanism. Similar exploits with a
matching supported caller and concrete loss: **none found**. Pattern confidence:
**high for numeric/mode confusion, low for exploitability in this target**.
Only two close precedents were found, so no historical-confidence override
applies.

### Evidence audit

| Claim | Evidence source | Tag | Valid for suppression? |
|---|---|---|---|
| `2^255` changes sign and mode | Original target source plus compiled Solidity 0.8.28 harness | [CODE] | Yes |
| The wrapper can return a discontinuous quote | Original wrapper executed against deterministic pool/router stubs | [MOCK] for pool state, [CODE] for wrapper | Supporting mechanism only; not relied on for suppression |
| The sole target caller fixes `1e18` | `GroveCompounderAprOracle.sol:213-224` | [CODE] | Yes |
| No other supported caller exists in the target | Bounded tracked-source/import/script/package/broadcast adjacency pass | [CODE] | Yes |
| Historical deployment metadata links a simulator library to an oracle | Repository broadcast JSON from older commits | [DOC] | Supporting only; not relied on as production proof |
| No sibling finding creates an arbitrary-amount consumer | Canonical candidate inventory and candidate ledgers | [CODE] | Yes |

## PoC attempt

- PoC Required: YES
- PoC Class: unit
- Attempted: YES
- PoC Not Attempted Because: N/A
- Test File:
  `artifacts/05_findings/CAN-009/validation_artifacts/harness/test/CAN009.t.sol`
- Command:
  `forge test --match-test test_CAN009_boundaryModeTransitionAndQuoteDiscontinuity -vvv`

### Execution result

- Compiled: YES (four compile attempts; the first three resolved missing
  initialized-gitlink remappings and harness-only compile annotations)
- Result: PASS — mechanism assertions only
- Fuzz variant: NOT_APPLICABLE (suppressed reachability candidate; no
  reportable Medium+ product-harm premise)
- Output:
  - `quote(int256.max) = 49,996,250,312,472`
  - `quote(2^255) = 49,996,250,312,472`
  - `quote(uint256.max) = 1`
- Evidence tag: **[CODE-TRACE] overall**. The executed harness mechanically
  proves the conversion and quote discontinuity, but it does not assert harm
  to an in-scope consumer, so it is not labeled `[POC-PASS]`.

No fix is proposed because the candidate is suppressed and the PoC did not
establish in-scope harm.

## Counterevidence, devil's advocate, and enabler search

**What would make this exploitable?** A supported caller would need to expose
an attacker-controlled `uint256 amountIn`, consume the library result as an
exact-input quote, and use it for a security-sensitive slippage, trade,
allocation, or availability decision. A later repository version could also
introduce such a caller.

**What was checked?** All tracked Solidity callers/importers, the allowlisted
oracle call, interfaces, tests for deployment adjacency, scripts, broadcasts,
README/package metadata, and the canonical candidate inventory.

**Enablers:** None of CAN-001 through CAN-008 adds a new library consumer or
changes the fixed `1e18` literal. Market manipulation and allocator-consumer
gaps in other candidates do not create attacker control over this parameter.

**Counterevidence:** The fixed source literal is a complete control for every
supported target path. The absence of a documented/exported consumer is also a
scope fact under the canonical threat model, not merely missing runtime setup.

## Remaining uncertainty and reopening condition

An unknown third-party, off-repository integration could independently call
the deployed library and misuse its result. Such a consumer is outside this
scan's explicit nine-file product boundary and no evidence of one was found.
Reopen CAN-009 only if scope expands to a concrete deployed consumer whose
attacker-influenced amount reaches this wrapper and whose action creates
measurable loss or availability harm.

## Severity facts

- Proven impact: anomalous read-only quote for deliberately oversized direct
  calls.
- Proven product impact: none.
- In-scope likelihood: unreachable.
- Attacker profit / victim loss: none established.
- Final severity: **N/A — suppressed**.
- Counterfactual ceiling if a concrete unsafe consumer is later identified:
  **Low** absent quantified asset loss or sustained availability impact; raise
  only from consumer-specific evidence.

## Validation closure

| Ledger row ID | Instance key | Advisory/source | Seed anchor | Root control | Entrypoint/source | Sink/control | Disposition | Counterevidence / proof gap | Survives |
|---|---|---|---|---|---|---|---|---|---|
| `R05W03-L07` | `signed-cast:src/libraries/UniswapV3SwapSimulator.sol:37` | R05W03-C05 / historical cast precedents | `src/libraries/UniswapV3SwapSimulator.sol:23-26` | `src/libraries/UniswapV3SwapSimulator.sol:34-46` | Direct caller-selected quote amount; supported oracle instead fixes `1e18` | Signed cast and sign-selected swap mode at core line 88 | suppressed | No in-scope or directly relied consumer accepts attacker-controlled amount; direct view call has no victim effect | no |

## Artifacts

- `artifacts/05_findings/CAN-009/validation_artifacts/harness/README.md`
- `artifacts/05_findings/CAN-009/validation_artifacts/harness/foundry.toml`
- `artifacts/05_findings/CAN-009/validation_artifacts/harness/test/CAN009.t.sol`
- `artifacts/05_findings/CAN-009/validation_artifacts/logs/forge_test.log`
- `artifacts/05_findings/CAN-009/validation_artifacts/logs/caller_adjacency.md`

Target cleanliness after validation: parent commit
`f8f796db93c52432cca0ed26861e94f5aaf20975`, empty
`git status --porcelain=v1`, and no target `out/` or `cache/` directory.
