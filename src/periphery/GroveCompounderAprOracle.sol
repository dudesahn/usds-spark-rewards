// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
import {UniswapV4SwapSimulator} from "src/libraries/UniswapV4SwapSimulator.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

interface IUniswapV4PositionManager {
    struct PoolKeyData {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    function poolKeys(bytes25 poolId) external view returns (PoolKeyData memory);
}

contract GroveCompounderAprOracle {
    using PoolIdLibrary for PoolKey;

    event ManagementTransferred(address indexed management);
    event UniV4PoolSet(bytes32 indexed poolId, uint24 fee, int24 tickSpacing);
    event UniV4PoolAdded(bytes32 indexed poolId, uint24 fee, int24 tickSpacing);
    event UniV4PoolRemoved(bytes32 indexed poolId);
    event UniV4PoolsSet(bytes32[] poolIds);
    event PoolSetterSet(address indexed poolSetter, bool allowed);

    struct UniV4PoolConfig {
        bytes32 poolId;
        uint24 fee;
        int24 tickSpacing;
    }

    struct RouteData {
        uint256 totalAmountOut;
        uint256 amountAllocated;
        bytes32[] poolIds;
        uint256[] allocations;
        uint256[] outputs;
    }

    struct RoutingState {
        UniswapV4SwapSimulator.State[] states;
        UniswapV4SwapSimulator.Preview[] previews;
        uint24[] swapFees;
        bool[] eligible;
    }

    /// @notice Sky Rewards staking contract
    address public constant STAKING = 0x4E41488C19cD35EB4de3083Fc3e204854c75c86a;

    /// @notice Grove governance token and staking reward token
    address public constant GROVE = 0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406;

    /// @notice Token staked to earn GROVE rewards
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice GROVE quote token
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IUniswapV4PositionManager public constant UNISWAP_V4_POSITION_MANAGER =
        IUniswapV4PositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);

    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID =
        0x2897b6ccd757711791a90b723df4f89567568859d040ff97d25cc4a5cb93ea03;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_TWO =
        0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_THREE =
        0xb557b2447a4723741959fe7ebd5a37375023931d19f6383cc83bd0d9c8397bb9;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_FOUR =
        0x2e53ef1a957f41bfba562bac317881d6f0ef2d6c217c7279c11b0878f9791ad5;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_FIVE_PERCENT =
        0xaa0b1a90c6188f42c3603998536418f4eeedccf20b999377dab7e4c6aafc5286;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_VOLUME =
        0x20d117a32203158c46d0dce34ade2b2cbf846d151e9cea406e0463fe361d82ce;
    bytes32 public constant DEFAULT_GROVE_USDC_V4_POOL_ID_KYBER =
        0x0d40eef4d9600a37016f34d089705e83d8d9e40ac80838abb04a278fa049e874;

    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;
    uint256 internal constant MAX_BPS = 10_000;
    bool internal constant GROVE_TO_USDC_ZERO_FOR_ONE = false;

    uint256 public constant GROVE_PRICE_QUOTE_AMOUNT = 10_000e18;
    uint256 public constant GROVE_PRICE_CHUNK_AMOUNT = 1_000e18;
    uint256 public constant GROVE_PRICE_CHUNK_COUNT = 10;
    uint256 public constant MAX_V4_POOLS = 10;
    uint256 public constant MAX_V4_POOL_PRICE_DEVIATION_BPS = 1_000;
    uint256 public constant MAX_EXPECTED_APR = 5e17;

    address public management;
    mapping(address => bool) public poolSetters;
    UniV4PoolConfig[] internal v4Pools;

    modifier onlyManagement() {
        _onlyManagement();
        _;
    }

    modifier onlyPoolSetter() {
        _onlyPoolSetter();
        _;
    }

    function _onlyManagement() internal view {
        require(msg.sender == management, "!management");
    }

    function _onlyPoolSetter() internal view {
        require(msg.sender == management || poolSetters[msg.sender], "!pool setter");
    }

