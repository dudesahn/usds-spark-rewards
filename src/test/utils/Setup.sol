// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {SparkCompounder, ERC20, Auction, IStaking} from "src/SparkCompounder.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";
import {AuctionFactory} from "@periphery/Auctions/AuctionFactory.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is Test, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    // auction to be used by our strategy
    Auction public auction;
    AuctionFactory public auctionFactory =
        AuctionFactory(0xCfA510188884F199fcC6e750764FAAbE6e56ec40);

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    // Address of the staking contract
    address public staking;

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    // use this as a cutoff to expect when deposits/withdrawals won't cause detectable APR differences
    uint256 public constant ORACLE_FUZZ_MIN = 1e15;

    // use this as a cutoff to expect when we won't generate meaningful profit
    uint256 public constant PROFIT_FUZZ_MIN = 10_000e18;

    // set profit max unlock time for 1 days since rewards are paid weekly
    uint256 public profitMaxUnlockTime = 1 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["USDS"]);

        // Set decimals
        decimals = asset.decimals();
        staking = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        // setup our auction with our rewards token to sell
        setUpAuction(strategy.REWARDS_TOKEN());

        // set min amount to sell super low for testing ~($1.50)
        vm.prank(management);
        strategy.setMinAmountToSell(50e18);

        factory = strategy.FACTORY();

        // manually top-up rewards so we don't run into EOW with no rewards
        uint256 timeLeft = IStaking(staking).periodFinish() - block.timestamp;
        uint256 week = 86400 * 7;
        uint256 toSend = IStaking(staking).rewardRate() * (week - timeLeft); // use current rewardRate, scaled by week time elapsed
        deal(strategy.REWARDS_TOKEN(), staking, toSend * 2); // send double than we're notifying to avoid edge reverts
        vm.prank(IStaking(staking).rewardsDistribution());
        IStaking(staking).notifyRewardAmount(toSend);

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        vm.startPrank(management);
        IStrategyInterface _strategy = IStrategyInterface(
            address(new SparkCompounder())
        );

        // setup the strategy
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _strategy.setKeeper(keeper);
        _strategy.setEmergencyAdmin(emergencyAdmin);
        _strategy.setProfitMaxUnlockTime(profitMaxUnlockTime);

        // check that deposits are closed
        assertEq(_strategy.availableDepositLimit(user), 0, "!deposit");
        _strategy.setAllowed(user, true);
        assertGt(_strategy.availableDepositLimit(user), 0, "!deposit");
        _strategy.setAllowed(user, false);
        vm.stopPrank();

        // prank owner of staking contract to make sure deposit limit is zero when paused
        vm.startPrank(0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB);
        IStaking(_strategy.STAKING()).setPaused(true);
        assertEq(_strategy.availableDepositLimit(user), 0, "!deposit");
        IStaking(_strategy.STAKING()).setPaused(false);
        vm.stopPrank();

        // turn on open deposits
        vm.prank(management);
        _strategy.setOpenDeposits(true);

        return address(_strategy);
    }

    function setUpAuction(address _token) public {
        // deploy auction for the strategy
        auction = Auction(
            auctionFactory.createNewAuction(
                address(asset),
                address(strategy),
                management
            )
        );

        // enable reward token on our auction
        vm.prank(management);
        auction.enable(_token);
    }

    function simulateAuction(uint256 _profitAmount) public {
        // cache our rewards token
        address rewardsToken = strategy.REWARDS_TOKEN();

        // kick the auction
        vm.prank(keeper);
        strategy.kickAuction(rewardsToken);

        // check for reward token balance in auction
        uint256 rewardBalance = ERC20(rewardsToken).balanceOf(address(auction));
        uint256 strategyBalance = ERC20(rewardsToken).balanceOf(
            address(auction)
        );
        console2.log(
            "Reward token sitting in our strategy",
            strategyBalance / 1e18,
            "* 1e18"
        );

        // if we have reward tokens, sweep it out, and send back our designated profitAmount
        if (rewardBalance > 0) {
            console2.log(
                "Reward token sitting in our auction",
                rewardBalance / 1e18,
                "* 1e18"
            );

            vm.prank(address(auction));
            ERC20(rewardsToken).transfer(user, rewardBalance);
            airdrop(asset, address(strategy), _profitAmount);
            rewardBalance = ERC20(rewardsToken).balanceOf(address(auction));
        }

        // confirm that we swept everything out
        assertEq(rewardBalance, 0, "!rewardBalance");
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddrs["USDS"] = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    }
}
