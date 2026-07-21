# Late-deposit reward-dilution PoC

This Foundry test reproduces the reward-accounting issue against
`GroveCompounder` revision `f8f796db93c52432cca0ed26861e94f5aaf20975`.
It forks Ethereum at block `25583450`, uses the production fixed staking
contract and AuctionFactory at that block, and deploys an unmodified local
instance of the vulnerable strategy. All state changes occur inside the local
fork; the test sends no transaction to Ethereum.

## Requirements

- Git with submodule support.
- Foundry (`forge`) with Solidity 0.8.28 support.
- Internet access for the initial repository/submodule checkout.
- An archive-capable Ethereum RPC URL that serves block `25583450`.

The RPC may see read requests for public chain state. Do not put a funded
private key in the environment; this PoC does not need one.

## Run

From the directory containing this README:

```sh
export ETH_RPC_URL='https://your-archive-rpc.example'
make test
```

`make test` creates `poc/worktree/`, checks out the exact vulnerable revision
and its pinned submodules, installs the test, verifies both revision and test
file, then runs four tests with 32 fuzz cases. To inspect setup without running
the fork test:

```sh
make setup
make verify
```

## What the test proves

The main sequence deposits 10,000 USDS for the incumbent, waits for GROVE to
accrue, then deposits another 10,000 USDS for a late participant before the
old reward lot is reported. It settles that lot through the real Auction
implementation, reports the resulting USDS, waits through the one-day profit
unlock, and redeems both accounts. Assertions require the late account to
receive pre-entry reward value and the incumbent to lose the same amount of
reward yield.

The remaining tests show that:

- the capture follows the late depositor's post-entry share fraction for
  deposits from 1,000 through 50,000 USDS;
- a 10% performance fee reduces but does not eliminate capture; and
- a closed, unlisted depositor is blocked, while an allowlisted depositor can
  reach the same share-minting path.

## Expected output

Minor gas figures can vary by Foundry version. A successful run includes:

```text
Ran 4 tests for src/test/CAN006Validation.t.sol:CAN006ValidationTest
[PASS] testFuzz_CAN006_LateCaptureScalesWithDeposit(uint96) (runs: 32, ...)
[PASS] test_CAN006_DefaultPerformanceFeeStillLeavesLateCapture()
Logs:
  late depositor profit after 10% performance fee 6865931249141758529
[PASS] test_CAN006_DepositGateIsTheReachabilityCondition()
[PASS] test_CAN006_LateDepositorCapturesPreEntryRewardValue()
Logs:
  claimable before late deposit 151022627237877100000
  pre-entry rewards auctioned 151022627237877100000
  USDS profit reported 15258789062499999856
  late depositor value immediately after report 10000000000000000000000
  late depositor redemption after unlock 10007629394531249999928
  late depositor profit 7629394531249999928
  incumbent redemption after unlock 10007629394531249999928
  incumbent reward dilution 7629394531249999928
Suite result: ok. 4 passed; 0 failed; 0 skipped
```

The integer values use 18 decimals. The late depositor therefore captures
7.629394531249999928 USDS without a performance fee and
6.865931249141758529 USDS with the 10% fee.

## Reliability and safety

The run is deterministic at the pinned block when the RPC serves complete
archive state. The test uses Foundry's `deal` cheatcode only to fund its local
actors; reward accrual, deposits, reports, auction settlement, profit locking,
and redemptions execute through the original interfaces. An RPC that prunes
old state or rate-limits requests can fail before any assertion runs.

No cleanup is required on Ethereum. Remove the local checkout with:

```sh
make clean
```
