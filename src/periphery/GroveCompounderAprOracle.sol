// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "@uniswap-v3-core/libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GroveCompounderAprOracle {
    /// @notice Sky Rewards staking contract
    address public constant STAKING =
        0x4E41488C19cD35EB4de3083Fc3e204854c75c86a;

    /// @notice Grove governance token
    /// @dev Reward token for staking
    address public constant GROVE =
        0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406;

    /// @notice Token to stake for GROVE rewards
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice GROVE is paired with USDC in UniV3 pool
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice GROVE/USDC 1% UniV3 pool
    IUniswapV3Pool public constant GROVE_USDC_POOL =
        IUniswapV3Pool(0x5D23797587B2c17414384384098291c0B1Fe1362);

    uint256 internal constant SECONDS_PER_YEAR = 31536000;
    uint256 internal constant Q192 = 1 << 192;
    uint256 public constant MIN_REWARD_POOL_LIQUIDITY = 1e12;
    uint256 public constant MIN_REWARD_POOL_USDC_BALANCE = 1_000e6;

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

        if (block.timestamp > IStaking(STAKING).periodFinish()) {
            return 0;
        }

        uint256 price = _grovePrice();

        // adjust for ∆ assets
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        // don't divide by 0. if no assets in staking contract, yield would be very good so return 100%
        if (assets == 0) return 1e18;

        // price is returned as 1e18 USDS per GROVE
        oracleApr = (rewardRate * SECONDS_PER_YEAR * price) / (assets);
    }

    function _grovePrice() internal view returns (uint256) {
        require(
            GROVE_USDC_POOL.liquidity() >= MIN_REWARD_POOL_LIQUIDITY &&
                IERC20(USDC).balanceOf(address(GROVE_USDC_POOL)) >=
                MIN_REWARD_POOL_USDC_BALANCE,
            "insufficient pool liquidity"
        );

        (uint160 sqrtPriceX96, , , , , , ) = GROVE_USDC_POOL.slot0();
        address token0 = GROVE_USDC_POOL.token0();
        address token1 = GROVE_USDC_POOL.token1();

        if (token0 == GROVE && token1 == USDC) {
            return _quoteToken1ForToken0(sqrtPriceX96, 1e18) * 1e12;
        }

        require(token0 == USDC && token1 == GROVE, "pool tokens");
        return _quoteToken0ForToken1(sqrtPriceX96, 1e18) * 1e12;
    }

    function _quoteToken1ForToken0(
        uint160 sqrtPriceX96,
        uint256 baseAmount
    ) internal pure returns (uint256) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return FullMath.mulDiv(ratioX192, baseAmount, Q192);
        }

        uint256 ratioX128 = FullMath.mulDiv(
            sqrtPriceX96,
            sqrtPriceX96,
            1 << 64
        );
        return FullMath.mulDiv(ratioX128, baseAmount, 1 << 128);
    }

    function _quoteToken0ForToken1(
        uint160 sqrtPriceX96,
        uint256 baseAmount
    ) internal pure returns (uint256) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return FullMath.mulDiv(Q192, baseAmount, ratioX192);
        }

        uint256 ratioX128 = FullMath.mulDiv(
            sqrtPriceX96,
            sqrtPriceX96,
            1 << 64
        );
        return FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
    }
}