    constructor() {
        management = msg.sender;
        _pushUniV4Pool(DEFAULT_GROVE_USDC_V4_POOL_ID_FIVE_PERCENT);
        _pushUniV4Pool(DEFAULT_GROVE_USDC_V4_POOL_ID);
        _pushUniV4Pool(DEFAULT_GROVE_USDC_V4_POOL_ID_TWO);
        _pushUniV4Pool(DEFAULT_GROVE_USDC_V4_POOL_ID_VOLUME);
        _pushUniV4Pool(DEFAULT_GROVE_USDC_V4_POOL_ID_KYBER);
        emit ManagementTransferred(msg.sender);
    }

    /**
     * @dev The strategy parameter is unused because all strategies share the staking rewards.
     * @param _delta The proposed change in staked USDS.
     * @return oracleApr Expected APR represented as 1e18.
     */
    function aprAfterDebtChange(address, int256 _delta) external view returns (uint256 oracleApr) {
        uint256 assets = IStaking(STAKING).totalSupply();
        uint256 rewardRate = IStaking(STAKING).rewardRate();

        if (block.timestamp > IStaking(STAKING).periodFinish()) return 0;

        uint256 price = _grovePrice();
        assets = _delta < 0 ? assets - uint256(-_delta) : assets + uint256(_delta);

        if (assets == 0) revert("apr too high");

        oracleApr = (rewardRate * SECONDS_PER_YEAR * price) / assets;
        require(oracleApr <= MAX_EXPECTED_APR, "apr too high");
    }

    function setManagement(address _management) external onlyManagement {
        require(_management != address(0), "!management");
        management = _management;
        emit ManagementTransferred(_management);
    }

    function setPoolSetter(address _poolSetter, bool _allowed) external onlyManagement {
        require(_poolSetter != address(0), "!pool setter");
        poolSetters[_poolSetter] = _allowed;
        emit PoolSetterSet(_poolSetter, _allowed);
    }

    function setUniV4Pool(bytes32 _poolId) external onlyPoolSetter {
        UniV4PoolConfig memory config = _resolvePoolConfig(_poolId);
        delete v4Pools;
        v4Pools.push(config);
        emit UniV4PoolSet(config.poolId, config.fee, config.tickSpacing);
    }

    function setUniV4Pools(bytes32[] calldata _poolIds) external onlyPoolSetter {
        uint256 length = _poolIds.length;
        require(length > 0 && length <= MAX_V4_POOLS, "length");

        delete v4Pools;
        for (uint256 i; i < length; ++i) {
            for (uint256 j; j < i; ++j) {
                require(_poolIds[i] != _poolIds[j], "duplicate");
            }
            v4Pools.push(_resolvePoolConfig(_poolIds[i]));
        }

        emit UniV4PoolsSet(_poolIds);
    }

    function addUniV4Pool(bytes32 _poolId) external onlyPoolSetter {
        require(v4Pools.length < MAX_V4_POOLS, "max pools");
        require(!_hasUniV4Pool(_poolId), "duplicate");

        UniV4PoolConfig memory config = _resolvePoolConfig(_poolId);
        v4Pools.push(config);
        emit UniV4PoolAdded(config.poolId, config.fee, config.tickSpacing);
    }

    function removeUniV4Pool(uint256 _index) external onlyPoolSetter {
        uint256 length = v4Pools.length;
        require(length > 1, "!pool");
        require(_index < length, "!index");

        bytes32 removedPoolId = v4Pools[_index].poolId;
        v4Pools[_index] = v4Pools[length - 1];
        v4Pools.pop();
        emit UniV4PoolRemoved(removedPoolId);
    }

    function uniV4PoolCount() external view returns (uint256) {
        return v4Pools.length;
    }

    function uniV4Pool(uint256 _index) external view returns (bytes32 poolId, uint24 fee, int24 tickSpacing) {
        UniV4PoolConfig memory pool = v4Pools[_index];
        return (pool.poolId, pool.fee, pool.tickSpacing);
    }

    function quoteUniV4Route()
        external
        view
        returns (
            uint256 totalAmountOut,
            uint256 amountAllocated,
            uint256 price,
            bytes32[] memory poolIds,
            uint256[] memory allocations,
            uint256[] memory outputs
        )
    {
        RouteData memory route = _quoteV4Route();
        totalAmountOut = route.totalAmountOut;
        amountAllocated = route.amountAllocated;
        if (amountAllocated == GROVE_PRICE_QUOTE_AMOUNT) {
            price = FullMath.mulDiv(totalAmountOut, 1e30, GROVE_PRICE_QUOTE_AMOUNT);
        }
        return (totalAmountOut, amountAllocated, price, route.poolIds, route.allocations, route.outputs);
    }

