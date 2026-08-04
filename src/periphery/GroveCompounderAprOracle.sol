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
    error InvalidIndex();
    error InvalidManagement();
    error InvalidPool();
    error InvalidPoolCount();
    error InvalidPoolId();
    error InvalidPoolSetter();
    error InvalidTickSpacing();
    error MaxPools();
    error UnauthorizedManagement();
    error UnauthorizedPoolSetter();
    error UninitializedPool();

    event ManagementTransferred(address indexed management);
    event UniV4PoolAdded(bytes32 indexed poolId, uint24 fee, int24 tickSpacing);
    event UniV4PoolRemoved(bytes32 indexed poolId);
    event UniV4PoolsSet(bytes32[] poolIds);
    event PoolSetterSet(address indexed poolSetter, bool allowed);
    event CachedGrovePriceUpdated(uint256 previousPrice, uint256 newPrice, uint256 timestamp);
    event CachedGrovePriceVerified(uint256 cachedPrice, uint256 livePrice, uint256 timestamp);
    event GrovePriceConfirmationPending(uint256 price, uint256 timestamp);
    event GrovePriceConfirmationCleared();

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

    /// @notice GROVE quote token
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IUniswapV4StateView public constant UNISWAP_V4_STATE_VIEW =
        IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IUniswapV4PositionManager public constant UNISWAP_V4_POSITION_MANAGER =
        IUniswapV4PositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);

    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;
    uint256 internal constant MAX_BPS = 10_000;
    bool internal constant GROVE_TO_USDC_ZERO_FOR_ONE = false;

    uint256 public constant GROVE_PRICE_QUOTE_AMOUNT = 10_000e18;
    uint256 public constant GROVE_PRICE_CHUNK_AMOUNT = 1_000e18;
    uint256 internal constant GROVE_PRICE_CHUNK_COUNT = 10;
    uint256 public constant MAX_V4_POOLS = 10;
    uint256 internal constant MAX_V4_POOL_PRICE_DEVIATION_BPS = 1_000;
    uint256 public constant MAX_EXPECTED_APR = 5e17;

    uint256 public constant CACHE_UPDATE_THRESHOLD_BPS = 500;
    uint256 public constant LARGE_PRICE_MOVE_BPS = 1_000;
    uint256 public constant CACHE_HEARTBEAT = 12 hours;
    uint256 public constant CACHE_FULL_PRICE_AGE = 24 hours;
    uint256 public constant CACHE_MAX_AGE = 48 hours;
    uint256 public constant STALE_CACHE_PRICE_BPS = 9_000;
    uint256 public constant PRICE_CONFIRMATION_DELAY = 30 minutes;
    uint256 public constant PRICE_CONFIRMATION_WINDOW = 6 hours;

    address public management;
    mapping(address => bool) public poolSetters;
    UniV4PoolConfig[] internal v4Pools;

    uint256 public cachedGrovePrice;
    uint256 public pendingGrovePrice;
    uint64 public lastPriceVerification;
    uint64 public pendingPriceTimestamp;

    modifier onlyManagement() {
        _onlyManagement();
        _;
    }

    modifier onlyPoolSetter() {
        _onlyPoolSetter();
        _;
    }

    function _onlyManagement() internal view {
        if (msg.sender != management) revert UnauthorizedManagement();
    }

    function _onlyPoolSetter() internal view {
        if (msg.sender != management && !poolSetters[msg.sender]) revert UnauthorizedPoolSetter();
    }

    constructor() {
        management = msg.sender;
        emit ManagementTransferred(msg.sender);
    }

    /**
     * @dev The strategy parameter is unused because all strategies share the staking rewards.
     * @param _delta The proposed change in staked USDS.
     * @return oracleApr Expected APR represented as 1e18.
     */
    function aprAfterDebtChange(address, int256 _delta) external view returns (uint256 oracleApr) {
        if (block.timestamp >= IStaking(STAKING).periodFinish()) return 0;

        uint256 assets = IStaking(STAKING).totalSupply();
        uint256 rewardRate = IStaking(STAKING).rewardRate();
        uint256 price = _grovePrice();
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

    /**
     * @notice Verify the cached GROVE price against the currently executable V4 route.
     * @dev Prices moving by 5% to 10% are updated immediately. Moves above 10%
     *      must be observed twice, at least 30 minutes apart and no more than
     *      6 hours apart, with the observations agreeing within 5%.
     * @return livePrice The current fully executable 10,000 GROVE quote.
     * @return priceUpdated Whether the active cached price was updated.
     * @return confirmationPending Whether a large move still needs confirmation.
     */
    function refreshCachedGrovePrice()
        external
        onlyPoolSetter
        returns (uint256 livePrice, bool priceUpdated, bool confirmationPending)
    {
        (bool valid, uint256 price) = _tryGrovePrice();
        if (!valid) revert InsufficientPoolLiquidity();
        livePrice = price;

        uint256 cachedPrice = cachedGrovePrice;
        if (cachedPrice == 0) {
            _updateCachedGrovePrice(livePrice);
            return (livePrice, true, false);
        }

        uint256 deviationBps = _priceDeviationBps(livePrice, cachedPrice);
        if (deviationBps > LARGE_PRICE_MOVE_BPS) {
            (priceUpdated, confirmationPending) = _handleLargePriceMove(livePrice);
            return (livePrice, priceUpdated, confirmationPending);
        }

        _clearPendingPrice();
        if (deviationBps >= CACHE_UPDATE_THRESHOLD_BPS) {
            _updateCachedGrovePrice(livePrice);
            return (livePrice, true, false);
        }

        if (block.timestamp >= uint256(lastPriceVerification) + CACHE_HEARTBEAT) {
            lastPriceVerification = uint64(block.timestamp);
            emit CachedGrovePriceVerified(cachedPrice, livePrice, block.timestamp);
        }

        return (livePrice, false, false);
    }

    /**
     * @notice Return the cached price after applying the configured stale-price policy.
     * @return price The full cached price through 24 hours, 90% through 48 hours,
     *         and zero beyond 48 hours.
     */
    function effectiveCachedGrovePrice() public view returns (uint256 price) {
        uint256 verifiedAt = lastPriceVerification;
        if (verifiedAt == 0 || cachedGrovePrice == 0) return 0;

        uint256 age = block.timestamp - verifiedAt;
        if (age <= CACHE_FULL_PRICE_AGE) return cachedGrovePrice;
        if (age <= CACHE_MAX_AGE) return FullMath.mulDiv(cachedGrovePrice, STALE_CACHE_PRICE_BPS, MAX_BPS);
        return 0;
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

    function addUniV4Pool(bytes32 _poolId) external onlyPoolSetter {
        if (v4Pools.length >= MAX_V4_POOLS) revert MaxPools();
        if (_hasUniV4Pool(_poolId)) revert DuplicatePool();

        UniV4PoolConfig memory config = _resolvePoolConfig(_poolId);
        v4Pools.push(config);
        emit UniV4PoolAdded(config.poolId, config.fee, config.tickSpacing);
    }

    function removeUniV4Pool(uint256 _index) external onlyPoolSetter {
        uint256 length = v4Pools.length;
        if (length <= 1) revert InvalidPoolCount();
        if (_index >= length) revert InvalidIndex();

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
        (bool valid, uint256 price) = _tryGrovePrice();
        if (valid) return price;
        return effectiveCachedGrovePrice();
    }

    function _tryGrovePrice() internal view returns (bool valid, uint256 price) {
        RouteData memory route = _quoteV4Route();
        if (route.amountAllocated != GROVE_PRICE_QUOTE_AMOUNT) return (false, 0);
        return (true, FullMath.mulDiv(route.totalAmountOut, 1e30, GROVE_PRICE_QUOTE_AMOUNT));
    }

    function _handleLargePriceMove(uint256 livePrice) internal returns (bool priceUpdated, bool confirmationPending) {
        uint256 pendingPrice = pendingGrovePrice;
        uint256 pendingAt = pendingPriceTimestamp;

        if (pendingPrice != 0 && pendingAt != 0) {
            uint256 pendingAge = block.timestamp - pendingAt;
            bool observationsAgree = _priceDeviationBps(livePrice, pendingPrice) <= CACHE_UPDATE_THRESHOLD_BPS;

            if (observationsAgree && pendingAge >= PRICE_CONFIRMATION_DELAY && pendingAge <= PRICE_CONFIRMATION_WINDOW)
            {
                _updateCachedGrovePrice(livePrice);
                return (true, false);
            }

            if (observationsAgree && pendingAge <= PRICE_CONFIRMATION_WINDOW) return (false, true);
        }

        pendingGrovePrice = livePrice;
        pendingPriceTimestamp = uint64(block.timestamp);
        emit GrovePriceConfirmationPending(livePrice, block.timestamp);
        return (false, true);
    }

    function _updateCachedGrovePrice(uint256 livePrice) internal {
        uint256 previousPrice = cachedGrovePrice;
        cachedGrovePrice = livePrice;
        lastPriceVerification = uint64(block.timestamp);
        _clearPendingPrice();
        emit CachedGrovePriceUpdated(previousPrice, livePrice, block.timestamp);
    }

    function _clearPendingPrice() internal {
        if (pendingGrovePrice == 0 && pendingPriceTimestamp == 0) return;
        pendingGrovePrice = 0;
        pendingPriceTimestamp = 0;
        emit GrovePriceConfirmationCleared();
    }

    function _priceDeviationBps(uint256 price, uint256 referencePrice) internal pure returns (uint256) {
        uint256 deviation = price > referencePrice ? price - referencePrice : referencePrice - price;
        return FullMath.mulDiv(deviation, MAX_BPS, referencePrice);
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
        if (_poolId == bytes32(0)) revert InvalidPool();

        // PositionManager indexes pool keys by the leading 25 bytes of the canonical pool ID.
        // forge-lint: disable-next-line(unsafe-typecast)
        IUniswapV4PositionManager.PoolKeyData memory key = UNISWAP_V4_POSITION_MANAGER.poolKeys(bytes25(_poolId));
        if (key.currency0 != USDC || key.currency1 != GROVE) revert InvalidCurrencies();
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
        return UniV4PoolConfig({poolId: _poolId, fee: key.fee, tickSpacing: key.tickSpacing});
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
