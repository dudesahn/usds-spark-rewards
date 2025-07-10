// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "src/test/utils/Setup.sol";

contract OperationTest is Setup {
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
        // TODO: add additional check on strat params
    }

    // test a fixed deposit amount so we can see our logs, using both UniV3 and auctions for rewards
    function test_operation_fixed() public {
        uint256 _amount = 1_000_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        uint256 claimable = strategy.claimableRewards();
        assertGt(claimable, 0, "!rewards");
        console2.log("Claimable SPK:", claimable / 1e18, "* 1e18");

        // can't kick auction if useAuction is false
        vm.prank(management);
        vm.expectRevert("!useAuction");
        strategy.kickAuction(address(asset));

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log("Profit from UniV3 report:", profit / 1e18, "* 1e18 USDS");
        uint256 roughApr = (((profit * 365) /
            (strategy.profitMaxUnlockTime() / 86400)) * 10_000) / _amount;
        console2.log("Rough APR from UniV3 report:", roughApr, "BPS");
        console2.log(
            "Days to unlock profit:",
            strategy.profitMaxUnlockTime() / 86400
        );

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // switch to using the auction
        vm.startPrank(management);
        vm.expectRevert("!auction");
        strategy.setUseAuction(true);
        strategy.setAuction(address(auction));
        strategy.setUseAuction(true);
        vm.stopPrank();

        // simulate our auction process
        uint256 simulatedProfit = _amount / 200; // 0.5% profit
        simulateAuction(simulatedProfit);

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log(
            "Profit from auction report:",
            profitTwo / 1e18,
            "* 1e18 USDS"
        );
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
        // also do other setters (uniV3 fees, referral)
        strategy.setUniV3Fees(100);
        strategy.setReferral(6969);
        vm.stopPrank();

        // airdrop some USDS to the strategy to test our revert
        airdrop(asset, address(strategy), 100e18);
        vm.prank(management);
        vm.expectRevert("!asset");
        strategy.kickAuction(address(asset));

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        assertGt(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_operation_auction_extra() public {
        uint256 _amount = 1_000_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        uint256 claimable = strategy.claimableRewards();
        assertGt(claimable, 0, "!rewards");
        console2.log("Claimable SPK:", claimable / 1e18, "* 1e18");

        // switch to using the auction
        vm.startPrank(management);
        strategy.setAuction(address(auction));
        strategy.setUseAuction(true);
        vm.stopPrank();

        // Report profit, should come through our auction
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from auction report:",
            profit / 1e18,
            "* 1e18 USDS"
        );
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // even though we don't get profit, we should have rewards in the auction contract
        uint256 rewardBalance = ERC20(strategy.REWARDS_TOKEN()).balanceOf(
            address(auction)
        );
        assertGt(rewardBalance, 0, "!auction");

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // check some of our views
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.balanceOfAsset(), 0, "!asset");
        assertEq(strategy.balanceOfStake(), _amount, "!stake");
        assertEq(strategy.claimableRewards(), 0, "!rewards");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // make sure we have some claimable profit
        assertGt(strategy.claimableRewards(), 0, "!rewards");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        if (_amount < PROFIT_FUZZ_MIN) {
            assertGe(profit, 0, "!profit");
        } else {
            assertGt(profit, 0, "!profit");
        }
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        if (_amount < PROFIT_FUZZ_MIN) {
            assertGe(
                asset.balanceOf(user),
                balanceBefore + _amount,
                "!final balance"
            );
        } else {
            assertGt(
                asset.balanceOf(user),
                balanceBefore + _amount,
                "!final balance"
            );
        }
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
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

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
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

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}
