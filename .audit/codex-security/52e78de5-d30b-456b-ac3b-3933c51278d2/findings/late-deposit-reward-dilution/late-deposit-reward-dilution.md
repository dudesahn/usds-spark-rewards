# Late deposits can capture reward value accrued for existing shares

**Severity:** Low (P3)  
**Impact:** Medium  
**Likelihood:** Medium, when deposits are open or the attacker is allowlisted  
**Confidence:** 0.95  
**Weakness:** CWE-682 (Incorrect Calculation), CWE-841 (Improper Enforcement of Behavioral Workflow)

## Executive Summary

`GroveCompounder` issues new shares without accounting for GROVE rewards that
have already accrued to the existing USDS-funded position. The inherited
share-pricing path deliberately uses the last reported asset total, while the
strategy recognizes GROVE only after a keeper claims and sells it. A depositor
who enters between reward accrual and final profit recognition therefore buys
shares at a price that excludes economically earned value. Once the reward
proceeds are reported and profit finishes unlocking, the new shares receive a
pro-rata portion of that pre-entry value.

The affected source basis is repository revision
`f8f796db93c52432cca0ed26861e94f5aaf20975`, which pins
`tokenized-strategy` at `8c8929f1878e8c5ad78aa0a6dabc877a890f68d9`
and `tokenized-strategy-periphery` at
`ab942b245c611cf9747e541ab03b36770c610966`. Any deployment with equivalent
accounting is affected. No fixed revision was available for comparison, and I
did not establish the issue's original introduction point.

I reviewed those exact sources and reproduced the included PoC on a local
Ethereum mainnet fork at block `25583450`. All four tests passed, including 32
fuzz cases. The production staking and auction contracts supplied the external
behavior, while the vulnerable strategy was deployed locally and no live-chain
transaction was sent.

In the concrete equal-deposit run, 151.0226272378771 GROVE was claimable before
the attacker entered. Its auction produced 15.258789062499999856 USDS. After a
10,000-USDS late deposit and the one-day profit unlock, the late depositor
redeemed 10,007.629394531249999928 USDS, diverting
7.629394531249999928 USDS of the old reward lot from the incumbent. The default
10% performance fee reduced capture to 6.865931249141758529 USDS but did not
eliminate it.

This is reward-yield dilution rather than principal insolvency. Exploitation
also requires open deposits or an untrusted allowlisted depositor, material
pending rewards, ordinary keeper settlement, and capital committed through
settlement and profit unlocking. Those constraints support Low/P3 severity
after the required Medium-impact by Medium-likelihood policy calibration.

## Background

`GroveCompounder` accepts USDS, stakes it in a fixed staking contract, and earns
GROVE. A keeper later calls `report()`. The strategy then claims GROVE and either
sells it through Uniswap and the PSM wrapper or transfers it into a configured
Dutch auction. Returned USDS is eventually included in the strategy's reported
assets.

The important distinction is between economic value and reported value.
Pending GROVE is publicly observable:

```solidity
// src/GroveCompounder.sol:70-72
function claimableRewards() external view returns (uint256) {
    return STAKING.earned(address(this));
}
```

Yet `GroveCompounder` does not override the inherited live asset estimator.
The exact inherited implementation explicitly preserves report-boundary
accounting:

```solidity
// lib/tokenized-strategy/src/BaseStrategy.sol:225-244
/**
 * @dev Internal function to return the Strategy's current asset estimate.
 *
 * The default returns `TokenizedStrategy.lastTotalAssets()`, preserving
 * v3.0.4 report-boundary accounting. Strategies that want live accounting
 * should override this with a strictly read-only estimate of all assets,
 * including loose funds.
 */
function _strategyTotalAssets()
    internal
    view
    virtual
    returns (uint256 _totalAssets)
{
    return TokenizedStrategy.lastTotalAssets();
}
```

That default is intentional, but it does not by itself define a safe policy for
which share cohort owns value earned between reports. Here, the economically
earned GROVE belongs to the position funded by existing shares, while the
asset total used to price a new deposit omits it entirely.

Deposits are conditionally reachable. `open` defaults to false; management can
open deposits globally or allowlist individual receivers:

```solidity
// lib/tokenized-strategy-periphery/src/Bases/HealthCheck/BaseHealthCheck.sol:35-39,189-191
// If open is true, anyone can deposit. Else only `allowed[_owner]`.
bool public open;
mapping(address => bool) public allowed;

function availableDepositLimit(address _owner) public view virtual override returns (uint256) {
    if (!open && !allowed[_owner]) return 0;
    return super.availableDepositLimit(_owner);
}
```