    function _grovePrice() internal view returns (uint256) {
        RouteData memory route = _quoteV4Route();
        require(route.amountAllocated == GROVE_PRICE_QUOTE_AMOUNT, "insufficient pool liquidity");
        return FullMath.mulDiv(route.totalAmountOut, 1e30, GROVE_PRICE_QUOTE_AMOUNT);
    }

    function _quoteV4Route() internal view returns (RouteData memory route) {
        uint256 poolCount = v4Pools.length;
        route.poolIds = new bytes32[](poolCount);
        route.allocations = new uint256[](poolCount);
        route.outputs = new uint256[](poolCount);

        (RoutingState memory routing, uint256[] memory firstChunkPrices, uint256 referenceCount) =
            _initializeRouting(route);
        if (referenceCount >= 3) {
            uint256 medianPrice = _median(firstChunkPrices, referenceCount);
            for (uint256 i; i < poolCount; ++i) {
                if (routing.eligible[i] && !_withinPriceDeviation(_previewPrice(routing.previews[i]), medianPrice)) {
                    routing.eligible[i] = false;
                }
            }
        }

        _allocateChunks(route, routing);
    }

    function _initializeRouting(RouteData memory route)
        internal
        view
        returns (RoutingState memory routing, uint256[] memory firstChunkPrices, uint256 referenceCount)
    {
        uint256 poolCount = v4Pools.length;
        routing.states = new UniswapV4SwapSimulator.State[](poolCount);
        routing.previews = new UniswapV4SwapSimulator.Preview[](poolCount);
        routing.swapFees = new uint24[](poolCount);
        routing.eligible = new bool[](poolCount);
        firstChunkPrices = new uint256[](poolCount);

        for (uint256 i; i < poolCount; ++i) {
            UniV4PoolConfig memory config = v4Pools[i];
            route.poolIds[i] = config.poolId;

            bool initialized;
            (routing.states[i], routing.swapFees[i], initialized) =
                UniswapV4SwapSimulator.loadState(UNISWAP_V4_STATE_VIEW, config.poolId, GROVE_TO_USDC_ZERO_FOR_ONE);
            if (!initialized) continue;

            routing.previews[i] =
                _previewChunk(config, routing.swapFees[i], routing.states[i], GROVE_PRICE_CHUNK_AMOUNT);
            if (!routing.previews[i].valid || routing.previews[i].amountIn == 0 || routing.previews[i].amountOut == 0) {
                continue;
            }

            routing.eligible[i] = true;
            if (routing.previews[i].fullyFilled) {
                firstChunkPrices[referenceCount++] = _previewPrice(routing.previews[i]);
            }
        }
    }

    function _allocateChunks(RouteData memory route, RoutingState memory routing) internal view {
        uint256 poolCount = v4Pools.length;
        for (uint256 iteration; iteration < GROVE_PRICE_CHUNK_COUNT + poolCount; ++iteration) {
            uint256 remaining = GROVE_PRICE_QUOTE_AMOUNT - route.amountAllocated;
            if (remaining == 0) return;
            uint256 requested = remaining < GROVE_PRICE_CHUNK_AMOUNT ? remaining : GROVE_PRICE_CHUNK_AMOUNT;

            if (requested != GROVE_PRICE_CHUNK_AMOUNT) {
                for (uint256 i; i < poolCount; ++i) {
                    if (!routing.eligible[i]) continue;
                    routing.previews[i] = _previewChunk(v4Pools[i], routing.swapFees[i], routing.states[i], requested);
                    if (
                        !routing.previews[i].valid || routing.previews[i].amountIn == 0
                            || routing.previews[i].amountOut == 0
                    ) routing.eligible[i] = false;
                }
            }

            uint256 bestIndex = type(uint256).max;
            for (uint256 i; i < poolCount; ++i) {
                if (!routing.eligible[i]) continue;
                if (
                    bestIndex == type(uint256).max
                        || _previewPrice(routing.previews[i]) > _previewPrice(routing.previews[bestIndex])
                ) {
                    bestIndex = i;
                }
            }
            if (bestIndex == type(uint256).max) return;

            uint256 amountOut = routing.previews[bestIndex].amountOut;
            uint256 amountIn = routing.previews[bestIndex].amountIn;
            routing.states[bestIndex] = routing.previews[bestIndex].state;
            route.allocations[bestIndex] += amountIn;
            route.outputs[bestIndex] += amountOut;
            route.amountAllocated += amountIn;
            route.totalAmountOut += amountOut;

            if (route.amountAllocated == GROVE_PRICE_QUOTE_AMOUNT) return;
            if (!routing.previews[bestIndex].fullyFilled) {
                routing.eligible[bestIndex] = false;
                continue;
            }

            UniV4PoolConfig memory config = v4Pools[bestIndex];
            routing.previews[bestIndex] =
                _previewChunk(config, routing.swapFees[bestIndex], routing.states[bestIndex], GROVE_PRICE_CHUNK_AMOUNT);
            if (
                !routing.previews[bestIndex].valid || routing.previews[bestIndex].amountIn == 0
                    || routing.previews[bestIndex].amountOut == 0
            ) {
                routing.eligible[bestIndex] = false;
            }
        }
    }

