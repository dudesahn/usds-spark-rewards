// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SparkCompounder} from "src/SparkCompounder.sol";
import {GroveCompounder} from "src/GroveCompounder.sol";
import {ISparkCompounder} from "src/interfaces/ISparkCompounder.sol";
import {IGroveCompounder} from "src/interfaces/IGroveCompounder.sol";

contract CompounderCoexistenceTest is Test {
    function test_bothStrategiesKeepIndependentPositions() public {
        address management = address(1);
        address user = address(10);
        vm.startPrank(management);
        ISparkCompounder spark = ISparkCompounder(address(new SparkCompounder()));
        IGroveCompounder grove = IGroveCompounder(address(new GroveCompounder()));
        spark.setOpenDeposits(true);
        grove.setOpen(true);
        vm.stopPrank();

        assertEq(spark.apiVersion(), "3.0.4");
        assertEq(grove.apiVersion(), "3.1.0");
        assertEq(spark.asset(), grove.asset());
        assertTrue(spark.STAKING() != grove.STAKING());
        assertTrue(spark.REWARDS_TOKEN() != grove.REWARDS_TOKEN());

        ERC20 asset = ERC20(spark.asset());
        uint256 amount = 1_000e18;
        deal(address(asset), user, 2 * amount);
        vm.startPrank(user);
        asset.approve(address(spark), amount);
        asset.approve(address(grove), amount);
        spark.deposit(amount, user);
        grove.deposit(amount, user);
        assertEq(spark.balanceOfStake(), amount);
        assertEq(grove.balanceOfStake(), amount);

        spark.redeem(spark.balanceOf(user), user, user);
        assertEq(spark.balanceOfStake(), 0);
        assertEq(grove.balanceOfStake(), amount);
        grove.redeem(grove.balanceOf(user), user, user);
        vm.stopPrank();
        assertEq(grove.balanceOfStake(), 0);
        assertEq(asset.balanceOf(user), 2 * amount);
    }
}