Keepers remain trusted to report normally. The attacker neither needs nor gains
a keeper or management role; it only needs permission to make an ordinary
deposit and can observe accrued rewards and transaction ordering on-chain.

Finally, Yearn's locked-profit mechanism prevents newly reported profit from
immediately increasing redeemable value. It mints shares to the strategy and
burns them over `profitMaxUnlockTime`. This smooths price-per-share changes, but
it does not record which external shares existed when the profit was earned.
That distinction becomes decisive after a late deposit.

## Vulnerability Details

We can follow the vulnerable transition from share issuance to reward
recognition. The inherited deposit function accrues the strategy's estimate,
checks the deposit gate, converts assets to shares, and only then transfers the
USDS:

```solidity
// lib/tokenized-strategy/src/TokenizedStrategy.sol:516-540
function deposit(
    uint256 assets,
    address receiver
) external whenNotPaused nonReentrant returns (uint256 shares) {
    StrategyData storage S = _strategyStorage();
    _accrue(S);

    if (assets == type(uint256).max) {
        assets = S.asset.balanceOf(msg.sender);
    }

    require(
        assets <= _maxDeposit(S, receiver),
        "ERC4626: deposit more than max"
    );
    require(
        (shares = _convertToShares(S, assets, Math.Rounding.Down)) != 0,
        "ZERO_SHARES"
    );

    _deposit(S, receiver, assets, shares);
}
```

Although `_accrue()` sounds like it should close the gap, the estimator it
consults reaches the `BaseStrategy._strategyTotalAssets()` implementation
shown above, which returns `lastTotalAssets`. Claimable GROVE, loose GROVE, and
GROVE held by the auction therefore contribute zero to the snapshot used by
`_convertToShares()`.

After conversion, `_deposit()` adds only the incoming USDS to the same stale
reported total and mints the calculated shares:

```solidity
// lib/tokenized-strategy/src/TokenizedStrategy.sol:1096-1117
function _deposit(
    StrategyData storage S,
    address receiver,
    uint256 assets,
    uint256 shares
) internal {
    ERC20 _asset = S.asset;
    _asset.safeTransferFrom(msg.sender, address(this), assets);

    IBaseStrategy(address(this)).deployFunds(
        _asset.balanceOf(address(this))
    );

    S.lastTotalAssets += assets;
    _mint(S, receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);
}
```

Suppose the incumbent owns `A` USDS of reported assets and all `A` shares at a
1:1 price. The position has also earned net reward value `P`, but `P` is absent
from `lastTotalAssets`. A late depositor contributes `B` USDS and receives `B`
shares. When the old reward lot is finally recognized, the outside supply is
already `A + B`, so after locked profit fully unlocks the newcomer captures:

```text
late capture = P * B / (A + B)
```

The state transition is easier to see with the PoC's concrete values:

| Point in time | Reported assets | External shares | Unreported old reward value |
|---|---:|---:|---:|
| Before late entry | 10,000 USDS | 10,000 | 15.258789062499999856 USDS |
| After equal late deposit | 20,000 USDS | 20,000 | 15.258789062499999856 USDS |
| After report and full unlock | 20,015.258789062499999856 USDS | 20,000 | 0 |

The late account consequently receives one half of `P` even though none of its
capital was present while that GROVE accrued.

The strategy's auction path makes the accounting gap span multiple lifecycle
states. `_harvestAndReport()` claims rewards and transfers them to the auction,
but its returned asset total contains only staked and idle USDS:

```solidity
// src/GroveCompounder.sol:89-118
_claimRewards();

uint256 toSwap = balanceOfRewards();
uint256 minRewardAmountToSell = minAmountToSell[REWARDS_TOKEN];

if (!useAuction) {
    if (toSwap > minRewardAmountToSell) {
        require(PSM_WRAPPER.tin() == 0, "!psmFee");
        _swapFrom(REWARDS_TOKEN, base, toSwap, 0);
        PSM_WRAPPER.sellGem(
            address(this),
            ERC20(base).balanceOf(address(this))
        );
    }
} else if (toSwap > minRewardAmountToSell) {
    _kickAuction(REWARDS_TOKEN, toSwap);
}

uint256 balance = balanceOfAsset();
if (!TokenizedStrategy.isShutdown()) {
    if (balance > DUST) {
        _deployFunds(balance);
    }
}
_totalAssets = balanceOfStake() + balanceOfAsset();
```

On the first auction-mode report, we move the old GROVE out of the strategy but
report no USDS profit. Auction inventory is not part of `_totalAssets`. When an
auction buyer later pays USDS to the strategy, that USDS also remains absent
from the public total until a second report because the inherited estimator
still returns `lastTotalAssets`. The second report recognizes the proceeds as
profit against the already enlarged supply.