    function _previewChunk(
        UniV4PoolConfig memory config,
        uint24 swapFee,
        UniswapV4SwapSimulator.State memory state,
        uint256 amountIn
    ) internal view returns (UniswapV4SwapSimulator.Preview memory) {
        return UniswapV4SwapSimulator.previewExactInput(
            UNISWAP_V4_STATE_VIEW,
            config.poolId,
            config.tickSpacing,
            GROVE_TO_USDC_ZERO_FOR_ONE,
            amountIn,
            swapFee,
            state
        );
    }

    function _previewPrice(UniswapV4SwapSimulator.Preview memory preview) internal pure returns (uint256) {
        return FullMath.mulDiv(preview.amountOut, 1e18, preview.amountIn);
    }

    function _resolvePoolConfig(bytes32 _poolId) internal view returns (UniV4PoolConfig memory config) {
        require(_poolId != bytes32(0), "!pool");

        IUniswapV4PositionManager.PoolKeyData memory key = UNISWAP_V4_POSITION_MANAGER.poolKeys(bytes25(_poolId));
        require(key.currency0 == USDC && key.currency1 == GROVE, "!currencies");
        require(key.hooks == address(0), "!hooks");
        require(key.tickSpacing > 0, "!tick spacing");

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(key.currency0),
            currency1: Currency.wrap(key.currency1),
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: IHooks(key.hooks)
        });
        require(PoolId.unwrap(poolKey.toId()) == _poolId, "!pool id");

        (uint160 sqrtPriceX96,,,) = UNISWAP_V4_STATE_VIEW.getSlot0(_poolId);
        require(sqrtPriceX96 != 0, "!initialized");
        return UniV4PoolConfig({poolId: _poolId, fee: key.fee, tickSpacing: key.tickSpacing});
    }

    function _pushUniV4Pool(bytes32 _poolId) internal {
        v4Pools.push(_resolvePoolConfig(_poolId));
    }

    function _hasUniV4Pool(bytes32 _poolId) internal view returns (bool) {
        for (uint256 i; i < v4Pools.length; ++i) {
            if (v4Pools[i].poolId == _poolId) return true;
        }
        return false;
    }

    function _median(uint256[] memory values, uint256 count) internal pure returns (uint256) {
        for (uint256 i = 1; i < count; ++i) {
            uint256 value = values[i];
            uint256 j = i;
            while (j > 0 && values[j - 1] > value) {
                values[j] = values[j - 1];
                --j;
            }
            values[j] = value;
        }

        uint256 mid = count / 2;
        if (count % 2 == 1) return values[mid];
        uint256 lower = values[mid - 1];
        return lower + ((values[mid] - lower) / 2);
    }

    function _withinPriceDeviation(uint256 price, uint256 referencePrice) internal pure returns (bool) {
        uint256 deviation = price > referencePrice ? price - referencePrice : referencePrice - price;
        return deviation <= FullMath.mulDiv(referencePrice, MAX_V4_POOL_PRICE_DEVIATION_BPS, MAX_BPS);
    }
}
