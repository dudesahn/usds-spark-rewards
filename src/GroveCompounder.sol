// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenizedStrategyLib as TokenizedStrategy} from "@tokenized-strategy/libraries/TokenizedStrategyLib.sol";
import {BaseSwapper} from "@periphery/swappers/BaseSwapper.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {AuctionFactory} from "@periphery/Auctions/AuctionFactory.sol";
import {IStaking} from "src/interfaces/IStaking.sol";

contract GroveCompounder is BaseSwapper, BaseHealthCheck {
    using SafeERC20 for ERC20;

    /// @notice yearn's referral code
    uint16 public referral = 2009;

    /// @notice Address of the specific Auction this strategy uses.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable auction;

    /// @notice Yearn AuctionFactory used so taker bots can discover the auction.
    AuctionFactory public constant AUCTION_FACTORY = AuctionFactory(0x55B3830B4D85e6868c73f00A2e857e9AdbF89568);

    /// @notice Default minimum GROVE auction price in USDS terms, scaled to 1e18.
    uint256 public constant DEFAULT_MINIMUM_AUCTION_PRICE = 6e15;

    /// @notice Default auction starting price, scaled to 1e18.
    uint256 public constant DEFAULT_AUCTION_STARTING_PRICE = 10_000e18;

    /// @notice Default auction step decay rate in basis points.
    uint256 public constant DEFAULT_AUCTION_STEP_DECAY_RATE = 30;

    /// @notice Required Auction.minimumPrice() before this strategy will kick GROVE.
    uint256 public minimumAuctionPrice = DEFAULT_MINIMUM_AUCTION_PRICE;

    /// @notice Reward token we get for staking
    address public immutable REWARDS_TOKEN;

    /// @notice Staking contract we use
    IStaking public constant STAKING = IStaking(0x4E41488C19cD35EB4de3083Fc3e204854c75c86a);

    /// @notice Don't bother spending the gas to stake dust
    uint256 internal constant DUST = 1e18;

    constructor() BaseHealthCheck(STAKING.stakingToken(), "Grove USDS Compounder") {
        require(!STAKING.paused(), "!paused");
        REWARDS_TOKEN = STAKING.rewardsToken();

        // approve staking contract
        asset.forceApprove(address(STAKING), type(uint256).max);

        // Set the min amount for the auction to sell
        _setMinAmountToSell(REWARDS_TOKEN, 10_000e18);

        Auction _auction = Auction(
            AUCTION_FACTORY.createNewAuction(
                address(asset), address(this), address(this), DEFAULT_AUCTION_STARTING_PRICE
            )
        );
        _auction.enable(REWARDS_TOKEN);
        _auction.setMinimumPrice(DEFAULT_MINIMUM_AUCTION_PRICE);
        _auction.setStepDecayRate(DEFAULT_AUCTION_STEP_DECAY_RATE);
        _auction.setGovernanceOnlyKick(true);
        auction = address(_auction);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        return STAKING.balanceOf(address(this));
    }

    function balanceOfRewards() public view returns (uint256) {
        return ERC20(REWARDS_TOKEN).balanceOf(address(this));
    }

    function claimableRewards() external view returns (uint256) {
        return STAKING.earned(address(this));
    }

    /* ========== CORE STRATEGY FUNCTIONS ========== */

    function _deployFunds(uint256 _amount) internal override {
        STAKING.stake(_amount, referral);
    }

    function _freeFunds(uint256 _amount) internal override {
        STAKING.withdraw(_amount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // get our rewards. if no rewards is a noop so no worries about reverts
        _claimRewards();

        // store in memory to save gas
        uint256 rewardsBalance = balanceOfRewards();

        if (rewardsBalance > minAmountToSell[REWARDS_TOKEN]) {
            _kickAuction(REWARDS_TOKEN, rewardsBalance);
        }

        uint256 balance = balanceOfAsset();
        if (!TokenizedStrategy.isShutdown()) {
            if (balance > DUST) {
                _deployFunds(balance);
            }
        }
        _totalAssets = balanceOfStake() + balanceOfAsset();
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = _min(_amount, balanceOfStake());
        _freeFunds(_amount);
    }

    function availableDepositLimit(address _receiver) public view override returns (uint256) {
        if (STAKING.paused()) {
            return 0;
        }

        return super.availableDepositLimit(_receiver);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /* ========== REWARD & AUCTION FUNCTIONS ========== */

    /**
     * @notice Manually claim rewards from staking contract.
     * @dev Can only be called by management.
     */
    function claimRewards() external onlyKeepers {
        _claimRewards();
    }

    function _claimRewards() internal {
        STAKING.getReward();
    }

    /**
     * @notice Kick an auction to sell tokens to more asset.
     * @dev Can only be called by keepers. Claims rewards before kicking the reward token.
     * @param _token Token to kick the auction for.
     */
    function kickAuction(address _token) external onlyKeepers {
        uint256 tokenBalance;
        if (_token == REWARDS_TOKEN) {
            _claimRewards();
            tokenBalance = balanceOfRewards();
        } else {
            tokenBalance = ERC20(_token).balanceOf(address(this));
        }

        if (tokenBalance > minAmountToSell[_token]) {
            _kickAuction(_token, tokenBalance);
        }
    }

    function _kickAuction(address _token, uint256 _balance) internal {
        require(_token != address(asset), "!asset");
        Auction auctionContract = Auction(auction);

        if (auctionContract.isActive(_token)) {
            if (auctionContract.available(_token) > 0) return;
            auctionContract.settle(_token);
        }

        ERC20(_token).safeTransfer(auction, _balance);
        auctionContract.kick(_token);
    }

    /* ========== PERMISSIONED SETTER FUNCTIONS ========== */

    /**
     * @notice Set the minimum amount of a token to sell.
     * @dev Can only be called by management.
     * @param _token Token to set the minimum for.
     * @param _minAmountToSell minimum amount to sell in wei.
     */
    function setMinAmountToSell(address _token, uint256 _minAmountToSell) external onlyManagement {
        _setMinAmountToSell(_token, _minAmountToSell);
    }

    /**
     * @notice Enable an auction token and set its minimum amount to sell.
     * @dev Can only be called by management. Useful for selling non-reward tokens
     *      accidentally sent to the strategy.
     * @param _token Token to enable for auctions.
     * @param _minAmountToSell minimum amount to sell in wei.
     */
    function enableAuctionToken(address _token, uint256 _minAmountToSell) external onlyManagement {
        require(_token != address(asset), "!asset");
        Auction(auction).enable(_token);
        _setMinAmountToSell(_token, _minAmountToSell);
    }

    /**
     * @notice Set the minimum GROVE auction price required by the strategy.
     * @dev Can only be called by management. The Auction itself must be configured
     *      with at least this minimum price before rewards can be kicked.
     * @param _minimumAuctionPrice Minimum auction price in USDS terms, scaled to 1e18.
     */
    function setMinimumAuctionPrice(uint256 _minimumAuctionPrice) external onlyManagement {
        Auction(auction).setMinimumPrice(_minimumAuctionPrice);
        minimumAuctionPrice = _minimumAuctionPrice;
    }

    /**
     * @notice Set the auction starting price.
     * @dev Can only be called by management. Reverts while any enabled auction is active.
     * @param _startingPrice New starting price, scaled to 1e18.
     */
    function setAuctionStartingPrice(uint256 _startingPrice) external onlyManagement {
        Auction(auction).setStartingPrice(_startingPrice);
    }

    /**
     * @notice Set the auction step decay rate.
     * @dev Can only be called by management. Reverts while any enabled auction is active.
     * @param _stepDecayRate New step decay rate in basis points.
     */
    function setAuctionStepDecayRate(uint256 _stepDecayRate) external onlyManagement {
        Auction(auction).setStepDecayRate(_stepDecayRate);
    }

    /**
     * @notice Set the referral code for staking.
     * @dev Can only be called by management.
     * @param _referral Referral code for deposits in the staking contract.
     */
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }
}
