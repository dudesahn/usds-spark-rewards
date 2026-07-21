# Permissionless auction pre-kicks can deny strategy reports

| Field | Value |
|---|---|
| Severity | Medium |
| Priority | P2 |
| Confidence | 0.95 |
| Affected component | `GroveCompounder` auction-mode reward realization |
| Confirmed affected revision | `f8f796db93c52432cca0ed26861e94f5aaf20975` |
| Fixed revision | None identified |

## Executive Summary

`GroveCompounder` unconditionally starts a GROVE reward auction during
`report()` whenever auction mode is enabled and the claimed reward balance is
above the sale threshold. The configured Auction rejects a kick while an
auction for the same token is active. Because its kick entrypoint is public in
the tested configuration, an unprivileged account can donate one wei of GROVE
to the Auction and kick it immediately before a keeper report. The keeper's
later kick then reverts with `"too soon"`, rolling back the complete report and
leaving `lastReport` unchanged.

The attacker needs no strategy role and no meaningful capital: the tested path
requires one wei of GROVE plus gas. If the dust remains unsold, the same wei can
be re-kicked after each one-day auction window. This makes report availability,
reward recognition, and report-time maintenance repeatably attacker-controlled.
The demonstrated impact is denial of service, not loss of depositor principal.
The failed transfer is atomic, withdrawals were not shown to fail, and an
uncontested expiry window or management reconfiguration restores reporting.

I reviewed the exact affected revision and its pinned Auction source, and I
verified that the shipped Forge test is semantically identical to the test from
the successful mainnet-fork run at block `25583832`, with only descriptive
identifier changes: three tests passed, including 16 bounded fuzz runs. I also
attempted an independent rerun, but the unauthenticated RPC
endpoint refused historical-state access before test setup; I therefore rely
on the preserved successful output rather than claiming that later attempt
passed. I did not send transactions to a live deployment, enumerate every
deployed strategy/Auction pair, or validate a fixed revision because no
remediation was available.

The vulnerable auction call pattern has been present in repository history
since commit `dbd6a0e9d9abbc9a9178af5ca523bfef191ef932` (July 4, 2025), across
the strategy's earlier naming and later Grove port. This report makes an
affected-version claim only for the exact revision tested above; deployment
configuration can change whether the permissionless pre-kick route is exposed.

## Background

`GroveCompounder` is a Yearn V3 tokenized strategy. It accepts USDS, stakes that
principal in the configured staking contract, claims GROVE rewards, and turns
those rewards into more USDS. It supports either a direct Uniswap route or an
external Auction. Auction mode defaults to enabled, while management supplies
the Auction address.

The inherited tokenized-strategy `report()` function is keeper-restricted. It
calls back into the strategy's `harvestAndReport()` implementation before it
updates accounting and `lastReport`:

```solidity
// lib/tokenized-strategy/src/TokenizedStrategy.sol:1400-1418,1512-1514
function report()
    external
    nonReentrant
    onlyKeepers
    returns (uint256 profit, uint256 loss)
{
    StrategyData storage S = _strategyStorage();
    _accrue(S);

    uint256 newTotalAssets = IBaseStrategy(address(this))
        .harvestAndReport();
    // ... profit/loss accounting ...
    S.lastTotalAssets = newTotalAssets;
    S.lastReport = uint96(block.timestamp);
}
```

This ordering matters. If reward realization reverts, we never reach the final
accounting writes. Keeper authorization protects who may invoke `report()`, but
it does not protect the external Auction state that the report consumes.

The strategy constructor sets a `5,000e18` GROVE sale threshold. When the
reward balance exceeds it, the auction branch calls `_kickAuction`:

```solidity
// src/GroveCompounder.sol:89-109
_claimRewards();

uint256 toSwap = balanceOfRewards();
uint256 minRewardAmountToSell = minAmountToSell[REWARDS_TOKEN];

if (!useAuction) {
    if (toSwap > minRewardAmountToSell) {
        // direct sale path omitted
    }
} else if (toSwap > minRewardAmountToSell) {
    _kickAuction(REWARDS_TOKEN, toSwap);
}
```

Management's `setAuction()` compatibility checks cover the Auction's receiver
and wanted asset, but they do not establish how an already-active reward-token
auction should be handled:

```solidity
// src/GroveCompounder.sol:209-216
function setAuction(address _auction) external onlyManagement {
    if (_auction != address(0)) {
        require(Auction(_auction).receiver() == address(this), "receiver");
        require(Auction(_auction).want() == address(asset), "want");
    } else {
        require(!useAuction, "!auction");
    }
    auction = _auction;
}
```

The pinned Auction lasts one day. Its public `kick()` uses the contract's
current token balance as the lot. Governance authorization is conditional, and
the active-state guard rejects duplicate kicks:

