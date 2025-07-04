// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {UniswapV3SwapSimulator, ISwapRouter} from "src/libraries/UniswapV3SwapSimulator.sol";
import {IStaking} from "src/interfaces/IStaking.sol";

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

    /// @notice Uniswap V3 Router address
    address public constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint256 internal constant SECONDS_PER_YEAR = 31536000;
    uint256 internal constant WAD = 1e18;

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

        // get price of 1 SPK from UniV3
        uint256 output = UniswapV3SwapSimulator.simulateExactInputSingle(
            ISwapRouter(UNISWAP_V3_ROUTER),
            ISwapRouter.ExactInputSingleParams({
                tokenIn: SPK,
                tokenOut: USDC,
                fee: 100,
                recipient: address(0),
                deadline: block.timestamp,
                amountIn: 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // adjust for ∆ assets
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        // don't divide by 0
        if (assets == 0) return 0;

        oracleApr = (rewardRate * SECONDS_PER_YEAR * output * 1e12) / (assets);
    }
}