During that report, the inherited implementation computes profit from
`newTotalAssets - lastTotalAssets`, converts it to locked shares using the
current supply, and updates the last reported value. As the locked shares burn,
both the incumbent and late depositor benefit according to their current share
fractions. Nothing in this process preserves the pre-entry supply as the sole
owner of the old reward lot.

## Exploitability Analysis

The strongest practical route is a capital-backed timing strategy. We watch
`claimableRewards()` and ordinary keeper behavior, choose a reward lot large
enough to exceed gas and opportunity cost, and deposit immediately before its
claim/report sequence. When deposits are open, any EOA or contract can do this.
When deposits are closed, the same path remains available to an untrusted
allowlisted receiver. The PoC confirmed both the closed-unlisted negative
control and the allowlisted positive control.

Deposit size controls the fraction captured. For incumbent assets `A`, late
capital `B`, and distributable old profit `P`, capture approaches all of `P` as
`B` grows much larger than `A`. That upper bound is not free: the attacker must
source increasingly large USDS, accept execution and smart-contract risk, and
forgo alternative yield during the holding period. The 32-case fuzz test varied
`B` from 1,000 to 50,000 USDS and matched `P * B / (A + B)` within rounding.

Auction mode offers a second timing window. Once the first report has kicked
GROVE, the reward lot is even easier to identify, but it remains absent from
share-pricing assets until settlement and another report. A deposit during the
active auction should therefore obtain the same type of exposure. I did not
separately execute that post-kick variant; the included test uses the stronger
demonstration in which the GROVE was already claimable before entry and then
follows the lot through the real auction.

Direct-swap mode shortens the window but does not restore the invariant. A late
deposit before the keeper's swap/report still receives shares at the old
reported price, after which the same report converts pre-entry GROVE into USDS
and locks profit across both cohorts. This route was established from the
source path but was not separately exercised by the auction-focused PoC.

Several controls constrain rather than prevent exploitation:

- **Deposit access.** A closed strategy with only trusted allowlisted
  depositors removes the ordinary attacker path. Open deposits or an untrusted
  allowlisted participant are necessary conditions.
- **Pending value.** The old reward lot must be material. Tiny lots can be
  uneconomic after gas, capital cost, and price/settlement uncertainty.
- **Keeper progress.** The attacker cannot call `report()` without the role and
  relies on an authorized keeper eventually performing normal operations. No
  malicious keeper or role compromise is needed.
- **Capital duration.** In the tested auction route, settlement took 16 hours
  and profit unlocking another day, for roughly 40 hours in total. Immediate
  post-report `previewRedeem()` showed principal but none of the captured
  profit, so the demonstrated route is not flash-loan-only.
- **Fees.** Performance and protocol fees reduce distributable profit. With a
  10% performance fee, the equal late deposit still captured
  6.865931249141758529 USDS.
- **Profit locking.** Locked shares delay the price increase; they do not bind
  the reward to the shares that existed when it accrued. After the one-day
  unlock, capture was fully observable.

The economic consequence is a transfer of yield between depositors, not loss
of USDS backing. Repeating the timing strategy at successive report boundaries
can make the loss recurring, but each attempt remains bounded by the pending
reward value and the attacker's share fraction. These constraints are why the
finding is Low/P3 despite a reproducible Medium-impact, Medium-likelihood
cross-depositor primitive.

## Proof of Concept

The accompanying `poc/` directory contains the exact Foundry test, a revision-
pinned setup, and representative output. From the report directory, run:

```sh
cd poc
export ETH_RPC_URL='https://your-archive-rpc.example'
make test
```

The RPC must serve Ethereum block `25583450`. The harness locally deploys the
unmodified vulnerable `GroveCompounder`, uses production staking and
AuctionFactory code at the forked block, and funds only local actors with
Foundry's `deal` cheatcode. The sequence then uses normal deposits, staking
accrual, keeper reports, auction settlement, locked-profit accounting, and
redemption. It does not broadcast a transaction.

My reproduced run produced four passing tests and these decisive values:

| Observation | Result |
|---|---:|
| Incumbent deposit | 10,000 USDS |
| GROVE claimable before late entry | 151.0226272378771 GROVE |
| Late deposit / shares minted | 10,000 USDS / 10,000 shares |
| USDS profit from old lot | 15.258789062499999856 USDS |
| Late value immediately after report | 10,000 USDS |
| Late redemption after unlock | 10,007.629394531249999928 USDS |
| Captured old reward value | 7.629394531249999928 USDS |
| Capture with 10% performance fee | 6.865931249141758529 USDS |

Representative output is:

