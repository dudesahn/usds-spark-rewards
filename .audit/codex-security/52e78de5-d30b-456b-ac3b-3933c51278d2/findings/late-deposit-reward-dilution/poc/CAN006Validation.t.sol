// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface, Auction} from "src/test/utils/Setup.sol";

/// @notice Focused validation for CAN-006 against the original GroveCompounder.
/// The live staking contract supplies the pre-entry rewards and the pinned Auction
/// implementation performs the reward-for-USDS settlement.
contract CAN006ValidationTest is Setup {
    address internal constant LATE_DEPOSITOR = address(11);
    address internal constant AUCTION_BUYER = address(12);

    uint256 internal constant INCUMBENT_DEPOSIT = 10_000e18;

    struct Outcome {
        uint256 claimableBeforeLateDeposit;
        uint256 auctionedRewards;
        uint256 reportedProfit;
        uint256 immediateLateValue;
        uint256 lateRedemption;
        uint256 incumbentRedemption;
    }

    function setUp() public override {
        super.setUp();

        // Isolate the depositor redistribution from fee allocation. Fees only
        // reduce the profit left for both depositors; they do not assign old
        // reward value to the incumbent.
        vm.prank(management);
        strategy.setPerformanceFee(0);
    }

    function test_CAN006_LateDepositorCapturesPreEntryRewardValue() public {
        Outcome memory result = _runTwoDepositorSequence(INCUMBENT_DEPOSIT);

        uint256 attackerProfit = result.lateRedemption - INCUMBENT_DEPOSIT;
        uint256 incumbentProfit = result.incumbentRedemption - INCUMBENT_DEPOSIT;

        console2.log("claimable before late deposit", result.claimableBeforeLateDeposit);
        console2.log("pre-entry rewards auctioned", result.auctionedRewards);
        console2.log("USDS profit reported", result.reportedProfit);
        console2.log("late depositor value immediately after report", result.immediateLateValue);
        console2.log("late depositor redemption after unlock", result.lateRedemption);
        console2.log("late depositor profit", attackerProfit);
        console2.log("incumbent redemption after unlock", result.incumbentRedemption);
        console2.log("incumbent reward dilution", result.reportedProfit - incumbentProfit);

        // Harm assertion: the late depositor receives USDS profit derived from
        // GROVE that was already claimable before that depositor entered.
        assertGt(attackerProfit, 0, "late depositor captured no pre-entry value");

        // Profit locking delays the extraction but does not reserve the profit
        // for the incumbent. Immediately after report Bob is still near principal.
        assertApproxEqAbs(
            result.immediateLateValue,
            INCUMBENT_DEPOSIT,
            2,
            "profit locking did not hold immediate PPS"
        );

        // Equal deposits split the eventually unlocked profit approximately 50/50.
        assertApproxEqAbs(attackerProfit, result.reportedProfit / 2, 3, "wrong late-depositor capture share");
        assertApproxEqAbs(incumbentProfit, result.reportedProfit / 2, 3, "wrong incumbent profit share");
        assertLt(incumbentProfit, result.reportedProfit, "incumbent retained all pre-entry reward value");
    }

    function testFuzz_CAN006_LateCaptureScalesWithDeposit(uint96 rawLateDeposit) public {
        uint256 lateDeposit = bound(uint256(rawLateDeposit), 1_000e18, 50_000e18);
        Outcome memory result = _runTwoDepositorSequence(lateDeposit);

        uint256 attackerProfit = result.lateRedemption - lateDeposit;
        uint256 expectedCapture = (result.reportedProfit * lateDeposit) /
            (INCUMBENT_DEPOSIT + lateDeposit);

        assertGt(attackerProfit, 0, "late depositor captured no pre-entry value");
        assertApproxEqAbs(attackerProfit, expectedCapture, 4, "capture did not follow post-deposit share fraction");
    }

    function test_CAN006_DefaultPerformanceFeeStillLeavesLateCapture() public {
        vm.prank(management);
        strategy.setPerformanceFee(1_000);

        Outcome memory result = _runTwoDepositorSequence(INCUMBENT_DEPOSIT);
        uint256 attackerProfit = result.lateRedemption - INCUMBENT_DEPOSIT;

        console2.log("late depositor profit after 10% performance fee", attackerProfit);
        assertGt(attackerProfit, 0, "default performance fee eliminated late capture");
        assertLt(attackerProfit, result.reportedProfit / 2, "performance fee did not reduce capture");
    }

    function test_CAN006_DepositGateIsTheReachabilityCondition() public {
        vm.prank(management);
        strategy.setOpen(false);

        airdrop(asset, LATE_DEPOSITOR, 1e18);
        vm.prank(LATE_DEPOSITOR);
        asset.approve(address(strategy), 1e18);

        vm.prank(LATE_DEPOSITOR);
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(1e18, LATE_DEPOSITOR);

        vm.prank(management);
        strategy.setAllowed(LATE_DEPOSITOR, true);

        vm.prank(LATE_DEPOSITOR);
        uint256 shares = strategy.deposit(1e18, LATE_DEPOSITOR);
        assertEq(shares, 1e18, "allowlisted depositor did not reach deposit path");
    }

    function _runTwoDepositorSequence(uint256 lateDeposit) internal returns (Outcome memory result) {
        // Alice funds the strategy and is the sole shareholder while GROVE accrues.
        mintAndDepositIntoStrategy(strategy, user, INCUMBENT_DEPOSIT);
        skip(strategy.profitMaxUnlockTime());

        result.claimableBeforeLateDeposit = strategy.claimableRewards();
        assertGt(result.claimableBeforeLateDeposit, 50e18, "insufficient pre-entry rewards");
        assertEq(strategy.totalAssets(), INCUMBENT_DEPOSIT, "pending rewards entered totalAssets");

        // Bob enters at the stale report-boundary PPS. Setup has opened deposits.
        mintAndDepositIntoStrategy(strategy, LATE_DEPOSITOR, lateDeposit);
        assertEq(strategy.balanceOf(LATE_DEPOSITOR), lateDeposit, "late shares were not minted at stale PPS");
        assertEq(
            strategy.totalAssets(),
            INCUMBENT_DEPOSIT + lateDeposit,
            "pending rewards affected post-deposit totalAssets"
        );

        // The first report claims Alice's already-accrued GROVE and kicks it to
        // the real pinned Auction, while recognizing no USDS profit.
        vm.prank(keeper);
        (uint256 firstProfit, uint256 firstLoss) = strategy.report();
        assertEq(firstProfit, 0, "first report unexpectedly recognized reward value");
        assertEq(firstLoss, 0, "first report loss");

        address rewardToken = strategy.REWARDS_TOKEN();
        result.auctionedRewards = ERC20(rewardToken).balanceOf(address(auction));
        assertGe(
            result.auctionedRewards,
            result.claimableBeforeLateDeposit,
            "pre-entry rewards were not sent to auction"
        );

        // Prevent fresh post-entry rewards from re-kicking the still-active
        // auction during the second report. This does not change the old lot.
        vm.prank(management);
        strategy.setMinAmountToSell(type(uint256).max);

        // Settle the old reward lot through the actual Auction implementation.
        // At 16 hours the deployed Dutch price is below the 100% health-check
        // cap while still producing a material, economically testable reward.
        skip(16 hours);
        uint256 needed = auction.getAmountNeeded(rewardToken);
        assertGt(needed, 0, "auction inactive before settlement");
        assertLt(needed, INCUMBENT_DEPOSIT + lateDeposit, "auction proceeds exceed health-check cap");

        airdrop(asset, AUCTION_BUYER, needed);
        vm.prank(AUCTION_BUYER);
        asset.approve(address(auction), needed);
        vm.prank(AUCTION_BUYER);
        uint256 taken = auction.take(rewardToken);
        assertEq(taken, result.auctionedRewards, "auction did not settle full pre-entry lot");
        assertEq(asset.balanceOf(address(strategy)), needed, "auction did not route USDS to strategy");

        // Until the second report, even received USDS is hidden by report-boundary accounting.
        assertEq(
            strategy.totalAssets(),
            INCUMBENT_DEPOSIT + lateDeposit,
            "auction proceeds entered totalAssets before report"
        );

        vm.prank(keeper);
        (result.reportedProfit, firstLoss) = strategy.report();
        assertEq(result.reportedProfit, needed, "second report did not recognize auction proceeds");
        assertEq(firstLoss, 0, "second report loss");

        result.immediateLateValue = strategy.previewRedeem(strategy.balanceOf(LATE_DEPOSITOR));

        // Once Yearn's locked-profit shares finish unlocking, Bob can extract his
        // post-deposit share of the reward value that accrued before he entered.
        skip(strategy.profitMaxUnlockTime());

        uint256 lateShares = strategy.balanceOf(LATE_DEPOSITOR);
        vm.prank(LATE_DEPOSITOR);
        result.lateRedemption = strategy.redeem(lateShares, LATE_DEPOSITOR, LATE_DEPOSITOR);

        uint256 incumbentShares = strategy.balanceOf(user);
        vm.prank(user);
        result.incumbentRedemption = strategy.redeem(incumbentShares, user, user);
    }
}
