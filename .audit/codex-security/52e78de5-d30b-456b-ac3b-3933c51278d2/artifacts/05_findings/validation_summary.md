# Centralized Validation Summary

All nine canonical discovery candidates received an independent centralized validation report and exactly one centralized validation receipt in their candidate ledger. The target remained clean at `f8f796db93c52432cca0ed26861e94f5aaf20975`; all harnesses, Forge outputs, caches, logs, and PoCs are scan-local.

## Closure table

| Candidate / ledger row | Instance key | Root control | Entrypoint / source | Sink / broken control | Disposition | Counterevidence or proof gap | Survives |
|---|---|---|---|---|---|---|---|
| CAN-001 | `swap-slippage:src/GroveCompounder.sol:100` | `src/GroveCompounder.sol:96-105` | Public transaction ordering and GROVE/USDC trading around management-enabled direct mode | Literal zero reaches Uniswap `amountOutMinimum` | deferred | Production-fork sandwich reduced immediate proceeds but was unprofitable before gas and did not prove permanent loss; direct mode is non-default and deployment was not found | uncertain |
| CAN-002 | `oracle-spot-v3:src/periphery/GroveCompounderAprOracle.sol:228` | `src/periphery/GroveCompounderAprOracle.sol:211-245` | Mutable current V3 state | First positive V3 quote is annualized before V4 | deferred | Mechanism reproduced; live branch was dormant and no state-changing allocator consumer or loss was found | uncertain |
| CAN-003 | `oracle-spot-v4:src/periphery/GroveCompounderAprOracle.sol:290` | `src/periphery/GroveCompounderAprOracle.sol:255-305` | Mutable current V4 state with one qualifying quote | One quote self-validates as its median and reaches APR | deferred | Mechanism and 75% understatement reproduced; no deployment, security-sensitive consumer, or manipulation-cost proof | uncertain |
| CAN-004 | `denial-of-service:src/libraries/UniswapV3SwapSimulatorCore.sol:98` | `src/libraries/UniswapV3SwapSimulatorCore.sol:98-179` | Attacker-shaped initialized-tick topology in a qualifying V3 pool | Tick traversal consumes caller gas before fallback | deferred | Harm assertions failed at 5M and 60M gas; 2,800-tick model still returned V4 APR; no selected smaller-spacing pool or consumer gas envelope | uncertain |
| CAN-005 | `reward-expiry-boundary:src/periphery/GroveCompounderAprOracle.sol:114` | `src/periphery/GroveCompounderAprOracle.sol:114-116` | Timestamp exactly equals `periodFinish` | Strict `>` leaves stale nonzero APR for equality block | deferred | Equality mismatch reproduced, but no allocator action, persistence, alternative yield, or loss was found | uncertain |
| CAN-006 | `report-boundary-accounting:src/GroveCompounder.sol:89` | `src/GroveCompounder.sol:89-118` | Open-mode or allowlisted deposit after rewards accrue and before realization | Pending rewards omitted from share-price assets until report | reportable | Requires open deposits or attacker allowlisting; profit locking/fees reduce or delay capture but do not prevent it | yes |
| CAN-007 | `oracle-denominator:src/periphery/GroveCompounderAprOracle.sol:111` | `src/periphery/GroveCompounderAprOracle.sol:111-125` | Permissionless same-block stake/withdraw | Instantaneous global `totalSupply` denominator | deferred | Mechanism reproduced, but 10% movement required ~24.66M USDS and no state-changing consumer or real capital source was proven | uncertain |
| CAN-008 | `report-dos:src/GroveCompounder.sol:108` | `src/GroveCompounder.sol:107-109,174-180` | Active reward auction or public one-wei donation/pre-kick | Unconditional `kick` reverts on already-active token auction | reportable | No principal loss; one-day recovery occurs if the attacker stops renewing, but renewal can continue indefinitely | yes |
| CAN-009 | `signed-cast:src/libraries/UniswapV3SwapSimulator.sol:37` | `src/libraries/UniswapV3SwapSimulator.sol:34-46` | Oversized direct library argument | Signed conversion changes exact-input to exact-output semantics | suppressed | Sole supported caller fixes `amountIn = 1e18`; no attacker-controlled in-scope/deployed consumer exists | no |

## Reportable findings

- CAN-006 — Medium, high confidence (`0.95`): a late depositor can capture part of reward value accrued before entry. Four fork tests passed, including 32 fuzz runs.
- CAN-008 — Medium, high confidence (`0.95`): a public one-wei pre-kick can repeatedly deny reward-bearing reports. Three fork tests passed, including 16 fuzz runs.

## Validation counts

- Reportable: 2
- Deferred: 6
- Suppressed: 1
- Not applicable: 0