```text
Ran 4 tests for src/test/CAN006Validation.t.sol:CAN006ValidationTest
[PASS] testFuzz_CAN006_LateCaptureScalesWithDeposit(uint96) (runs: 32, ...)
[PASS] test_CAN006_DefaultPerformanceFeeStillLeavesLateCapture()
  late depositor profit after 10% performance fee 6865931249141758529
[PASS] test_CAN006_DepositGateIsTheReachabilityCondition()
[PASS] test_CAN006_LateDepositorCapturesPreEntryRewardValue()
  claimable before late deposit 151022627237877100000
  USDS profit reported 15258789062499999856
  late depositor redemption after unlock 10007629394531249999928
  late depositor profit 7629394531249999928
  incumbent reward dilution 7629394531249999928
Suite result: ok. 4 passed; 0 failed; 0 skipped
```

An archive-node failure or rate limit can stop setup before assertions execute;
it does not indicate a fixed target. Cleanup affects only the local checkout:

```sh
make clean
```

## Remediation

The invariant to restore is simple to state: **a deposit must not mint shares
until every economically owned value item from the preceding share cohort is
either included in the mint price or reserved exclusively for that cohort.**
This includes claimable GROVE, loose GROVE, auction-held GROVE, and returned
USDS that has not yet crossed a report boundary.

A minimal fail-closed patch can replace the existing deposit-limit override and
suspend new deposits whenever any such value is detectable, allowing deposits
only after keepers settle and report the old lot:

```solidity
// Proposed defensive stopgap in GroveCompounder; not an existing remediation.
function _hasUncheckpointedValue() internal view returns (bool) {
    if (STAKING.earned(address(this)) != 0) return true;
    if (balanceOfRewards() != 0) return true;

    address currentAuction = auction;
    if (
        currentAuction != address(0) &&
        ERC20(REWARDS_TOKEN).balanceOf(currentAuction) != 0
    ) return true;

    uint256 currentUsds = balanceOfStake() + balanceOfAsset();
    return currentUsds != TokenizedStrategy.lastTotalAssets();
}

function availableDepositLimit(
    address receiver
) public view override returns (uint256) {
    if (_hasUncheckpointedValue()) return 0;
    return super.availableDepositLimit(receiver);
}
```

This stopgap favors accounting safety over availability. Because GROVE can
accrue continuously, an exact nonzero check may leave very little time for
deposits. A dust threshold improves availability only by explicitly accepting
a bounded amount of redistribution, which should be documented and tested.

For a durable open-deposit design, we recommend a structural checkpoint or
reservation mechanism instead:

1. Snapshot pending reward entitlement before minting new shares and reserve
   the realized proceeds for the pre-entry supply, including while the lot is
   held by the auction.
2. Alternatively, override live asset accounting to include a conservative,
   manipulation-resistant USDS value for claimable, loose, and auction-pending
   rewards. A raw spot quote is not sufficient because it replaces this bug
   with price-manipulation exposure.
3. Make one source of truth cover every reward lifecycle state: unclaimed,
   claimed, auction-held, returned as idle USDS, reported, and unlocked.
4. Expose an `uncheckpointedValue` or reservation view and monitor deposits
   that occur near reward settlement, rather than treating fees or locked
   profit as ownership controls.

Regression tests should exercise the actual boundary, not only final totals:

- With deposits open, accrue GROVE before a second depositor enters and assert
  that the newcomer cannot redeem any of that pre-entry lot.
- Repeat when the newcomer is allowlisted under closed mode.
- Deposit after GROVE is kicked but before auction settlement, and again after
  USDS returns but before the second report.
- Cover direct-swap and auction modes, zero/default/protocol fees, and zero/
  nonzero profit-unlock times.
- Fuzz incumbent assets, late capital, reward size, and rounding boundaries;
  assert that pre-entry reward entitlement remains with pre-entry shares.
- Confirm that deposits resume after a complete settlement/checkpoint and that
  principal withdrawals remain available while deposits are suspended.

## Summary

The strategy separates share minting from reward recognition without reserving
the intervening reward value. We first price the late depositor against
`lastTotalAssets`; we then realize the incumbent-funded GROVE over the enlarged
supply; finally, locked-profit shares burn and let the newcomer redeem part of
the old lot. The mainnet-fork PoC demonstrated a matching gain and incumbent
dilution, while fee and access-control tests established the practical bounds.

The immediate engineering priority is to prevent deposits whenever old value
is outside the pricing snapshot, then replace that stopgap with a lifecycle-
complete reservation or conservative live-NAV design if open deposits are a
product requirement. Further review should focus on each transition between
unclaimed rewards, auction inventory, returned proceeds, reported profit, and
unlocked profit, because any unrepresented state recreates the same cohort-
ownership mismatch.