```solidity
// lib/tokenized-strategy-periphery/src/Auctions/Auction.sol:503-520
function kick(address _from) external virtual nonReentrant returns (uint256 _available) {
    return _kick(_from);
}

function _kick(address _from) internal virtual returns (uint256 _available) {
    if (governanceOnlyKick) _checkGovernance();

    require(auctions[_from].scaler != 0, "not enabled");
    require(!isActive(_from), "too soon");

    _available = ERC20(_from).balanceOf(address(this));
    require(_available != 0, "nothing to kick");

    auctions[_from].kicked = uint64(block.timestamp);
    auctions[_from].initialAvailable = uint128(_available);
}
```

In the production-factory clone exercised by the PoC, an arbitrary address's
one-wei donation and direct `kick(GROVE)` succeeded. We therefore do not need to
assume that the attacker can impersonate a keeper, management, or governance.

## Vulnerability Details

The missed invariant is simple: **a strategy report must not attempt to transfer
and kick rewards when the configured Auction already has an active auction for
that token**. `_kickAuction()` neither checks this state nor treats the sale as
optional:

```solidity
// src/GroveCompounder.sol:174-180
function _kickAuction(address _token, uint256 _balance) internal {
    require(_token != address(asset), "!asset");
    address _auction = auction;
    require(_auction != address(0), "!auction");
    ERC20(_token).safeTransfer(_auction, _balance);
    Auction(_auction).kick(_token);
}
```

We can carry the externally controlled Auction state through the full attack as
follows:

| Step | Auction GROVE state | Strategy/report state |
|---|---|---|
| 1. Attacker donates | Balance becomes `1` wei; no active auction yet | Rewards continue accruing in staking |
| 2. Attacker calls `kick(GROVE)` | `kicked = block.timestamp`, `initialAvailable = 1`; auction is active | No strategy role is used |
| 3. Keeper calls `report()` | Active state remains true | Strategy claims more than `5,000e18` GROVE |
| 4. Strategy calls `_kickAuction()` | Transfer is attempted, then `kick()` sees active state | `kick()` reverts with `"too soon"` |
| 5. Transaction rolls back | Balance returns to its pre-report value | Claim, transfer, accounting, and `lastReport` update are all reverted |

The attacker controls both the initial dust balance and the time of the first
kick. The enabled-token check is already satisfied for the strategy's intended
GROVE auction. A single wei satisfies the Auction's only lot-size condition,
`_available != 0`. The strategy-side `5,000e18` threshold does not help because
it applies to the strategy's claimed rewards, not to the public caller's lot.

When the keeper reaches the reward branch, the safe transfer runs before the
external kick. Solidity's atomic revert semantics prevent that transfer from
becoming a loss, but they also revert every earlier action in the same report.
We therefore get a clean availability primitive: the report returns no result,
the newly claimed reward state is undone, and `lastReport` remains stale.

The same collision can occur without an attacker. One ordinary reward-bearing
report starts an auction; if another report accrues more than the threshold
before that auction ends, it takes the same unconditional path and reverts. The
public pre-kick route is stronger because it makes the collision intentional
and lets an account with no protocol role choose the blocking window.

## Exploitability Analysis

The strongest route is a pre-positioning attack. We first watch for a routine
keeper report or simply maintain an active dust auction continuously. Before
the keeper transaction executes, we transfer one wei of GROVE to the configured
Auction and call `kick(GROVE)`. From here, the exact size of the strategy's
reward claim is irrelevant as long as it exceeds its own sale threshold: every
such report reaches the active-kick rejection.

The pre-kick can also be ordered ahead of a visible keeper transaction in the
public mempool. The PoC does not depend on a same-block race, however. Kicking at
any point during the preceding day creates the same state, so the attacker can
trade precision for reliability. At the end of the one-day interval, the
attacker can kick again. The deterministic test renewed the denial with the
same unsold wei after `auctionLength() + 1`; if a bidder purchases that dust,
the attacker would need to donate another nonzero amount.

Sustained denial is not perfectly continuous by construction. Once an auction
expires, a keeper can report before the attacker's renewal, and management can
change the Auction or switch sale mode. The attacker must therefore win
transaction ordering at each renewal boundary to prevent every report. Public
mempool visibility, the one-transaction renewal, and negligible capital make
that realistic, but this recovery race is an important bound on impact.

Restricting Auction kicks to governance removes the unprivileged pre-kick route
where that control exists and is correctly configured. It does not repair the
integration invariant: a normal strategy-created auction can still be active
when the next report tries to kick. Likewise, increasing the sale threshold may
reduce collision frequency but cannot make the state transition safe.

The consequence is delayed reporting and delayed realization of accumulated
GROVE, not demonstrated theft. We found no evidence that a failed report moves
principal, leaves the attempted GROVE transfer in the Auction, blocks ordinary
withdrawals, or permanently corrupts accounting. The report path recovers once
an active window expires without renewal. Those constraints are why the issue
is Medium/P2 rather than High despite its low-cost, repeatable trigger.

