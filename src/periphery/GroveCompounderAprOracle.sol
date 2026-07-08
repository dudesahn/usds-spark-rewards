// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
import {UniswapV3SwapSimulator, ISwapRouter, ISwapRouterWithFactory} from "src/libraries/UniswapV3SwapSimulator.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "@uniswap-v3-core/libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GroveCompounderAprOracle {
    event ManagementTransferred(address indexed management);
    event UniV3FeeSet(uint24 indexed rewardToBaseUniV3Fee);
    event UniV4PoolSet(
        bytes32 indexed poolId,
        bool indexed groveIsToken0
    );

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

    /// @notice Uniswap V3 Router address
    address public constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /// @notice Default GROVE/USDC 1% UniV3 pool
    address public constant DEFAULT_GROVE_USDC_V3_POOL =
        0x5D23797587B2c17414384384098291c0B1Fe1362;

    /// @notice Default GROVE/USDC 1% UniV3 fee
    uint24 public constant DEFAULT_REWARD_TO_BASE_UNI_V3_FEE = 10_000;

    /// @notice UniV4 StateView lens
    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);

    /// @notice UniV4 USDC/GROVE pool key:
    /// currency0 = USDC, currency1 = GROVE, fee = 70000, tickSpacing = 1400, hooks = address(0)
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID =
        0x905e07b7a930fc9998b0d695774e3841d37b5ab15b691118071722cc15d89792;

    uint256 internal constant SECONDS_PER_YEAR = 31536000;
    uint256 internal constant Q192 = 1 << 192;
    uint256 public constant MIN_REWARD_POOL_LIQUIDITY = 1e12;
    uint256 public constant MIN_REWARD_POOL_USDC_BALANCE = 1_000e6;

    /// @notice Address allowed to update oracle pool configuration
    address public management;

    /// @notice UniV3 fee used for quoting GROVE -> USDC
    uint24 public rewardToBaseUniV3Fee = DEFAULT_REWARD_TO_BASE_UNI_V3_FEE;

    /// @notice UniV4 pool id used as fallback pricing
    bytes32 public groveUsdcV4PoolId = DEFAULT_GROVE_USDC_V4_POOL_ID;

    /// @notice True if the configured UniV4 pool has GROVE as currency0 and USDC as currency1
    bool public v4GroveIsToken0;

    modifier onlyManagement() {
        _onlyManagement();
        _;
    }

    function _onlyManagement() internal view {
        require(msg.sender == management, "!management");
    }

    constructor() {
        management = msg.sender;
        emit ManagementTransferred(msg.sender);
    }

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

    function setManagement(address _management) external onlyManagement {
        require(_management != address(0), "!management");
        management = _management;
        emit ManagementTransferred(_management);
    }

    function setUniV3Fee(
        uint24 _rewardToBaseUniV3Fee
    ) external onlyManagement {
        require(
            _uniV3PoolForFee(_rewardToBaseUniV3Fee) != address(0),
            "!pool"
        );
        rewardToBaseUniV3Fee = _rewardToBaseUniV3Fee;
        emit UniV3FeeSet(_rewardToBaseUniV3Fee);
    }

    function setUniV4Pool(
        bytes32 _poolId,
        bool _groveIsToken0
    ) external onlyManagement {
        require(_poolId != bytes32(0), "!pool");
        groveUsdcV4PoolId = _poolId;
        v4GroveIsToken0 = _groveIsToken0;
        emit UniV4PoolSet(_poolId, _groveIsToken0);
    }

    function uniV3Pool() external view returns (address) {
        return _uniV3Pool();
    }

    function _grovePrice() internal view returns (uint256) {
        if (_v3PoolHasUsableLiquidity()) {
            try
                UniswapV3SwapSimulator.simulateExactInputSingle(
                    ISwapRouter(UNISWAP_V3_ROUTER),
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: GROVE,
                        tokenOut: USDC,
                        fee: rewardToBaseUniV3Fee,
                        recipient: address(0),
                        deadline: block.timestamp,
                        amountIn: 1e18,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 output) {
                if (output > 0) return output * 1e12;
            } catch {}
        }

        if (_v4PoolHasUsableLiquidity()) {
            return _v4GrovePrice();
        }

        revert("insufficient pool liquidity");
    }

    function _v3PoolHasUsableLiquidity() internal view returns (bool) {
        address pool = _uniV3Pool();
        if (pool == address(0)) return false;

        return
            IUniswapV3Pool(pool).liquidity() >= MIN_REWARD_POOL_LIQUIDITY &&
            IERC20(USDC).balanceOf(pool) >= MIN_REWARD_POOL_USDC_BALANCE;
    }

    function _v4PoolHasUsableLiquidity() internal view returns (bool) {
        try
            UNISWAP_V4_STATE_VIEW.getLiquidity(groveUsdcV4PoolId)
        returns (uint128 liquidity) {
            return liquidity >= MIN_REWARD_POOL_LIQUIDITY;
        } catch {
            return false;
        }
    }

    function _v4GrovePrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , ) = UNISWAP_V4_STATE_VIEW.getSlot0(
            groveUsdcV4PoolId
        );

        if (v4GroveIsToken0) {
            return _quoteToken1ForToken0(sqrtPriceX96, 1e18) * 1e12;
        }

        return _quoteToken0ForToken1(sqrtPriceX96, 1e18) * 1e12;
    }

    function _uniV3Pool() internal view returns (address) {
        return _uniV3PoolForFee(rewardToBaseUniV3Fee);
    }

    function _uniV3PoolForFee(uint24 _fee) internal view returns (address) {
        return
            IUniswapV3Factory(
                ISwapRouterWithFactory(UNISWAP_V3_ROUTER).factory()
            ).getPool(GROVE, USDC, _fee);
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
