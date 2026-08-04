// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

interface IStrategyInterface is IBaseHealthCheck {
    function balanceOfAsset() external view returns (uint256);

    function balanceOfStake() external view returns (uint256);

    function balanceOfRewards() external view returns (uint256);

    function claimableRewards() external view returns (uint256);

    function referral() external view returns (uint16);

    function STAKING() external view returns (address);

    function REWARDS_TOKEN() external view returns (address);

    function auction() external view returns (address);

    function AUCTION_FACTORY() external view returns (address);

    function minimumAuctionPrice() external view returns (uint256);

    function DEFAULT_MINIMUM_AUCTION_PRICE() external view returns (uint256);

    function DEFAULT_AUCTION_STARTING_PRICE() external view returns (uint256);

    function DEFAULT_AUCTION_STEP_DECAY_RATE() external view returns (uint256);

    function claimRewards() external;

    function kickAuction(address _token) external;

    function minAmountToSell(address _token) external view returns (uint256);

    function allowed(address _depositor) external view returns (bool);

    function setMinAmountToSell(address _token, uint256 _minAmountToSell) external;

    function enableAuctionToken(address _token, uint256 _minAmountToSell) external;

    function setMinimumAuctionPrice(uint256 _minimumAuctionPrice) external;

    function setAuctionStartingPrice(uint256 _startingPrice) external;

    function setAuctionStepDecayRate(uint256 _stepDecayRate) external;

    function setAllowed(address _depositor, bool _allowed) external;

    function setReferral(uint16 _referral) external;
}
