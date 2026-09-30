// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {AuctionFactory} from "@periphery/Auctions/AuctionFactory.sol";
import {GroveSetup, ERC20} from "src/test/grove/utils/Setup.sol";

contract GroveOperationTest is GroveSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.referral(), 2009);
        assertEq(strategy.DEFAULT_MINIMUM_AUCTION_PRICE(), DEFAULT_MINIMUM_AUCTION_PRICE);
        assertEq(strategy.DEFAULT_AUCTION_STARTING_PRICE(), 10_000e18);
        assertEq(strategy.DEFAULT_AUCTION_STEP_DECAY_RATE(), 30);
        assertEq(strategy.minimumAuctionPrice(), DEFAULT_MINIMUM_AUCTION_PRICE);
        AuctionFactory auctionFactory = AuctionFactory(strategy.AUCTION_FACTORY());
        assertEq(address(auctionFactory), 0x55B3830B4D85e6868c73f00A2e857e9AdbF89568);
        assertEq(auctionFactory.auctions(auctionFactory.numberOfAuctions() - 1), address(auction));
        assertEq(auction.receiver(), address(strategy));
        assertEq(auction.want(), address(asset));
        assertEq(auction.governance(), address(strategy));
        assertTrue(auction.governanceOnlyKick());
        assertEq(auction.minimumPrice(), DEFAULT_MINIMUM_AUCTION_PRICE);
        assertEq(auction.startingPrice(), strategy.DEFAULT_AUCTION_STARTING_PRICE());
        assertEq(auction.stepDecayRate(), strategy.DEFAULT_AUCTION_STEP_DECAY_RATE());
        // TODO: add additional check on strat params
    }

    function test_rewardSaleUsesConfiguredAuction() public {
        assertTrue(address(auction) != address(0));
        assertEq(strategy.auction(), address(auction));
    }

    function test_customFunctionPermissions() public {
        address rewardsToken = strategy.REWARDS_TOKEN();

        vm.startPrank(user);
        vm.expectRevert("!keeper");
        strategy.claimRewards();
        vm.expectRevert("!keeper");
        strategy.kickAuction(rewardsToken);
        vm.expectRevert("!management");
        strategy.setMinAmountToSell(rewardsToken, 1);
        vm.expectRevert("!management");
        strategy.enableAuctionToken(USDC, 1);
        vm.expectRevert("!management");
        strategy.setMinimumAuctionPrice(DEFAULT_MINIMUM_AUCTION_PRICE);
        vm.expectRevert("!management");
        strategy.setAuctionStartingPrice(1_000e18);
        vm.expectRevert("!management");
        strategy.setAuctionStepDecayRate(30);
        vm.expectRevert("!management");
        strategy.setReferral(1);
        vm.stopPrank();
    }

    function test_keeperCanClaimRewards() public {
        mintAndDepositIntoStrategy(strategy, user, 10_000e18);
        skip(1 days);
        assertGt(strategy.claimableRewards(), 0, "!claimable");

        vm.prank(keeper);
        strategy.claimRewards();

        assertEq(strategy.claimableRewards(), 0, "!claimed");
        assertGt(strategy.balanceOfRewards(), 0, "!rewards");
    }

    function test_setMinimumAuctionPriceUpdatesAuction() public {
        uint256 newMinimumAuctionPrice = 7e15;
        vm.prank(management);
        strategy.setMinimumAuctionPrice(newMinimumAuctionPrice);

        assertEq(strategy.minimumAuctionPrice(), newMinimumAuctionPrice);
        assertEq(auction.minimumPrice(), newMinimumAuctionPrice);
    }

    function test_setAuctionPricingUpdatesAuction() public {
        uint256 newStartingPrice = 500_000e18;
        uint256 newStepDecayRate = 25;

        vm.startPrank(management);
        strategy.setAuctionStartingPrice(newStartingPrice);
        strategy.setAuctionStepDecayRate(newStepDecayRate);
        vm.stopPrank();

        assertEq(auction.startingPrice(), newStartingPrice);
        assertEq(auction.stepDecayRate(), newStepDecayRate);
    }

    function test_directAuctionKickRequiresGovernance() public {
        address rewardsToken = strategy.REWARDS_TOKEN();
        airdrop(ERC20(rewardsToken), address(auction), 1);

        vm.expectRevert("!governance");
        auction.kick(rewardsToken);
    }

    function test_canAuctionDonatedToken() public {
        uint256 usdcAmount = 1_000e6;
        ERC20 usdc = ERC20(USDC);

        vm.prank(management);
        strategy.enableAuctionToken(USDC, 100e6);

        airdrop(usdc, address(strategy), usdcAmount);

        vm.prank(keeper);
        strategy.kickAuction(USDC);

        assertEq(usdc.balanceOf(address(strategy)), 0, "!strategy");
        assertEq(usdc.balanceOf(address(auction)), usdcAmount, "!auction");
        assertEq(auction.available(USDC), usdcAmount, "!available");
        assertTrue(auction.isActive(USDC));
    }

    function test_reportSkipsKickWhenAuctionIsActive() public {
        uint256 _amount = 10_000e18;
        address rewardsToken = strategy.REWARDS_TOKEN();

        mintAndDepositIntoStrategy(strategy, user, _amount);
        skip(strategy.profitMaxUnlockTime());

        vm.prank(keeper);
        strategy.report();

        uint256 auctionBalance = ERC20(rewardsToken).balanceOf(address(auction));
        assertGt(auctionBalance, 0, "!auction");

        vm.prank(management);
        strategy.setMinAmountToSell(rewardsToken, 1);

        skip(10);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");
        assertEq(ERC20(rewardsToken).balanceOf(address(auction)), auctionBalance);
        assertGt(strategy.balanceOfRewards(), strategy.minAmountToSell(rewardsToken), "!rewards");
    }

    function test_auctionTakeTransfersPaymentAndRewards() public {
        uint256 depositAmount = 10_000e18;
        address rewardsToken = strategy.REWARDS_TOKEN();
        address buyer = address(0xB0B);

        mintAndDepositIntoStrategy(strategy, user, depositAmount);
        skip(strategy.profitMaxUnlockTime());

        vm.prank(keeper);
        strategy.report();

        uint256 rewardsAvailable = auction.available(rewardsToken);
        uint256 paymentNeeded = auction.getAmountNeeded(rewardsToken);
        uint256 strategyAssetsBefore = asset.balanceOf(address(strategy));

        assertGt(rewardsAvailable, 0);
        assertGt(paymentNeeded, 0);

        airdrop(asset, buyer, paymentNeeded);
        vm.startPrank(buyer);
        asset.approve(address(auction), paymentNeeded);
        uint256 rewardsTaken = auction.take(rewardsToken);
        vm.stopPrank();

        assertEq(rewardsTaken, rewardsAvailable);
        assertEq(ERC20(rewardsToken).balanceOf(buyer), rewardsAvailable);
        assertEq(asset.balanceOf(address(strategy)), strategyAssetsBefore + paymentNeeded);
        assertEq(asset.balanceOf(buyer), 0);
        assertEq(auction.available(rewardsToken), 0);
        assertFalse(auction.isActive(rewardsToken));
    }

    function test_setMinimumAuctionPriceRevertsWhenAuctionIsActive() public {
        mintAndDepositIntoStrategy(strategy, user, 10_000e18);
        skip(strategy.profitMaxUnlockTime());

        vm.prank(keeper);
        strategy.report();

        vm.prank(management);
        vm.expectRevert("active auction");
        strategy.setMinimumAuctionPrice(DEFAULT_MINIMUM_AUCTION_PRICE + 1);
    }

    // test a fixed deposit amount so we can see our logs through the active reward sale mode
    function test_operation_fixed() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        uint256 claimable = strategy.claimableRewards();
        assertGt(claimable, 0, "!rewards");
        console2.log("Claimable rewards:", claimable / 1e18, "* 1e18");

        // Report rewards into the auction.
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log("Profit from auction report:", profit / 1e18, "* 1e18 USDS");
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 rewardBalance = ERC20(strategy.REWARDS_TOKEN()).balanceOf(address(auction));
        assertGt(rewardBalance, 0, "!auction");

        // simulate our auction process
        uint256 simulatedProfit = _amount / 200; // 0.5% profit
        simulateAuction(simulatedProfit);

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log("Profit from auction report:", profitTwo / 1e18, "* 1e18 USDS");
        assertGt(profitTwo, 0, "!profit");
        assertEq(lossTwo, 0, "!loss");

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // manually claim some rewards
        vm.startPrank(management);
        assertEq(strategy.balanceOfRewards(), 0, "!rewards");
        strategy.claimRewards();
        assertGt(strategy.balanceOfRewards(), 0, "!rewards");
        // also test management setter
        strategy.setReferral(6969);
        vm.stopPrank();

        // airdrop some USDS to the strategy to test our reward-only guard
        airdrop(asset, address(strategy), 100e18);
        vm.prank(keeper);
        vm.expectRevert("!asset");
        strategy.kickAuction(address(asset));

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        assertGt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_operation_auction_extra() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        uint256 claimable = strategy.claimableRewards();
        assertGt(claimable, 0, "!rewards");
        console2.log("Claimable rewards:", claimable / 1e18, "* 1e18");

        // Report profit, should come through our auction
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log("Profit from auction report:", profit / 1e18, "* 1e18 USDS");
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // even though we don't get profit, we should have rewards in the auction contract
        uint256 rewardBalance = ERC20(strategy.REWARDS_TOKEN()).balanceOf(address(auction));
        assertGt(rewardBalance, 0, "!auction");

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_operation() public {
        uint256 amount = 10_000e18;
        address rewardsToken = strategy.REWARDS_TOKEN();
        address buyer = address(0xB0B);

        // Keep the lifecycle accounting exact; fee behavior is covered separately.
        vm.prank(management);
        strategy.setPerformanceFee(0);

        // Use a small total lot price for this synthetic take so the profit stays inside health check bounds.
        vm.prank(management);
        strategy.setAuctionStartingPrice(50e18);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, amount);

        // check some of our views
        assertEq(strategy.totalAssets(), amount, "!totalAssets");
        assertEq(strategy.balanceOfAsset(), 0, "!asset");
        assertEq(strategy.balanceOfStake(), amount, "!stake");
        assertEq(strategy.claimableRewards(), 0, "!rewards");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // make sure we have some claimable profit
        assertGt(strategy.claimableRewards(), 0, "!rewards");

        // The first report claims GROVE and starts an auction, but realizes no USDS profit.
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 rewardsAvailable = auction.available(rewardsToken);
        uint256 paymentNeeded = auction.getAmountNeeded(rewardsToken);
        assertGt(rewardsAvailable, 0, "!auction");
        assertGt(paymentNeeded, 0, "!payment");

        // A real auction take transfers GROVE to the buyer and USDS to the strategy.
        airdrop(asset, buyer, paymentNeeded);
        vm.startPrank(buyer);
        asset.approve(address(auction), paymentNeeded);
        assertEq(auction.take(rewardsToken), rewardsAvailable);
        vm.stopPrank();

        assertEq(ERC20(rewardsToken).balanceOf(buyer), rewardsAvailable, "!rewards out");
        assertEq(strategy.balanceOfAsset(), paymentNeeded, "!payment in");
        assertFalse(auction.isActive(rewardsToken), "!settled");

        // The second report recognizes the payment as profit and reinvests it.
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertEq(profit, paymentNeeded, "!realized profit");
        assertEq(loss, 0, "!realized loss");
        assertEq(strategy.balanceOfAsset(), 0, "!idle");
        assertEq(strategy.balanceOfStake(), amount + paymentNeeded, "!reinvested");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);
        uint256 userShares = strategy.balanceOf(user);

        // Once profit unlocks, the original shareholder receives principal and auction proceeds.
        vm.prank(user);
        strategy.redeem(userShares, user, user);

        assertEq(asset.balanceOf(user), balanceBefore + amount + paymentNeeded, "!final balance");
        assertEq(strategy.totalAssets(), 0, "!final assets");
    }

    function test_profitableReport(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_000));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_profitableReport_withFees(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_000));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient);

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(performanceFeeRecipient), expectedShares, "!perf fee out");
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}
