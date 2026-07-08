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
    event UniV4PoolSet(bytes32 indexed poolId, bool indexed groveIsToken0);
    event UniV4PoolAdded(bytes32 indexed poolId, bool indexed groveIsToken0);
    event UniV4PoolRemoved(bytes32 indexed poolId);
    event UniV4PoolsSet(bytes32[] poolIds, bool[] groveIsToken0);

    struct UniV4PoolConfig {
        bytes32 poolId;
        bool groveIsToken0;
    }

    struct UniV4PoolQuote {
        bytes32 poolId;
        bool groveIsToken0;
        uint128 liquidity;
        uint256 price;
    }

    /// @notice Sky Rewards staking contract
    address public constant STAKING = 0x4E41488C19cD35EB4de3083Fc3e204854c75c86a;

    /// @notice Grove governance token
    /// @dev Reward token for staking
    address public constant GROVE = 0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406;

    /// @notice Token to stake for GROVE rewards
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice GROVE is paired with USDC in UniV3 pool
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Uniswap V3 Router address
    address public constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /// @notice Default GROVE/USDC 1% UniV3 pool
    address public constant DEFAULT_GROVE_USDC_V3_POOL = 0x5D23797587B2c17414384384098291c0B1Fe1362;

    /// @notice Default GROVE/USDC 1% UniV3 fee
    uint24 public constant DEFAULT_REWARD_TO_BASE_UNI_V3_FEE = 10_000;

    /// @notice UniV4 StateView lens
    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);

    /// @notice UniV4 USDC/GROVE pool key:
    /// currency0 = USDC, currency1 = GROVE, hooks = address(0)
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID =
        0x2897b6ccd757711791a90b723df4f89567568859d040ff97d25cc4a5cb93ea03;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_TWO =
        0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_THREE =
        0xb557b2447a4723741959fe7ebd5a37375023931d19f6383cc83bd0d9c8397bb9;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_FOUR =
        0x2e53ef1a957f41bfba562bac317881d6f0ef2d6c217c7279c11b0878f9791ad5;

    uint256 internal constant SECONDS_PER_YEAR = 31536000;
    uint256 internal constant Q192 = 1 << 192;
    uint256 internal constant MAX_BPS = 10_000;
    uint256 public constant MIN_REWARD_POOL_LIQUIDITY = 1e12;
    uint256 public constant MIN_REWARD_POOL_USDC_BALANCE = 1_000e6;
    uint256 public constant MAX_V4_POOL_PRICE_DEVIATION_BPS = 1_000;
    uint256 public constant MAX_EXPECTED_APR = 5e17;

    /// @notice Address allowed to update oracle pool configuration
    address public management;

    /// @notice UniV3 fee used for quoting GROVE -> USDC
    uint24 public rewardToBaseUniV3Fee = DEFAULT_REWARD_TO_BASE_UNI_V3_FEE;

    /// @notice UniV4 pools used as fallback pricing candidates
    UniV4PoolConfig[] internal v4Pools;

    modifier onlyManagement() {
        _onlyManagement();
        _;
    }

    function _onlyManagement() internal view {
        require(msg.sender == management, "!management");
    }

    constructor() {
        management = msg.sender;
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID, groveIsToken0: false}));
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID_TWO, groveIsToken0: false}));
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID_THREE, groveIsToken0: false}));
        v4Pools.push(UniV4PoolConfig({poolId: DEFAULT_GROVE_USDC_V4_POOL_ID_FOUR, groveIsToken0: false}));
        emit ManagementTransferred(msg.sender);
    }

    /**
     * @param _strategy The strategy to get the apr for. Not a used variable in this case.
     * @param _delta The difference in debt.
     * @return oracleApr The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(address _strategy, int256 _delta) external view returns (uint256 oracleApr) {
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

        // Don't divide by 0. With no staked assets, the implied APR is outside the sane oracle range.
        if (assets == 0) revert("apr too high");

        // price is returned as 1e18 USDS per GROVE
        oracleApr = (rewardRate * SECONDS_PER_YEAR * price) / (assets);
        require(oracleApr <= MAX_EXPECTED_APR, "apr too high");
    }

    function setManagement(address _management) external onlyManagement {
        require(_management != address(0), "!management");
        management = _management;
        emit ManagementTransferred(_management);
    }

    function setUniV3Fee(uint24 _rewardToBaseUniV3Fee) external onlyManagement {
        require(_uniV3PoolForFee(_rewardToBaseUniV3Fee) != address(0), "!pool");
        rewardToBaseUniV3Fee = _rewardToBaseUniV3Fee;
        emit UniV3FeeSet(_rewardToBaseUniV3Fee);
    }

    function setUniV4Pool(bytes32 _poolId, bool _groveIsToken0) external onlyManagement {
        require(_poolId != bytes32(0), "!pool");
        delete v4Pools;
        v4Pools.push(UniV4PoolConfig({poolId: _poolId, groveIsToken0: _groveIsToken0}));
        emit UniV4PoolSet(_poolId, _groveIsToken0);
    }

    function setUniV4Pools(bytes32[] calldata _poolIds, bool[] calldata _groveIsToken0) external onlyManagement {
        _setUniV4Pools(_poolIds, _groveIsToken0);
    }

    function addUniV4Pool(bytes32 _poolId, bool _groveIsToken0) external onlyManagement {
        require(_poolId != bytes32(0), "!pool");
        require(!_hasUniV4Pool(_poolId), "duplicate");

        v4Pools.push(UniV4PoolConfig({poolId: _poolId, groveIsToken0: _groveIsToken0}));
        emit UniV4PoolAdded(_poolId, _groveIsToken0);
    }

    function removeUniV4Pool(uint256 _index) external onlyManagement {
        uint256 length = v4Pools.length;
        require(length > 1, "!pool");
        require(_index < length, "!index");

        bytes32 removedPoolId = v4Pools[_index].poolId;
        v4Pools[_index] = v4Pools[length - 1];
        v4Pools.pop();

        emit UniV4PoolRemoved(removedPoolId);
    }

    function uniV3Pool() external view returns (address) {
        return _uniV3Pool();
    }

    function uniV4PoolCount() external view returns (uint256) {
        return v4Pools.length;
    }

    function uniV4Pool(uint256 _index) external view returns (bytes32 poolId, bool groveIsToken0) {
        UniV4PoolConfig memory pool = v4Pools[_index];
        return (pool.poolId, pool.groveIsToken0);
    }

    function groveUsdcV4PoolId() external view returns (bytes32) {
        return v4Pools[0].poolId;
    }

    function v4GroveIsToken0() external view returns (bool) {
        return v4Pools[0].groveIsToken0;
    }

    function bestUniV4Pool() external view returns (bytes32 poolId, bool groveIsToken0, uint128 liquidity) {
        (poolId, groveIsToken0, liquidity,) = _selectedV4Pool();
    }

    function selectedUniV4Pool()
        external
        view
        returns (bytes32 poolId, bool groveIsToken0, uint128 liquidity, uint256 price)
    {
        return _selectedV4Pool();
    }

    function _grovePrice() internal view returns (uint256) {
        if (_v3PoolHasUsableLiquidity()) {
            try UniswapV3SwapSimulator.simulateExactInputSingle(
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
            ) returns (
                uint256 output
            ) {
                if (output > 0) return output * 1e12;
            } catch {}
        }

        (,,, uint256 price) = _selectedV4Pool();

        if (price > 0) return price;

        revert("insufficient pool liquidity");
    }

    function _v3PoolHasUsableLiquidity() internal view returns (bool) {
        address pool = _uniV3Pool();
        if (pool == address(0)) return false;

        return IUniswapV3Pool(pool).liquidity() >= MIN_REWARD_POOL_LIQUIDITY
            && IERC20(USDC).balanceOf(pool) >= MIN_REWARD_POOL_USDC_BALANCE;
    }

    function _v4GrovePrice(uint160 sqrtPriceX96, bool groveIsToken0) internal pure returns (uint256) {
        if (groveIsToken0) {
            return _quoteToken1ForToken0(sqrtPriceX96, 1e18) * 1e12;
        }

        return _quoteToken0ForToken1(sqrtPriceX96, 1e18) * 1e12;
    }

    function _selectedV4Pool()
        internal
        view
        returns (bytes32 poolId, bool groveIsToken0, uint128 liquidity, uint256 price)
    {
        uint256 length = v4Pools.length;
        UniV4PoolQuote[] memory quotes = new UniV4PoolQuote[](length);
        uint256 quoteCount;

        for (uint256 i; i < length; ++i) {
            UniV4PoolConfig memory pool = v4Pools[i];

            try UNISWAP_V4_STATE_VIEW.getLiquidity(pool.poolId) returns (uint128 poolLiquidity) {
                if (poolLiquidity < MIN_REWARD_POOL_LIQUIDITY) continue;

                try UNISWAP_V4_STATE_VIEW.getSlot0(pool.poolId) returns (
                    uint160 poolSqrtPriceX96, int24, uint24, uint24
                ) {
                    if (poolSqrtPriceX96 == 0) continue;

                    uint256 poolPrice = _v4GrovePrice(poolSqrtPriceX96, pool.groveIsToken0);
                    if (poolPrice == 0) continue;

                    quotes[quoteCount++] = UniV4PoolQuote({
                        poolId: pool.poolId,
                        groveIsToken0: pool.groveIsToken0,
                        liquidity: poolLiquidity,
                        price: poolPrice
                    });
                } catch {}
            } catch {}
        }

        if (quoteCount == 0) return (bytes32(0), false, 0, 0);

        uint256 medianPrice = _medianPrice(quotes, quoteCount);
        uint256 selectedIndex = type(uint256).max;

        for (uint256 i; i < quoteCount; ++i) {
            if (!_withinV4PriceDeviation(quotes[i].price, medianPrice)) continue;

            if (selectedIndex == type(uint256).max || quotes[i].liquidity > quotes[selectedIndex].liquidity) {
                selectedIndex = i;
            }
        }

        if (selectedIndex == type(uint256).max) return (bytes32(0), false, 0, 0);

        UniV4PoolQuote memory selected = quotes[selectedIndex];
        return (selected.poolId, selected.groveIsToken0, selected.liquidity, selected.price);
    }

    function _medianPrice(UniV4PoolQuote[] memory quotes, uint256 quoteCount) internal pure returns (uint256) {
        uint256[] memory prices = new uint256[](quoteCount);

        for (uint256 i; i < quoteCount; ++i) {
            prices[i] = quotes[i].price;
        }

        for (uint256 i = 1; i < quoteCount; ++i) {
            uint256 price = prices[i];
            uint256 j = i;

            while (j > 0 && prices[j - 1] > price) {
                prices[j] = prices[j - 1];
                --j;
            }

            prices[j] = price;
        }

        uint256 mid = quoteCount / 2;
        if (quoteCount % 2 == 1) return prices[mid];

        uint256 lower = prices[mid - 1];
        return lower + ((prices[mid] - lower) / 2);
    }

    function _withinV4PriceDeviation(uint256 price, uint256 referencePrice) internal pure returns (bool) {
        uint256 deviation = price > referencePrice ? price - referencePrice : referencePrice - price;
        return deviation <= FullMath.mulDiv(referencePrice, MAX_V4_POOL_PRICE_DEVIATION_BPS, MAX_BPS);
    }

    function _setUniV4Pools(bytes32[] calldata _poolIds, bool[] calldata _groveIsToken0) internal {
        uint256 length = _poolIds.length;
        require(length > 0 && length == _groveIsToken0.length, "length");

        delete v4Pools;
        for (uint256 i; i < length; ++i) {
            bytes32 poolId = _poolIds[i];
            require(poolId != bytes32(0), "!pool");

            for (uint256 j; j < i; ++j) {
                require(poolId != _poolIds[j], "duplicate");
            }

            v4Pools.push(UniV4PoolConfig({poolId: poolId, groveIsToken0: _groveIsToken0[i]}));
        }

        emit UniV4PoolsSet(_poolIds, _groveIsToken0);
    }

    function _hasUniV4Pool(bytes32 _poolId) internal view returns (bool) {
        uint256 length = v4Pools.length;
        for (uint256 i; i < length; ++i) {
            if (v4Pools[i].poolId == _poolId) return true;
        }

        return false;
    }

    function _uniV3Pool() internal view returns (address) {
        return _uniV3PoolForFee(rewardToBaseUniV3Fee);
    }

    function _uniV3PoolForFee(uint24 _fee) internal view returns (address) {
        return IUniswapV3Factory(ISwapRouterWithFactory(UNISWAP_V3_ROUTER).factory()).getPool(GROVE, USDC, _fee);
    }

    function _quoteToken1ForToken0(uint160 sqrtPriceX96, uint256 baseAmount) internal pure returns (uint256) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return FullMath.mulDiv(ratioX192, baseAmount, Q192);
        }

        uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        return FullMath.mulDiv(ratioX128, baseAmount, 1 << 128);
    }

    function _quoteToken0ForToken1(uint160 sqrtPriceX96, uint256 baseAmount) internal pure returns (uint256) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return FullMath.mulDiv(Q192, baseAmount, ratioX192);
        }

        uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        return FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
    }
}
