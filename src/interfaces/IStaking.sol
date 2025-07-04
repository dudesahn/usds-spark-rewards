// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface IStaking {
    function stakingToken() external view returns (address);

    function rewardsToken() external view returns (address);

    function paused() external view returns (bool);

    function balanceOf(address) external view returns (uint256);

    function earned(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function stake(uint256 _amount, uint16 _referral) external;

    function withdraw(uint256 _amount) external;

    function getReward() external;
}
