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

    error AprTooHigh();
    error DuplicatePool();
    error HookedPool();
    error InsufficientPoolLiquidity();
    error InvalidCurrencies();
    error InvalidManagement();
    error InvalidManualPrice();
    error InvalidPool();
    error InvalidPoolCount();
    error InvalidPoolId();
    error InvalidPoolSetter();
    error InvalidPriceSetter();
    error LivePriceAvailable();
    error LivePriceTooFarFromExpected(uint256 livePrice, uint256 expectedPrice);
    error LivePriceTooFar(uint256 livePrice, uint256 storedPrice);
    error InvalidTickSpacing();
    error UnauthorizedManagement();
    error UnauthorizedPoolSetter();
    error UnauthorizedPriceSetter();
    error UninitializedPool();

    event ManagementTransferred(address indexed management);
    event UniV4PoolsSet(bytes32[] poolIds);
    event PoolSetterSet(address indexed poolSetter, bool allowed);
    event PriceSetterSet(address indexed priceSetter, bool allowed);
    event StoredGrovePriceUpdated(uint256 previousPrice, uint256 newPrice, bool manual, uint256 timestamp);

    struct UniV4PoolConfig {
        bytes32 poolId;
        address quoteToken;
        uint24 fee;
        int24 tickSpacing;
        bool zeroForOne;
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

    /// @notice Supported GROVE quote tokens. Both use 6 decimals.
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IUniswapV4PositionManager public constant UNISWAP_V4_POSITION_MANAGER =
        IUniswapV4PositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);

    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;
    uint256 internal constant MAX_BPS = 10_000;
    uint256 public constant GROVE_PRICE_QUOTE_AMOUNT = 10_000e18;
    uint256 public constant GROVE_PRICE_CHUNK_AMOUNT = 1_000e18;
    uint256 internal constant GROVE_PRICE_CHUNK_COUNT = 10;
    uint256 public constant MAX_V4_POOLS = 10;
    uint256 internal constant MAX_V4_POOL_PRICE_DEVIATION_BPS = 1_000;
    uint256 public constant MAX_LIVE_PRICE_DEVIATION_BPS = 5_000;
    uint256 public constant MAX_CONFIRMED_PRICE_DEVIATION_BPS = 500;
    uint256 public constant MAX_EXPECTED_APR = 5e17;

    address public management;
    mapping(address => bool) public poolSetters;
    mapping(address => bool) public priceSetters;
    UniV4PoolConfig[] internal v4Pools;

    uint256 public storedGrovePrice;
    uint64 public lastPriceUpdate;
    bool public storedPriceIsManual;

    modifier onlyManagement() {
        _onlyManagement();
        _;
    }

    modifier onlyPoolSetter() {
        _onlyPoolSetter();
        _;
    }

    modifier onlyPriceSetter() {
        _onlyPriceSetter();
        _;
    }

    function _onlyManagement() internal view {
        if (msg.sender != management) revert UnauthorizedManagement();
    }

    function _onlyPoolSetter() internal view {
        if (msg.sender != management && !poolSetters[msg.sender]) revert UnauthorizedPoolSetter();
    }

    function _onlyPriceSetter() internal view {
        if (msg.sender != management && !priceSetters[msg.sender]) revert UnauthorizedPriceSetter();
    }

    constructor() {
        management = msg.sender;
        emit ManagementTransferred(msg.sender);
    }

    /**
     * @dev The strategy parameter is unused because all strategies share the staking rewards.
     *      APR uses a sane live V4 price when available and otherwise retains the
     *      last stored price without expiring it.
     * @param _delta The proposed change in staked USDS.
     * @return oracleApr Expected APR represented as 1e18.
     */
    function aprAfterDebtChange(address, int256 _delta) external view returns (uint256 oracleApr) {
        if (block.timestamp >= IStaking(STAKING).periodFinish()) return 0;

        uint256 assets = IStaking(STAKING).totalSupply();
        uint256 rewardRate = IStaking(STAKING).rewardRate();
        (uint256 price,) = _selectedGrovePrice();
        if (_delta < 0) {
            if (_delta == type(int256).min) revert AprTooHigh();
            // Negation is safe after excluding int256.min, and the result is nonnegative.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 decrease = uint256(-_delta);
            if (decrease >= assets) revert AprTooHigh();
            assets -= decrease;
        } else {
            // The branch proves that _delta is nonnegative.
            // forge-lint: disable-next-line(unsafe-typecast)
            assets += uint256(_delta);
        }

        oracleApr = (rewardRate * SECONDS_PER_YEAR * price) / assets;
        if (oracleApr > MAX_EXPECTED_APR) revert AprTooHigh();
    }

    function setManagement(address _management) external onlyManagement {
        if (_management == address(0)) revert InvalidManagement();
        management = _management;
        emit ManagementTransferred(_management);
    }

    function setPoolSetter(address _poolSetter, bool _allowed) external onlyManagement {
        if (_poolSetter == address(0)) revert InvalidPoolSetter();
        poolSetters[_poolSetter] = _allowed;
        emit PoolSetterSet(_poolSetter, _allowed);
    }

    function setPriceSetter(address _priceSetter, bool _allowed) external onlyManagement {
        if (_priceSetter == address(0)) revert InvalidPriceSetter();
        priceSetters[_priceSetter] = _allowed;
        emit PriceSetterSet(_priceSetter, _allowed);
    }

    /**
     * @notice Store the current V4 price when it is within 50% of the stored reference.
     */
    function refreshStoredGrovePrice() external onlyPoolSetter returns (uint256 livePrice) {
        (bool valid, uint256 price) = _tryGrovePrice();
        if (!valid) revert InsufficientPoolLiquidity();

        uint256 storedPrice = storedGrovePrice;
        if (storedPrice != 0 && !_withinLivePriceBound(price, storedPrice)) {
            revert LivePriceTooFar(price, storedPrice);
        }

        _storeGrovePrice(price, false);
        return price;
    }

    /**
     * @notice Explicitly accept the current V4 price after human review of `_expectedPrice`.
     * @dev This bypasses only the 50% stored-price sanity bound. The execution-time
     *      onchain quote must remain within 5% of the reviewed price.
     */
    function confirmLiveGrovePrice(uint256 _expectedPrice) external onlyPriceSetter returns (uint256 livePrice) {
        (bool valid, uint256 price) = _tryGrovePrice();
        if (!valid) revert InsufficientPoolLiquidity();
        if (!_withinPriceBound(price, _expectedPrice, MAX_CONFIRMED_PRICE_DEVIATION_BPS)) {
            revert LivePriceTooFarFromExpected(price, _expectedPrice);
        }
        _storeGrovePrice(price, false);
        return price;
    }

    /**
     * @notice Store an already-conservative manually sourced price.
     * @dev The trusted maintenance script, not this contract, applies the haircut.
     */
    function setManualGrovePrice(uint256 _price) external onlyPriceSetter {
        if (_price == 0) revert InvalidManualPrice();
        (bool livePriceAvailable,) = _tryGrovePrice();
        if (livePriceAvailable) revert LivePriceAvailable();
        _storeGrovePrice(_price, true);
    }

    function setUniV4Pools(bytes32[] calldata _poolIds) external onlyPoolSetter {
        uint256 length = _poolIds.length;
        if (length == 0 || length > MAX_V4_POOLS) revert InvalidPoolCount();

        delete v4Pools;
        for (uint256 i; i < length; ++i) {
            for (uint256 j; j < i; ++j) {
                if (_poolIds[i] == _poolIds[j]) revert DuplicatePool();
            }
            v4Pools.push(_resolvePoolConfig(_poolIds[i]));
        }

        emit UniV4PoolsSet(_poolIds);
    }

    function uniV4PoolCount() external view returns (uint256) {
        return v4Pools.length;
    }

    function uniV4Pool(uint256 _index)
        external
        view
        returns (bytes32 poolId, uint24 fee, int24 tickSpacing, address quoteToken, bool zeroForOne)
    {
        UniV4PoolConfig memory pool = v4Pools[_index];
        return (pool.poolId, pool.fee, pool.tickSpacing, pool.quoteToken, pool.zeroForOne);
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
        // Outputs are 6-decimal stablecoin units, treating USDC and USDT as par.
        RouteData memory route = _quoteV4Route();
        totalAmountOut = route.totalAmountOut;
        amountAllocated = route.amountAllocated;
        if (amountAllocated == GROVE_PRICE_QUOTE_AMOUNT) {
            price = FullMath.mulDiv(totalAmountOut, 1e30, GROVE_PRICE_QUOTE_AMOUNT);
        }
        return (totalAmountOut, amountAllocated, price, route.poolIds, route.allocations, route.outputs);
    }

    /**
     * @notice Return the price currently used by the APR calculation and whether it is live.
     */
    function grovePrice() external view returns (uint256 price, bool usingLivePrice) {
        return _selectedGrovePrice();
    }

    function _selectedGrovePrice() internal view returns (uint256 price, bool usingLivePrice) {
        (bool valid, uint256 livePrice) = _tryGrovePrice();
        uint256 storedPrice = storedGrovePrice;
        usingLivePrice = valid && (storedPrice == 0 || _withinLivePriceBound(livePrice, storedPrice));
        price = usingLivePrice ? livePrice : storedPrice;
    }

    function _tryGrovePrice() internal view returns (bool valid, uint256 price) {
        RouteData memory route = _quoteV4Route();
        if (route.amountAllocated != GROVE_PRICE_QUOTE_AMOUNT) return (false, 0);
        return (true, FullMath.mulDiv(route.totalAmountOut, 1e30, GROVE_PRICE_QUOTE_AMOUNT));
    }

    function _storeGrovePrice(uint256 price, bool manual) internal {
        uint256 previousPrice = storedGrovePrice;
        storedGrovePrice = price;
        lastPriceUpdate = uint64(block.timestamp);
        storedPriceIsManual = manual;
        emit StoredGrovePriceUpdated(previousPrice, price, manual, block.timestamp);
    }

    function _withinLivePriceBound(uint256 livePrice, uint256 storedPrice) internal pure returns (bool) {
        return _withinPriceBound(livePrice, storedPrice, MAX_LIVE_PRICE_DEVIATION_BPS);
    }

    function _withinPriceBound(uint256 price, uint256 referencePrice, uint256 maxDeviationBps)
        internal
        pure
        returns (bool)
    {
        uint256 deviation = price > referencePrice ? price - referencePrice : referencePrice - price;
        return deviation <= FullMath.mulDiv(referencePrice, maxDeviationBps, MAX_BPS);
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
                UniswapV4SwapSimulator.loadState(UNISWAP_V4_STATE_VIEW, config.poolId, config.zeroForOne);
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
            UNISWAP_V4_STATE_VIEW, config.poolId, config.tickSpacing, config.zeroForOne, amountIn, swapFee, state
        );
    }

    function _previewPrice(UniswapV4SwapSimulator.Preview memory preview) internal pure returns (uint256) {
        // USDC and USDT both have 6 decimals and are treated as par for live routing.
        // The maintenance script's unrestricted Kyber fallback instead uses final USDC output.
        return FullMath.mulDiv(preview.amountOut, 1e18, preview.amountIn);
    }

    function _resolvePoolConfig(bytes32 _poolId) internal view returns (UniV4PoolConfig memory config) {
        if (_poolId == bytes32(0)) revert InvalidPool();

        // PositionManager indexes pool keys by the leading 25 bytes of the canonical pool ID.
        // forge-lint: disable-next-line(unsafe-typecast)
        IUniswapV4PositionManager.PoolKeyData memory key = UNISWAP_V4_POSITION_MANAGER.poolKeys(bytes25(_poolId));
        bool isUsdcPool = key.currency0 == USDC && key.currency1 == GROVE;
        bool isUsdtPool = key.currency0 == GROVE && key.currency1 == USDT;
        if (!isUsdcPool && !isUsdtPool) revert InvalidCurrencies();
        if (key.hooks != address(0)) revert HookedPool();
        if (key.tickSpacing <= 0) revert InvalidTickSpacing();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(key.currency0),
            currency1: Currency.wrap(key.currency1),
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: IHooks(key.hooks)
        });
        if (PoolId.unwrap(poolKey.toId()) != _poolId) revert InvalidPoolId();

        (uint160 sqrtPriceX96,,,) = UNISWAP_V4_STATE_VIEW.getSlot0(_poolId);
        if (sqrtPriceX96 == 0) revert UninitializedPool();
        return UniV4PoolConfig({
            poolId: _poolId,
            quoteToken: isUsdcPool ? USDC : USDT,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            zeroForOne: isUsdtPool
        });
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
