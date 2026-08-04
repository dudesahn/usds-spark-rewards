pragma solidity ^0.8.18;

import {Setup, ERC20} from "src/test/utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_emergencyWithdraw_maxUint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_shutdownCanRealizePendingRewardsThroughAuction() public {
        uint256 amount = 10_000e18;
        address rewardsToken = strategy.REWARDS_TOKEN();
        address buyer = address(0xB0B);

        // Use a small total lot price for this synthetic take so the profit stays inside health check bounds.
        vm.prank(management);
        strategy.setAuctionStartingPrice(50e18);

        mintAndDepositIntoStrategy(strategy, user, amount);
        skip(1 days);
        assertGt(strategy.claimableRewards(), 0, "!claimable");

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        assertTrue(strategy.isShutdown());
        assertEq(strategy.balanceOfStake(), 0, "!stake");
        assertEq(strategy.balanceOfAsset(), amount, "!idle");

        // A post-shutdown report can still claim pending GROVE and kick its auction.
        vm.prank(keeper);
        strategy.report();

        uint256 rewardsAvailable = auction.available(rewardsToken);
        uint256 paymentNeeded = auction.getAmountNeeded(rewardsToken);
        assertGt(rewardsAvailable, 0, "!auction");
        assertGt(paymentNeeded, 0, "!payment");
        assertEq(strategy.balanceOfStake(), 0, "!restaked");

        airdrop(asset, buyer, paymentNeeded);
        vm.startPrank(buyer);
        asset.approve(address(auction), paymentNeeded);
        assertEq(auction.take(rewardsToken), rewardsAvailable);
        vm.stopPrank();

        assertEq(ERC20(rewardsToken).balanceOf(buyer), rewardsAvailable, "!rewards");
        assertEq(strategy.balanceOfAsset(), amount + paymentNeeded, "!proceeds");

        // A final report recognizes the proceeds but leaves all USDS idle while shutdown.
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, paymentNeeded, "!profit");
        assertEq(loss, 0, "!loss");
        assertEq(strategy.balanceOfStake(), 0, "!restaked");
        assertEq(strategy.totalAssets(), amount + paymentNeeded, "!totalAssets");
    }

    function test_shutdownCannotDepositToRecoverLateAuctionProceeds() public {
        uint256 amount = 10_000e18;
        address rewardsToken = strategy.REWARDS_TOKEN();
        address buyer = address(0xB0B);

        mintAndDepositIntoStrategy(strategy, user, amount);
        skip(1 days);

        vm.prank(keeper);
        strategy.report();

        uint256 rewardsAvailable = auction.available(rewardsToken);
        uint256 paymentNeeded = auction.getAmountNeeded(rewardsToken);
        assertGt(rewardsAvailable, 0, "!auction");
        assertGt(paymentNeeded, 0, "!payment");

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // The final shareholder can redeem before the outstanding auction settles.
        uint256 userShares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(userShares, user, user);
        assertEq(strategy.totalSupply(), 0, "!supply");

        // Auction proceeds arriving afterward have no external shareholder.
        airdrop(asset, buyer, paymentNeeded);
        vm.startPrank(buyer);
        asset.approve(address(auction), paymentNeeded);
        assertEq(auction.take(rewardsToken), rewardsAvailable);
        vm.stopPrank();

        assertEq(strategy.balanceOfAsset(), paymentNeeded, "!late proceeds");
        assertEq(strategy.maxDeposit(user), 0, "!max deposit");

        // Shutdown is permanent, so depositing to mint replacement shares is impossible.
        vm.startPrank(user);
        asset.approve(address(strategy), 1e18);
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(1e18, user);
        vm.stopPrank();

        assertEq(strategy.totalSupply(), 0, "!final supply");
        assertEq(strategy.balanceOfAsset(), paymentNeeded, "!stranded proceeds");
    }

    // TODO: Add tests for any emergency function added.
}
