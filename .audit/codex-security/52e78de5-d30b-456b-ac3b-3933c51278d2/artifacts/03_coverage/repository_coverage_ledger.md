# Repository Coverage Ledger

Authoritative production scope: all nine allowlisted Solidity files. Every file has six independent round-01 completion receipts. Tests were validation-only. Vendored source was consulted only where directly required to trace an allowlisted call.

| Row | Boundary / family | Files checked | Candidate | Disposition | Evidence / closure |
|---|---|---|---|---|---|
| COV-001 | Strategy lifecycle, accounting, unauthorized principal transfer, reentrancy | `src/GroveCompounder.sol`; relevant first-party interfaces | — | suppressed | Fixed staking/PSM addresses, self-only inherited hooks, atomic external calls, and stake-plus-idle accounting expose no unprivileged destination or local share-math bypass. |
| COV-002 | Direct reward sale / MEV and price constraint | `src/GroveCompounder.sol:84-118` | CAN-001 | candidate | Literal zero minimum output reaches the exact-input reward sale. |
| COV-003 | Auction reward sale / authz and arbitrary token transfer | `src/GroveCompounder.sol:153-180,204-227` | — | suppressed | Keeper/management gates, strategy-asset prohibition, and receiver/want checks close unprivileged transfer paths. |
| COV-004 | Fixed staking and PSM integrations | `src/GroveCompounder.sol`; `src/interfaces/IStaking.sol`; `src/interfaces/IPsmWrapper.sol` | — | suppressed | Targets and token compatibility are fixed; external protocol compromise remains an assumption, not a first-party bypass. |
| COV-005 | Primary V3 APR price integrity | Oracle and V3 simulator files | CAN-002 | candidate | Live V3 state is accepted without a TWAP or independent-source check. |
| COV-006 | V4 fallback price integrity and quorum | Oracle and V4 StateView interface | CAN-003 | candidate | A mutable current quote can pass as its own median; no trustworthy minimum quorum exists. |
| COV-007 | V3 simulator resource bounds | V3 simulator wrapper/core and oracle caller | CAN-004 | candidate | Tick-dependent traversal has no iteration, complexity, or isolated-gas bound; runtime cost remains to be validated. |
| COV-008 | Reward schedule expiry boundary | `src/periphery/GroveCompounderAprOracle.sol:109-132`; `src/interfaces/IStaking.sol` | CAN-005 | candidate | Strict `>` permits equality to remain on the nonzero APR path; deployed semantics remain to be validated. |
| COV-009 | APR signed debt adjustment and numeric conversion | `src/periphery/GroveCompounderAprOracle.sol:109-132` | — | suppressed | Invalid deltas revert under checked arithmetic; no in-repository consumer exposes arbitrary privileged state transitions. |
| COV-010 | Oracle administration and configuration authz | `src/periphery/GroveCompounderAprOracle.sol:77-176,338-363` | — | suppressed | Mutations are management-gated and core zero/duplicate/length checks exist; trusted misconfiguration remains operational risk. |
| COV-011 | Interface-only implementation surfaces | all five `src/interfaces/*.sol` files | — | not_applicable | ABI declarations contain no independent enforcement or state; concrete call sites are covered above. |
| COV-012 | Non-EVM application families | all nine files | — | not_applicable | No shell/query/template/deserializer/filesystem/HTTP/session/tenant surface exists in production scope. |
| COV-013 | Management-sized V4 arrays / quadratic sort availability | oracle configuration and median implementation | — | suppressed | Only trusted management controls array size and can repair configuration; no unprivileged size input exists. |
| COV-014 | Report-boundary accounting / reward dilution | `src/GroveCompounder.sol:70-72,89-118` | CAN-006 | candidate | Pending claimable rewards and auction inventory are not represented in share-price assets until later realization; depositor-timing impact requires centralized validation. |
| COV-015 | Instantaneous staking-supply denominator integrity | `src/periphery/GroveCompounderAprOracle.sol:109-132`; `src/interfaces/IStaking.sol:13-25` | CAN-007 | candidate | Unrelated same-block staking supply changes are not normalized; capital cost and consumer impact require centralized validation. |
| COV-016 | Reward-auction state-machine liveness | `src/GroveCompounder.sol:84-118,174-180`; directly relied-on auction `Auction.sol:503-520` | CAN-008 | candidate | A later reward-bearing report can call `kick` while the same token auction is active; runtime sequence and operational impact require centralized validation. |
| COV-017 | Simulator exported-API signed-range integrity | `src/libraries/UniswapV3SwapSimulator.sol:23-46` | CAN-009 | candidate | Values at or above 2^255 change sign and simulation mode; no allowlisted caller reaches that range, so centralized reachability validation is required. |

No row is deferred after round 01. Candidate rows remain open for centralized validation after discovery saturation.