## Proof of Concept

The `poc/` directory contains the exact Forge integration test and a small
runner that obtains the affected revision and its pinned submodules in an
isolated `.worktree/` directory. It uses mainnet state only through an RPC fork;
it does not broadcast transactions.

From this report directory, run:

```sh
export ETH_RPC_URL="https://your-archive-mainnet-rpc.example"
cd poc
make test
```

The suite exercises three complementary cases:

1. A normal report starts an auction, and a second report 12 hours later
   reverts before recovering after expiry.
2. An arbitrary account donates one wei, pre-kicks, blocks a report, re-kicks
   the same unsold wei after one day, blocks another report, and then stops so
   reporting can recover.
3. A bounded fuzz test varies the donation over `1..1e18` wei and the report
   delay over `0..23 hours` for 16 runs.

The deterministic denial checks both the revert and its accounting effect:

```solidity
uint256 lastReportBeforeBlockedAttempt = strategy.lastReport();

vm.prank(keeper);
vm.expectRevert("too soon");
strategy.report();

assertEq(
    strategy.lastReport(),
    lastReportBeforeBlockedAttempt,
    "blocked report updated accounting"
);
```

Representative output from the pinned reproduction is:

```text
[PASS] testFuzz_publicPreKickBlocksThroughoutActiveWindow(uint96,uint32) (runs: 16)
[PASS] test_normalTwoReportCollisionAndRecovery()
[PASS] test_permissionlessDustPreKickBlocksReportAndRecovery()
Suite result: ok. 3 passed; 0 failed; 0 skipped
```

On a corrected implementation, the two tests that expect `"too soon"` from
`report()` should fail until their assertions are updated to require successful
reporting while an auction is active. No fixed revision was available for a
comparative run. Requirements, expected behavior, safe operation, and cleanup
are documented in `poc/README.md`; `make clean` removes only the runner's local
`.worktree/` directory.

## Remediation

Restore the integration invariant at the point where the strategy still owns
the newly claimed rewards: if the reward-token Auction is active, leave those
rewards in the strategy and allow the report to finish. A later report can
transfer the accumulated balance and start a new auction after expiry.

A minimal patch is:

```solidity
function _kickAuction(address _token, uint256 _balance) internal {
    require(_token != address(asset), "!asset");
    address _auction = auction;
    require(_auction != address(0), "!auction");

    // Reward sale is deferred; report/accounting must remain live.
    if (Auction(_auction).isActive(_token)) return;

    ERC20(_token).safeTransfer(_auction, _balance);
    Auction(_auction).kick(_token);
}
```

The check must occur before the transfer. Catching the later revert after the
transfer is not a viable equivalent because Solidity cannot catch an ordinary
internal sequence selectively, and allowing the report to proceed after moving
tokens without a successfully initialized auction would create a different
accounting and custody problem.

The patch above has not been applied or validated in a fixed revision. The
following regression tests should accompany it:

- pre-kick with exactly one wei as an arbitrary account, then assert an
  above-threshold keeper `report()` succeeds and advances `lastReport`;
- assert claimed GROVE stays in the strategy while the Auction is active;
- after expiry, assert a later report transfers the full accumulated GROVE and
  starts exactly one new auction;
- retain the normal two-report case to prove rapid report cadence is safe;
- fuzz donation sizes, report timing across the expiry boundary, reward
  balances around the sale threshold, and repeated active/expired transitions;
- exercise management changes to the Auction and `useAuction` around active
  windows.

For structural hardening, separate reporting from best-effort reward sale.
Model reward realization as an explicit state machine—`idle`, `active`, and
`kickable`—whose failure cannot roll back core accounting. Validate an Auction's
enabled reward token and kick policy when configuring it, monitor active and
pending reward balances, and emit a deferral event when sale is skipped.
Restricting public kicks where supported is useful defense in depth, but it must
not replace active-state tolerance because ordinary strategy kicks can collide
too.

## Summary

An unprivileged caller can turn one wei of GROVE into a repeatable report-denial
primitive by activating the strategy's configured Auction before the keeper
reports. We traced that external state into the unconditional
`_kickAuction()` call, reproduced the Auction's `"too soon"` rejection, and
confirmed that the complete report rolls back without advancing `lastReport`.
The same underlying state-machine collision also occurs naturally between two
reward-bearing reports inside one auction window.

No principal loss or withdrawal denial was demonstrated, and reporting resumes
after an uncontested one-day expiry or management reconfiguration. The durable
fix is therefore not to treat the Auction revert as fatal: reports should defer
reward sale while an auction is active, retain the rewards safely, and kick
only when the downstream state machine is ready. Future variant analysis should
focus on other report-time external integrations where optional maintenance is
allowed to roll back core accounting.
