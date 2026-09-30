# Validation Ledger

## Promoted Findings

| ID | Candidate sources | Validation | Status |
|---|---|---|---|
| G-01 auction-returned reward dilution | invariant, economic-security, first-principles | Focused Foundry PoC passed; source trace confirms auction payment to strategy and stale deposit accounting. | Confirmed |
| G-02 zero-min direct UniV3 sale | asymmetry, trust-gap, economic-security | Source-level validation confirms direct branch passes literal zero min-out to inherited swapper. Conditional on management enabling direct mode. | Confirmed conditional |

## Promoted Leads

| ID | Candidate sources | Reason promoted as lead |
|---|---|---|
| L-01 V3 spot preempts V4 median | execution-trace, periphery, economic-security, asymmetry, boundary, numerical-gap, flow-gap, first-principles | Repeated across lanes and source-backed, but needs downstream APR consumer and manipulation-cost validation. |
| L-02 singleton V4 median | numerical-gap, periphery | Source-backed one-survivor behavior, but feasibility with live configured pools needs validation. |
| L-03 active auction report revert | boundary, flow-gap/trust-gap notes | Source-backed liveness path, but depends on keeper timing and reward accrual during an active auction. |
| L-04 mutable auction receiver | trust-gap | Source-backed dependency behavior, but deployment governance may make it trusted. |

## Rejected / De-escalated

| Candidate | Reason |
|---|---|
| APR negative `_delta` underflow/revert | Caller supplies invalid view query; no in-scope state-changing path found. |
| Exact `periodFinish` boundary | One-timestamp edge with no proven consumer impact. |
| Zero reward-rate price dependency | Plausible view-liveness issue, but live staking state feasibility not proven. |
| Non-reward token threshold mismatch | Keeper-gated recovery awkwardness; no asset-loss path found. |
| Management can misconfigure V4 pools | Trusted configuration surface, not a vulnerability by itself. |

## Test Evidence

Full fork suite:

```text
forge test -vv --fork-url https://ethereum.publicnode.com
Ran 4 test suites in 4.64s (14.81s CPU time): 26 tests passed, 0 failed, 0 skipped (26 total tests)
```

Focused PoC:

```text
forge test --match-path src/test/CodexAuctionDilution.t.sol --match-test test_jitDepositCapturesUnreportedAuctionProceeds -vv --fork-url https://ethereum.publicnode.com
[PASS] test_jitDepositCapturesUnreportedAuctionProceeds() (gas: 1115355)
```
