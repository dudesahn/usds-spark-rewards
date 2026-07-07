// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
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
    IUniswapV3Pool public constant GROVE_USDC_V3_POOL =
        IUniswapV3Pool(0x5D23797587B2c17414384384098291c0B1Fe1362);

    /// @notice UniV4 StateView lens
    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);

    /// @notice UniV4 USDC/GROVE pool key:
    /// currency0 = USDC, currency1 = GROVE, fee = 70000, tickSpacing = 1400, hooks = address(0)
    bytes32 public constant GROVE_USDC_V4_POOL_ID =
        0x905e07b7a930fc9998b0d695774e3841d37b5ab15b691118071722cc15d89792;

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
        if (_v3PoolHasUsableLiquidity()) {
            return _v3GrovePrice();
        }

        if (_v4PoolHasUsableLiquidity()) {
            return _v4GrovePrice();
        }

        revert("insufficient pool liquidity");
    }

    function _v3PoolHasUsableLiquidity() internal view returns (bool) {
        return
            GROVE_USDC_V3_POOL.liquidity() >= MIN_REWARD_POOL_LIQUIDITY &&
            IERC20(USDC).balanceOf(address(GROVE_USDC_V3_POOL)) >=
            MIN_REWARD_POOL_USDC_BALANCE;
    }

    function _v4PoolHasUsableLiquidity() internal view returns (bool) {
        try
            UNISWAP_V4_STATE_VIEW.getLiquidity(GROVE_USDC_V4_POOL_ID)
        returns (uint128 liquidity) {
            return liquidity >= MIN_REWARD_POOL_LIQUIDITY;
        } catch {
            return false;
        }
    }

    function _v3GrovePrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = GROVE_USDC_V3_POOL.slot0();
        address token0 = GROVE_USDC_V3_POOL.token0();
        address token1 = GROVE_USDC_V3_POOL.token1();

        if (token0 == GROVE && token1 == USDC) {
            return _quoteToken1ForToken0(sqrtPriceX96, 1e18) * 1e12;
        }

        require(token0 == USDC && token1 == GROVE, "pool tokens");
        return _quoteToken0ForToken1(sqrtPriceX96, 1e18) * 1e12;
    }

    function _v4GrovePrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , ) = UNISWAP_V4_STATE_VIEW.getSlot0(
            GROVE_USDC_V4_POOL_ID
        );

        // UniV4 pool key is USDC/GROVE, so quote token0 USDC for 1e18 token1 GROVE.
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
