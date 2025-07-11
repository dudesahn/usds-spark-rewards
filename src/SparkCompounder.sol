// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {IPsmWrapper} from "src/interfaces/IPsmWrapper.sol";

contract SparkCompounder is UniswapV3Swapper, BaseHealthCheck {
    using SafeERC20 for ERC20;

    /// @notice yearn's referral code
    uint16 public referral = 1007;

    /// @notice Address of the specific Auction this strategy uses.
    address public auction;

    /// @notice True if we should use auctions, if false use UniV3
    bool public useAuction;

    /// @notice True if strategy deposits are open to any address
    bool public openDeposits;

    /// @notice Mapping of addresses and whether they are allowed to deposit to this strategy
    mapping(address => bool) public allowed;

    /// @notice Reward token we get for staking
    address public immutable REWARDS_TOKEN;

    /// @notice Staking contract we use
    IStaking public constant STAKING =
        IStaking(0x173e314C7635B45322cd8Cb14f44b312e079F3af);

    /// @notice Wrapper for PSM with USDS
    IPsmWrapper internal constant PSM_WRAPPER =
        IPsmWrapper(0xA188EEC8F81263234dA3622A406892F3D630f98c);

    /// @notice Don't bother spending the gas to stake dust
    uint256 internal constant DUST = 1e18;

    constructor() BaseHealthCheck(PSM_WRAPPER.usds(), "Spark USDS Compounder") {
        require(!STAKING.paused(), "!paused");
        require(PSM_WRAPPER.usds() == STAKING.stakingToken(), "!stakingToken");
        REWARDS_TOKEN = STAKING.rewardsToken();

        // approve staking contract and our PSM wrapper
        asset.forceApprove(address(STAKING), type(uint256).max);

        // use USDC for our UniV3 swaps and then send it through the PSM for USDS
        address usdc = PSM_WRAPPER.gem();
        ERC20(usdc).forceApprove(address(PSM_WRAPPER), type(uint).max); //approve the PSM

        // Set the min amount for the swapper/auction to sell
        base = usdc; // use USDC as base in UniV3
        minAmountToSell = 5_000e18; // SPK is ~$0.03
        _setUniFees(REWARDS_TOKEN, usdc, 100); // SPK-USDC pool is 0.01%. uniV3 fees in 1/100 of bps
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

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // get our rewards. if no rewards is a noop so no worries about reverts
        _claimRewards();

        // store in memory to save gas
        uint256 toSwap = balanceOfRewards();

        if (!useAuction) {
            if (toSwap > minAmountToSell) {
                // swap if using UniV3 to sell rewards
                _swapFrom(REWARDS_TOKEN, base, toSwap, 0);
                // use PSM to go from USDC to USDS for free, assuming psm.tin() stays zero
                PSM_WRAPPER.sellGem(
                    address(this),
                    ERC20(base).balanceOf(address(this))
                );
            }
        } else if (toSwap > minAmountToSell) {
            _kickAuction(REWARDS_TOKEN, toSwap);
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

    function availableDepositLimit(
        address _receiver
    ) public view override returns (uint256) {
        if (STAKING.paused()) {
            return 0;
        } else if (openDeposits || allowed[_receiver]) {
            return type(uint256).max;
        } else {
            return 0;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /* ========== REWARD & AUCTION FUNCTIONS ========== */

    /**
     * @notice Manually claim rewards from staking contract.
     * @dev Can only be called by management.
     */
    function claimRewards() external onlyManagement {
        _claimRewards();
    }

    function _claimRewards() internal {
        STAKING.getReward();
    }

    /**
     * @notice Kick an auction to sell rewards to more asset.
     * @dev Can only be called by keepers. useAuction must be set to true. Can't kick asset.
     * @param _token Token to kick the auction for.
     */
    function kickAuction(address _token) external onlyKeepers {
        require(useAuction, "!useAuction");
        uint256 rewardsBalance;

        if (_token == REWARDS_TOKEN) {
            _claimRewards();
            rewardsBalance = balanceOfRewards();
        } else {
            rewardsBalance = ERC20(_token).balanceOf(address(this));
        }

        if (rewardsBalance > minAmountToSell) {
            _kickAuction(_token, rewardsBalance);
        }
    }

    function _kickAuction(address _token, uint256 _balance) internal {
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(auction, _balance);
        Auction(auction).kick(_token);
    }

    /* ========== PERMISSIONED SETTER FUNCTIONS ========== */

    /**
     * @notice Set the minimum amount of rewardsToken to sell.
     * @dev Can only be called by management.
     * @param _minAmountToSell minimum amount to sell in wei.
     */
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /**
     * @notice Set fees for UniswapV3 to sell rewardsToken.
     * @dev Can only be called by management.
     * @param _rewardToBase fee reward to base (spk/usdc)
     */
    function setUniV3Fees(uint24 _rewardToBase) external onlyManagement {
        _setUniFees(REWARDS_TOKEN, base, _rewardToBase);
    }

    /**
     * @notice Set address for our auction contract.
     * @dev Can only be called by management.
     * @param _auction Address of the auction to use.
     */
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(Auction(_auction).receiver() == address(this), "receiver");
            require(Auction(_auction).want() == address(asset), "want");
        }
        auction = _auction;
    }

    /**
     * @notice Set whether to use auction or UniV3 for rewards selling.
     * @dev Can only be called by management.
     * @param _useAuction Use auction to sell rewards (true) or UniV3 (false).
     */
    function setUseAuction(bool _useAuction) external onlyManagement {
        if (_useAuction) require(auction != address(0), "!auction");
        useAuction = _useAuction;
    }

    /**
     * @notice Set the referral code for staking.
     * @dev Can only be called by management.
     * @param _referral Referral code for deposits in the staking contract.
     */
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }

    /**
     * @notice Set whether deposits are open to anyone or restricted to our allowed mapping.
     * @dev Can only be called by management.
     * @param _openDeposits Allow deposits from anyone (true) or use mapping (false).
     */
    function setOpenDeposits(bool _openDeposits) external onlyManagement {
        openDeposits = _openDeposits;
    }

    /**
     * @notice Set whether an address can deposit to the strategy or not.
     * @dev Can only be called by management.
     * @param _depositor Address to set mapping for.
     * @param _allowed Whether the address is allowed to deposit to the strategy.
     */
    function setAllowed(
        address _depositor,
        bool _allowed
    ) external onlyManagement {
        allowed[_depositor] = _allowed;
    }
}
