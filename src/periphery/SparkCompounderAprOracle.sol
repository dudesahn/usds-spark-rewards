// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IStaking} from "src/interfaces/IStaking.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

contract SparkCompounderAprOracle {
    /// @notice Sky Rewards staking contract
    address public constant STAKING =
        0x173e314C7635B45322cd8Cb14f44b312e079F3af;

    /// @notice SPARK governance token
    /// @dev Reward token for staking
    address public constant SPK = 0xc20059e0317DE91738d13af027DfC4a50781b066;

    /// @notice Token to stake for SPK rewards
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice SPK is paired with USDC in UniV3 pool
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice SPK Redstone oracle address
    address public constant REDSTONE_ORACLE =
        0xF2448DC04B1d3f1767D6f7C03da8a3933bdDD697;

    uint256 internal constant SECONDS_PER_YEAR = 31536000;

    /**
     * @param _strategy The strategy to get the apr for. Not a used variable in this case.
     * @param _delta The difference in debt.
     * @return oracleApr The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256 oracleApr) {
        // pull total staked and reward rate from staking contract
        uint256 assets = IStaking(STAKING).totalSupply();
        uint256 rewardRate = IStaking(STAKING).rewardRate(); // tokens per second

        // get price of 1 SPK from Redstone
        (, int256 answer, , uint256 updatedAt, ) = IOracle(REDSTONE_ORACLE)
            .latestRoundData();

        // make sure the price is no more than 48 hours old
        require(block.timestamp - updatedAt < 172800, "stale price");
        require(answer > 0, "negative price");

        uint256 price = uint256(answer);

        // adjust for ∆ assets
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        // don't divide by 0. if no assets in staking contract, yield would be very good so return 100%
        if (assets == 0) return 1e18;

        // adjust by 1e10 since price is returned with 8 decimals
        oracleApr = (rewardRate * SECONDS_PER_YEAR * price * 1e10) / (assets);
    }
}
