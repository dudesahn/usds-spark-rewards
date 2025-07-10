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

    function claimRewards() external;

    function kickAuction(address _token) external;

    function minAmountToSell() external view returns (uint256);

    function openDeposits() external view returns (bool);

    function allowed(address _depositor) external view returns (bool);

    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setUniV3Fees(uint24 _rewardToBase) external;

    function setOpenDeposits(bool _openDeposits) external;

    function setAllowed(address _depositor, bool _allowed) external;

    function setReferral(uint16 _referral) external;

    function setAuction(address _auction) external;

    function setUseAuction(bool _useAuction) external;
}
