// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {GroveUniV4PoolConfig} from "script/GroveUniV4PoolConfig.sol";
import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
import {UniswapV4SwapSimulator} from "src/libraries/UniswapV4SwapSimulator.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

interface IV4Quoter {
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }

    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);
}

interface IV4PositionManagerView {
    function poolKeys(bytes25 poolId)
        external
        view
        returns (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks);
}

contract V4SimulatorHarness {
    function loadSwapFee(IUniswapV4StateView stateView, bytes32 poolId)
        external
        view
        returns (uint24 swapFee, bool initialized)
    {
        (, swapFee, initialized) = UniswapV4SwapSimulator.loadState(stateView, poolId, false);
    }

    function quote(IUniswapV4StateView stateView, bytes32 poolId, int24 tickSpacing, uint256 amountIn)
        external
        view
        returns (uint256 amountConsumed, uint256 amountOut, bool valid, bool fullyFilled)
    {
        (UniswapV4SwapSimulator.State memory state, uint24 swapFee, bool initialized) =
            UniswapV4SwapSimulator.loadState(stateView, poolId, false);
        if (!initialized) return (0, 0, false, false);

        UniswapV4SwapSimulator.Preview memory preview =
            UniswapV4SwapSimulator.previewExactInput(stateView, poolId, tickSpacing, false, amountIn, swapFee, state);
        return (preview.amountIn, preview.amountOut, preview.valid, preview.fullyFilled);
    }

    function quoteWithDirection(
        IUniswapV4StateView stateView,
        bytes32 poolId,
        int24 tickSpacing,
        bool zeroForOne,
        uint256 amountIn
    ) external view returns (uint256 amountConsumed, uint256 amountOut, bool valid, bool fullyFilled) {
        (UniswapV4SwapSimulator.State memory state, uint24 swapFee, bool initialized) =
            UniswapV4SwapSimulator.loadState(stateView, poolId, zeroForOne);
        if (!initialized) return (0, 0, false, false);

        UniswapV4SwapSimulator.Preview memory preview = UniswapV4SwapSimulator.previewExactInput(
            stateView, poolId, tickSpacing, zeroForOne, amountIn, swapFee, state
        );
        return (preview.amountIn, preview.amountOut, preview.valid, preview.fullyFilled);
    }
}

contract OracleTest is Test {
    using PoolIdLibrary for PoolKey;

    GroveCompounderAprOracle public oracle;
    V4SimulatorHarness public simulator;

    uint256 internal constant ORACLE_FORK_BLOCK = 25_668_920;

    IUniswapV4StateView internal constant STATE_VIEW = IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IV4Quoter internal constant V4_QUOTER = IV4Quoter(0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203);

    bytes32 internal constant POOL_ONE = 0x2897b6ccd757711791a90b723df4f89567568859d040ff97d25cc4a5cb93ea03;
    bytes32 internal constant POOL_TWO = 0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;
    bytes32 internal constant POOL_THREE = 0xb557b2447a4723741959fe7ebd5a37375023931d19f6383cc83bd0d9c8397bb9;
    bytes32 internal constant POOL_FOUR = 0x2e53ef1a957f41bfba562bac317881d6f0ef2d6c217c7279c11b0878f9791ad5;
    bytes32 internal constant POOL_FIVE = 0xaa0b1a90c6188f42c3603998536418f4eeedccf20b999377dab7e4c6aafc5286;
    bytes32 internal constant POOL_VOLUME = 0x20d117a32203158c46d0dce34ade2b2cbf846d151e9cea406e0463fe361d82ce;
    bytes32 internal constant POOL_KYBER = 0x0d40eef4d9600a37016f34d089705e83d8d9e40ac80838abb04a278fa049e874;
    bytes32 internal constant POOL_KYBER_TWO = 0x31c6aeb8a664ed9ef2ec68791e7043e1aee1481ab4507b227b179072c9e4871b;
    bytes32 internal constant POOL_KYBER_USDT = 0xde47849dd91a1d9b90a775776ae012cfc6eb2eb2ce0fe7c5be770038dd71ae4e;

    address internal constant GROVE = 0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal user = address(0xBEEF);

    function setUp() public {
        vm.rollFork(ORACLE_FORK_BLOCK);
        oracle = new GroveCompounderAprOracle();
        oracle.setUniV4Pools(_initialOraclePools());
        simulator = new V4SimulatorHarness();
    }

    function test_oracleDeploysWithoutPools() public {
        GroveCompounderAprOracle freshOracle = new GroveCompounderAprOracle();
        assertEq(freshOracle.management(), address(this));
        assertEq(freshOracle.uniV4PoolCount(), 0);
    }

    function test_oracleSetupPools() public {
        assertEq(oracle.management(), address(this));
        assertEq(oracle.uniV4PoolCount(), 6);
        assertEq(oracle.GROVE_PRICE_QUOTE_AMOUNT(), 10_000e18);
        assertEq(oracle.GROVE_PRICE_CHUNK_AMOUNT(), 1_000e18);
        assertEq(oracle.MAX_V4_POOLS(), 10);

        (bytes32 poolId, uint24 fee, int24 tickSpacing, address quoteToken, bool zeroForOne) = oracle.uniV4Pool(0);
        assertEq(poolId, POOL_FIVE);
        assertEq(fee, 49_900);
        assertEq(tickSpacing, 998);
        assertEq(quoteToken, USDC);
        assertFalse(zeroForOne);

        (poolId, fee, tickSpacing, quoteToken, zeroForOne) = oracle.uniV4Pool(1);
        assertEq(poolId, POOL_ONE);
        assertEq(fee, 10_000);
        assertEq(tickSpacing, 200);

        (poolId, fee, tickSpacing, quoteToken, zeroForOne) = oracle.uniV4Pool(2);
        assertEq(poolId, POOL_TWO);
        assertEq(fee, 49_800);
        assertEq(tickSpacing, 996);

        (poolId, fee, tickSpacing, quoteToken, zeroForOne) = oracle.uniV4Pool(3);
        assertEq(poolId, POOL_VOLUME);
        assertEq(fee, 49_898);
        assertEq(tickSpacing, 499);

        (poolId, fee, tickSpacing, quoteToken, zeroForOne) = oracle.uniV4Pool(4);
        assertEq(poolId, POOL_KYBER);
        assertEq(fee, 86_400);
        assertEq(tickSpacing, 10);

        (poolId, fee, tickSpacing, quoteToken, zeroForOne) = oracle.uniV4Pool(5);
        assertEq(poolId, POOL_KYBER_TWO);
        assertEq(fee, 101_300);
        assertEq(tickSpacing, 10);
    }

    function test_managementCanSetPools() public {
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = POOL_TWO;
        poolIds[1] = POOL_VOLUME;

        vm.prank(user);
        vm.expectRevert(GroveCompounderAprOracle.UnauthorizedPoolSetter.selector);
        oracle.setUniV4Pools(poolIds);

        oracle.setUniV4Pools(poolIds);
        assertEq(oracle.uniV4PoolCount(), 2);

        (bytes32 poolId,,,,) = oracle.uniV4Pool(0);
        assertEq(poolId, POOL_TWO);
        (poolId,,,,) = oracle.uniV4Pool(1);
        assertEq(poolId, POOL_VOLUME);

        poolIds[1] = POOL_TWO;
        vm.expectRevert(GroveCompounderAprOracle.DuplicatePool.selector);
        oracle.setUniV4Pools(poolIds);
    }

    function test_managementControlsPoolSetters() public {
        assertFalse(oracle.poolSetters(user));

        vm.prank(user);
        vm.expectRevert(GroveCompounderAprOracle.UnauthorizedManagement.selector);
        oracle.setPoolSetter(user, true);

        vm.expectRevert(GroveCompounderAprOracle.InvalidPoolSetter.selector);
        oracle.setPoolSetter(address(0), true);

        oracle.setPoolSetter(user, true);
        assertTrue(oracle.poolSetters(user));

        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = POOL_TWO;
        poolIds[1] = POOL_VOLUME;

        vm.prank(user);
        oracle.setUniV4Pools(poolIds);
        assertEq(oracle.uniV4PoolCount(), 2);

        oracle.setPoolSetter(user, false);
        assertFalse(oracle.poolSetters(user));

        vm.prank(user);
        vm.expectRevert(GroveCompounderAprOracle.UnauthorizedPoolSetter.selector);
        oracle.setUniV4Pools(poolIds);
    }

    function test_managementControlsPriceSetters() public {
        assertFalse(oracle.priceSetters(user));

        vm.prank(user);
        vm.expectRevert(GroveCompounderAprOracle.UnauthorizedManagement.selector);
        oracle.setPriceSetter(user, true);

        vm.expectRevert(GroveCompounderAprOracle.InvalidPriceSetter.selector);
        oracle.setPriceSetter(address(0), true);

        oracle.setPriceSetter(user, true);
        assertTrue(oracle.priceSetters(user));

        vm.prank(user);
        oracle.setGrovePrice(1e18);
        assertEq(oracle.storedGrovePrice(), 1e18);

        oracle.setPriceSetter(user, false);
        assertFalse(oracle.priceSetters(user));

        vm.prank(user);
        vm.expectRevert(GroveCompounderAprOracle.UnauthorizedPriceSetter.selector);
        oracle.setGrovePrice(1e18);
    }

    function test_cannotConfigureMoreThanMaximumPools() public {
        bytes32[] memory poolIds = new bytes32[](11);

        vm.expectRevert(GroveCompounderAprOracle.InvalidPoolCount.selector);
        oracle.setUniV4Pools(poolIds);
    }

    function test_rejectsZeroPoolId() public {
        vm.expectRevert(GroveCompounderAprOracle.InvalidPool.selector);
        oracle.setUniV4Pools(_singlePool(bytes32(0)));
    }

    function test_rejectsPoolWithWrongCurrencies() public {
        _mockPoolKey(POOL_ONE, address(0xBAD), GROVE, 10_000, 200, address(0));

        vm.expectRevert(GroveCompounderAprOracle.InvalidCurrencies.selector);
        oracle.setUniV4Pools(_singlePool(POOL_ONE));
    }

    function test_rejectsHookedPool() public {
        _mockPoolKey(POOL_ONE, USDC, GROVE, 10_000, 200, address(1));

        vm.expectRevert(GroveCompounderAprOracle.HookedPool.selector);
        oracle.setUniV4Pools(_singlePool(POOL_ONE));
    }

    function test_rejectsInvalidTickSpacing() public {
        _mockPoolKey(POOL_ONE, USDC, GROVE, 10_000, 0, address(0));

        vm.expectRevert(GroveCompounderAprOracle.InvalidTickSpacing.selector);
        oracle.setUniV4Pools(_singlePool(POOL_ONE));
    }

    function test_rejectsMismatchedPoolId() public {
        _mockPoolKey(POOL_ONE, USDC, GROVE, 10_001, 200, address(0));

        vm.expectRevert(GroveCompounderAprOracle.InvalidPoolId.selector);
        oracle.setUniV4Pools(_singlePool(POOL_ONE));
    }

    function test_rejectsUninitializedPool() public {
        _mockPoolKey(POOL_ONE, USDC, GROVE, 10_000, 200, address(0));
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, POOL_ONE),
            abi.encode(uint160(0), int24(0), uint24(0), uint24(10_000))
        );

        vm.expectRevert(GroveCompounderAprOracle.UninitializedPool.selector);
        oracle.setUniV4Pools(_singlePool(POOL_ONE));
    }

    function test_identicalPoolsSplitFiftyFifty() public {
        _setPoolCount(2);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);

        (
            uint256 totalAmountOut,
            uint256 amountAllocated,
            uint256 price,,
            uint256[] memory allocations,
            uint256[] memory outputs
        ) = oracle.quoteUniV4Route();

        assertEq(amountAllocated, 10_000e18);
        assertGt(totalAmountOut, 0);
        assertGt(price, 0);
        assertEq(allocations[0], 5_000e18);
        assertEq(allocations[1], 5_000e18);
        assertEq(outputs[0] + outputs[1], totalAmountOut);
    }

    function test_identicalThreePoolsUseAllPools() public {
        _setPoolCount(3);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);
        _mockIdenticalPool(POOL_THREE);

        (,, uint256 price,, uint256[] memory allocations,) = oracle.quoteUniV4Route();

        assertGt(price, 0);
        assertEq(allocations[0], 4_000e18);
        assertEq(allocations[1], 3_000e18);
        assertEq(allocations[2], 3_000e18);
    }

    function test_maximumPoolRouteStaysWithinGasBudget() public {
        uint256 poolCount = oracle.MAX_V4_POOLS();
        bytes32[] memory poolIds = new bytes32[](poolCount);
        uint24 fee = 10_000;
        int24 tickSpacing = 10;

        for (uint256 i; i < poolCount; ++i) {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(USDC),
                currency1: Currency.wrap(GROVE),
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: IHooks(address(0))
            });
            bytes32 poolId = PoolId.unwrap(key.toId());
            poolIds[i] = poolId;
            _mockPoolKey(poolId, USDC, GROVE, fee, tickSpacing, address(0));
            _mockPool(poolId, uint160(1 << 96), 0, 1e24, fee);
            ++fee;
            ++tickSpacing;
        }
        oracle.setUniV4Pools(poolIds);

        uint256 gasBefore = gasleft();
        (, uint256 amountAllocated, uint256 price,,,) = oracle.quoteUniV4Route();
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(amountAllocated, oracle.GROVE_PRICE_QUOTE_AMOUNT());
        assertGt(price, 0);
        assertLt(gasUsed, 10_000_000, "route gas");
    }

    function test_simulatorAppliesOneForZeroProtocolFee() public {
        uint24 lpFee = 10_000;
        uint24 packedProtocolFee = (uint24(500) << 12) | uint24(200);
        _mockPoolWithProtocolFee(POOL_THREE, packedProtocolFee, lpFee);
        _mockPool(POOL_FOUR, uint160(1 << 96), 0, 1e24, lpFee);

        (uint24 swapFee, bool initialized) = simulator.loadSwapFee(STATE_VIEW, POOL_THREE);
        assertTrue(initialized);
        assertEq(swapFee, 10_495);

        (uint256 consumedWithFee, uint256 outputWithFee, bool validWithFee, bool filledWithFee) =
            simulator.quote(STATE_VIEW, POOL_THREE, 10, 1_000e18);
        (uint256 consumedWithoutFee, uint256 outputWithoutFee, bool validWithoutFee, bool filledWithoutFee) =
            simulator.quote(STATE_VIEW, POOL_FOUR, 10, 1_000e18);

        assertTrue(validWithFee && filledWithFee);
        assertTrue(validWithoutFee && filledWithoutFee);
        assertEq(consumedWithFee, 1_000e18);
        assertEq(consumedWithoutFee, 1_000e18);
        assertLt(outputWithFee, outputWithoutFee);
    }

    function test_finitePoolCapacitiesAreCombinedToFillQuote() public {
        _setPoolCount(2);
        _mockFinitePool(POOL_ONE, 200, 542e21, 10_000);
        _mockFinitePool(POOL_TWO, 996, 103e21, 49_800);

        (
            uint256 totalAmountOut,
            uint256 amountAllocated,
            uint256 price,,
            uint256[] memory allocations,
            uint256[] memory outputs
        ) = oracle.quoteUniV4Route();

        assertEq(amountAllocated, 10_000e18);
        assertGt(totalAmountOut, 0);
        assertGt(price, 0);
        assertGt(allocations[0], 0);
        assertGt(allocations[1], 0);
        assertLt(allocations[0], 10_000e18);
        assertLt(allocations[1], 10_000e18);
        assertEq(allocations[0] + allocations[1], 10_000e18);
        assertEq(outputs[0] + outputs[1], totalAmountOut);
    }

    function test_firstChunkPriceOutlierIsExcluded() public {
        _setPoolCount(3);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);
        _mockPool(POOL_THREE, uint160((uint256(1 << 96) * 120) / 100), 0, 1e24, 10_000);

        (,,,, uint256[] memory allocations,) = oracle.quoteUniV4Route();

        assertEq(allocations[0], 5_000e18);
        assertEq(allocations[1], 5_000e18);
        assertEq(allocations[2], 0);
    }

    function test_twoDivergentPoolsAreNotBothRejected() public {
        _setPoolCount(2);
        _mockIdenticalPool(POOL_ONE);
        _mockPool(POOL_TWO, uint160((uint256(1 << 96) * 120) / 100), 0, 1e24, 10_000);

        (, uint256 amountAllocated, uint256 price,,,) = oracle.quoteUniV4Route();

        assertEq(amountAllocated, 10_000e18);
        assertGt(price, 0);
    }

    function test_incompleteRouteReturnsNoPriceAndZeroAprWithoutStoredPrice() public {
        _setPoolCount(1);
        _mockIncompletePool(POOL_ONE);

        (, uint256 amountAllocated, uint256 price,,,) = oracle.quoteUniV4Route();
        assertEq(amountAllocated, 0);
        assertEq(price, 0);

        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, 0);
        assertFalse(usingLivePrice);
        GroveCompounderAprOracle.GrovePriceStatus status;
        (selectedPrice, status) = oracle.grovePriceWithStatus();
        assertEq(selectedPrice, 0);
        assertEq(uint256(status), uint256(GroveCompounderAprOracle.GrovePriceStatus.Unavailable));

        _mockActiveRewards();
        assertEq(oracle.aprAfterDebtChange(address(0), 0), 0);
    }

    function test_onlyPriceSetterCanSetStoredPrice() public {
        vm.prank(user);
        vm.expectRevert(GroveCompounderAprOracle.UnauthorizedPriceSetter.selector);
        oracle.setGrovePrice(1e18);

        vm.expectRevert(GroveCompounderAprOracle.InvalidGrovePrice.selector);
        oracle.setGrovePrice(0);
    }

    function test_priceSetterStoresRawReferenceEvenWhenV4IsAvailable() public {
        _setMockedSinglePoolPrice(10_000);
        uint256 referencePrice = 0.0078e18;
        oracle.setGrovePrice(referencePrice);

        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(oracle.storedGrovePrice(), referencePrice);
        assertEq(oracle.lastPriceUpdate(), block.timestamp);
        assertEq(selectedPrice, referencePrice);
        assertFalse(usingLivePrice);
        (, GroveCompounderAprOracle.GrovePriceStatus status) = oracle.grovePriceWithStatus();
        assertEq(uint256(status), uint256(GroveCompounderAprOracle.GrovePriceStatus.FreshStoredPrice));
    }

    function test_freshStoredReferenceWinsThrough72Hours() public {
        uint256 referencePrice = 0.0078e18;
        oracle.setGrovePrice(referencePrice);
        uint256 livePrice = _setMockedSinglePoolPrice(10_000);
        assertTrue(livePrice != referencePrice);

        vm.warp(block.timestamp + oracle.STORED_PRICE_VALIDITY());
        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, referencePrice);
        assertFalse(usingLivePrice);
    }

    function test_validV4BecomesFallbackAfter72Hours() public {
        uint256 livePrice = _setMockedSinglePoolPrice(10_000);
        uint256 referencePrice = livePrice + ((livePrice * 1_000) / 10_000);
        oracle.setGrovePrice(referencePrice);

        vm.warp(block.timestamp + oracle.STORED_PRICE_VALIDITY() + 1);
        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, livePrice);
        assertTrue(usingLivePrice);
        (, GroveCompounderAprOracle.GrovePriceStatus status) = oracle.grovePriceWithStatus();
        assertEq(uint256(status), uint256(GroveCompounderAprOracle.GrovePriceStatus.LiveV4));
    }

    function test_outOfBoundsV4UsesStoredFallback() public {
        uint256 referencePrice = _setMockedSinglePoolPrice(10_000);
        oracle.setGrovePrice(referencePrice);
        _mockPool(POOL_ONE, uint160(uint256(1 << 96) * 2), 0, 1e24, 10_000);
        (,, uint256 livePrice,,,) = oracle.quoteUniV4Route();
        assertGt(_deviationBps(livePrice, referencePrice), oracle.MAX_LIVE_PRICE_DEVIATION_BPS());

        vm.warp(block.timestamp + oracle.STORED_PRICE_VALIDITY() + 1);

        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, referencePrice);
        assertFalse(usingLivePrice);
    }

    function test_unavailableV4KeepsFullStoredPriceThroughDaySeven() public {
        uint256 referencePrice = 0.0078e18;
        oracle.setGrovePrice(referencePrice);
        _setPoolCount(1);
        _mockIncompletePool(POOL_ONE);

        vm.warp(block.timestamp + oracle.STORED_PRICE_DECAY_START());
        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, referencePrice);
        assertFalse(usingLivePrice);
        (, GroveCompounderAprOracle.GrovePriceStatus status) = oracle.grovePriceWithStatus();
        assertEq(uint256(status), uint256(GroveCompounderAprOracle.GrovePriceStatus.StaleStoredPrice));
    }

    function test_storedPriceDecaysLinearlyFromDaySevenToDayFourteen() public {
        uint256 referencePrice = 0.008e18;
        oracle.setGrovePrice(referencePrice);
        _setPoolCount(1);
        _mockIncompletePool(POOL_ONE);

        vm.warp(block.timestamp + 10 days + 12 hours);
        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, referencePrice / 2);
        assertFalse(usingLivePrice);
        (, GroveCompounderAprOracle.GrovePriceStatus status) = oracle.grovePriceWithStatus();
        assertEq(uint256(status), uint256(GroveCompounderAprOracle.GrovePriceStatus.DecayingStoredPrice));
    }

    function test_storedPriceIsZeroAtDayFourteenWithoutV4() public {
        oracle.setGrovePrice(0.008e18);
        _setPoolCount(1);
        _mockIncompletePool(POOL_ONE);

        vm.warp(block.timestamp + oracle.STORED_PRICE_DECAY_END());
        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, 0);
        assertFalse(usingLivePrice);
        (, GroveCompounderAprOracle.GrovePriceStatus status) = oracle.grovePriceWithStatus();
        assertEq(uint256(status), uint256(GroveCompounderAprOracle.GrovePriceStatus.Unavailable));

        _mockActiveRewards();
        assertEq(oracle.aprAfterDebtChange(address(0), 0), 0);
    }

    function test_validV4StillWorksAfterDayFourteen() public {
        uint256 livePrice = _setMockedSinglePoolPrice(10_000);
        oracle.setGrovePrice(livePrice);
        vm.warp(block.timestamp + oracle.STORED_PRICE_DECAY_END());

        (uint256 selectedPrice, bool usingLivePrice) = oracle.grovePrice();
        assertEq(selectedPrice, livePrice);
        assertTrue(usingLivePrice);
    }

    function test_aprUsesSplitRoutePriceAndRemainsStaticCallable() public {
        _setPoolCount(2);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);
        _mockActiveRewards();

        (,, uint256 price,,,) = oracle.quoteUniV4Route();
        oracle.setGrovePrice(price);
        uint256 expectedApr = (1e18 * 31_536_000 * price) / 1e50;

        (bool success, bytes memory data) = address(oracle)
            .staticcall(abi.encodeWithSelector(oracle.aprAfterDebtChange.selector, address(0), int256(0)));
        assertTrue(success);
        assertEq(abi.decode(data, (uint256)), expectedApr);
    }

    function test_aprWorksThroughYearnRegistryStaticCall() public {
        _setPoolCount(2);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);
        _mockActiveRewards();
        (,, uint256 price,,,) = oracle.quoteUniV4Route();
        oracle.setGrovePrice(price);

        address strategy = address(0x1234);
        AprOracle registry = new AprOracle(address(this));
        registry.setOracle(strategy, address(oracle));

        assertEq(registry.getStrategyApr(strategy, 0), oracle.aprAfterDebtChange(strategy, 0));
    }

    function test_aprRespondsToDebtChanges() public {
        _setPoolCount(2);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);
        _mockActiveRewards();
        (,, uint256 price,,,) = oracle.quoteUniV4Route();
        oracle.setGrovePrice(price);

        uint256 currentApr = oracle.aprAfterDebtChange(address(0), 0);
        uint256 lowerDebtApr = oracle.aprAfterDebtChange(address(0), -1e49);
        uint256 higherDebtApr = oracle.aprAfterDebtChange(address(0), 1e49);

        assertGt(lowerDebtApr, currentApr);
        assertLt(higherDebtApr, currentApr);
    }

    function test_aprCapStillApplies() public {
        _setPoolCount(2);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);
        _mockActiveRewards();
        (,, uint256 price,,,) = oracle.quoteUniV4Route();
        oracle.setGrovePrice(price);
        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.totalSupply.selector), abi.encode(uint256(1e18)));

        vm.expectRevert(GroveCompounderAprOracle.AprTooHigh.selector);
        oracle.aprAfterDebtChange(address(0), 0);
    }

    function test_aprReturnsZeroAtPeriodFinish() public {
        vm.mockCall(
            oracle.STAKING(), abi.encodeWithSelector(IStaking.periodFinish.selector), abi.encode(block.timestamp)
        );

        assertEq(oracle.aprAfterDebtChange(address(0), 0), 0);
    }

    function test_singlePoolSimulatorMatchesOfficialV4Quoter() public {
        _assertSimulatorMatchesOfficialV4Quoter(POOL_TWO, 49_800, 996, 0.01e18);
    }

    function test_currentKyberPoolMatchesOfficialV4Quoter() public {
        _assertSimulatorMatchesOfficialV4Quoter(POOL_KYBER_TWO, USDC, GROVE, 101_300, 10, false, 1_000e18);
    }

    function test_currentUsdtPoolMatchesOfficialV4Quoter() public {
        vm.rollFork(25_761_300);
        simulator = new V4SimulatorHarness();
        _assertSimulatorMatchesOfficialV4Quoter(POOL_KYBER_USDT, GROVE, USDT, 8_000, 80, true, 10_000e18);
    }

    function test_simulatorFindsLiquidityBeyondAnEmptyCurrentRange() public {
        uint128 nextRangeLiquidity = 1e24;
        int128 nextRangeLiquidityDelta = 1e24;
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, POOL_ONE),
            abi.encode(uint160(1 << 96), int24(0), uint24(0), uint24(10_000))
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getLiquidity.selector, POOL_ONE),
            abi.encode(uint128(0))
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, POOL_ONE, int16(0)),
            abi.encode(uint256(1 << 1))
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickLiquidity.selector, POOL_ONE, int24(200)),
            abi.encode(nextRangeLiquidity, nextRangeLiquidityDelta)
        );

        (uint256 amountConsumed, uint256 amountOut, bool valid, bool fullyFilled) =
            simulator.quote(STATE_VIEW, POOL_ONE, 200, 1_000e18);

        assertTrue(valid);
        assertTrue(fullyFilled);
        assertEq(amountConsumed, 1_000e18);
        assertGt(amountOut, 0);
    }

    function test_simulatorFinalizesFillOnLastPermittedStep() public {
        _mockLiquidityAtWord(POOL_THREE, 126, 1e24);

        (uint256 amountConsumed, uint256 amountOut, bool valid, bool fullyFilled) =
            simulator.quote(STATE_VIEW, POOL_THREE, 1, 1e18);

        assertTrue(valid);
        assertTrue(fullyFilled);
        assertEq(amountConsumed, 1e18);
        assertGt(amountOut, 0);
    }

    function test_simulatorFinalizesPartialQuoteAtStepLimit() public {
        _mockLiquidityAtWord(POOL_THREE, 127, 1e24);

        (uint256 amountConsumed, uint256 amountOut, bool valid, bool fullyFilled) =
            simulator.quote(STATE_VIEW, POOL_THREE, 1, 1e18);

        assertTrue(valid);
        assertFalse(fullyFilled);
        assertEq(amountConsumed, 0);
        assertEq(amountOut, 0);
    }

    function test_forkRouteFillsQuote() public {
        (
            uint256 totalAmountOut,
            uint256 amountAllocated,
            uint256 price,
            bytes32[] memory poolIds,
            uint256[] memory allocations,
            uint256[] memory outputs
        ) = oracle.quoteUniV4Route();

        console2.log("V4 route USDC out", totalAmountOut);
        console2.log("V4 GROVE price", price);
        assertEq(amountAllocated, 10_000e18);
        assertGt(totalAmountOut, 0);
        assertGt(price, 0);
        assertEq(poolIds.length, 6);
        assertEq(allocations.length, 6);
        assertEq(outputs.length, 6);

        uint256 summedOutputs;
        for (uint256 i; i < outputs.length; ++i) {
            summedOutputs += outputs[i];
        }
        assertEq(totalAmountOut, summedOutputs);
    }

    function test_currentDeploymentPoolsFillQuote() public {
        vm.rollFork(25_761_300);
        GroveCompounderAprOracle currentOracle = new GroveCompounderAprOracle();

        bytes32[] memory poolIds = GroveUniV4PoolConfig.initialPools();
        currentOracle.setUniV4Pools(poolIds);

        (bytes32 configuredPool,,, address quoteToken, bool zeroForOne) = currentOracle.uniV4Pool(0);
        assertEq(configuredPool, POOL_KYBER_USDT);
        assertEq(quoteToken, USDT);
        assertTrue(zeroForOne);

        (uint256 totalAmountOut, uint256 amountAllocated, uint256 price,,,) = currentOracle.quoteUniV4Route();

        assertEq(amountAllocated, currentOracle.GROVE_PRICE_QUOTE_AMOUNT());
        assertGt(totalAmountOut, 78e6);
        assertLt(totalAmountOut, 80e6);
        assertGt(price, 78e14);
        assertLt(price, 80e14);
    }

    function _deviationBps(uint256 price, uint256 referencePrice) internal pure returns (uint256) {
        return (price > referencePrice ? price - referencePrice : referencePrice - price) * 10_000 / referencePrice;
    }

    function _setPoolCount(uint256 count) internal {
        bytes32[] memory poolIds = new bytes32[](count);
        poolIds[0] = POOL_ONE;
        if (count > 1) poolIds[1] = POOL_TWO;
        if (count > 2) poolIds[2] = POOL_THREE;
        if (count > 3) poolIds[3] = POOL_FOUR;
        oracle.setUniV4Pools(poolIds);
    }

    function _singlePool(bytes32 poolId) internal pure returns (bytes32[] memory poolIds) {
        poolIds = new bytes32[](1);
        poolIds[0] = poolId;
    }

    function _initialOraclePools() internal pure returns (bytes32[] memory poolIds) {
        poolIds = new bytes32[](6);
        poolIds[0] = POOL_FIVE;
        poolIds[1] = POOL_ONE;
        poolIds[2] = POOL_TWO;
        poolIds[3] = POOL_VOLUME;
        poolIds[4] = POOL_KYBER;
        poolIds[5] = POOL_KYBER_TWO;
    }

    function _mockIdenticalPool(bytes32 poolId) internal {
        _mockPool(poolId, uint160(1 << 96), 0, 1e24, 10_000);
    }

    function _setMockedSinglePoolPrice(uint24 lpFee) internal returns (uint256 price) {
        _setPoolCount(1);
        _mockPool(POOL_ONE, uint160(1 << 96), 0, 1e24, lpFee);
        (,, price,,,) = oracle.quoteUniV4Route();
        assertGt(price, 0);
    }

    function _mockIncompletePool(bytes32 poolId) internal {
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, poolId),
            abi.encode(uint160(0), int24(0), uint24(0), uint24(0))
        );
    }

    function _mockPoolKey(
        bytes32 poolId,
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) internal {
        vm.mockCall(
            address(oracle.UNISWAP_V4_POSITION_MANAGER()),
            // PositionManager indexes pool keys by the leading 25 bytes of the pool ID.
            // forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(IV4PositionManagerView.poolKeys.selector, bytes25(poolId)),
            abi.encode(currency0, currency1, fee, tickSpacing, hooks)
        );
    }

    function _mockPool(bytes32 poolId, uint160 sqrtPriceX96, int24 tick, uint128 liquidity, uint24 lpFee) internal {
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, poolId),
            abi.encode(sqrtPriceX96, tick, uint24(0), lpFee)
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getLiquidity.selector, poolId),
            abi.encode(liquidity)
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, poolId, int16(0)),
            abi.encode(uint256(0))
        );
    }

    function _mockPoolWithProtocolFee(bytes32 poolId, uint24 packedProtocolFee, uint24 lpFee) internal {
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, poolId),
            abi.encode(uint160(1 << 96), int24(0), packedProtocolFee, lpFee)
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getLiquidity.selector, poolId),
            abi.encode(uint128(1e24))
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, poolId, int16(0)),
            abi.encode(uint256(0))
        );
    }

    function _mockFinitePool(bytes32 poolId, int24 tickSpacing, uint128 liquidity, uint24 lpFee) internal {
        require(liquidity <= uint128(type(int128).max), "liquidity");
        _mockPool(poolId, uint160(1 << 96), 0, liquidity, lpFee);
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, poolId, int16(0)),
            abi.encode(uint256(1 << 1))
        );
        for (int16 wordPosition = 1; wordPosition <= 20; ++wordPosition) {
            vm.mockCall(
                address(STATE_VIEW),
                abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, poolId, wordPosition),
                abi.encode(uint256(0))
            );
        }
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickLiquidity.selector, poolId, tickSpacing),
            // The bound above makes this conversion lossless.
            // forge-lint: disable-next-line(unsafe-typecast)
            abi.encode(liquidity, -int128(liquidity))
        );
    }

    function _mockLiquidityAtWord(bytes32 poolId, int16 liquidityWord, uint128 liquidity) internal {
        require(liquidity <= uint128(type(int128).max), "liquidity");
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, poolId),
            abi.encode(uint160(1 << 96), int24(0), uint24(0), uint24(0))
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getLiquidity.selector, poolId),
            abi.encode(uint128(0))
        );
        for (int16 wordPosition; wordPosition < liquidityWord; ++wordPosition) {
            vm.mockCall(
                address(STATE_VIEW),
                abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, poolId, wordPosition),
                abi.encode(uint256(0))
            );
        }
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, poolId, liquidityWord),
            abi.encode(uint256(1) << 255)
        );
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickBitmap.selector, poolId, liquidityWord + 1),
            abi.encode(uint256(0))
        );

        int24 liquidityTick = (int24(liquidityWord) * 256) + 255;
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getTickLiquidity.selector, poolId, liquidityTick),
            // The bound above makes this conversion lossless.
            // forge-lint: disable-next-line(unsafe-typecast)
            abi.encode(liquidity, int128(liquidity))
        );
    }

    function _mockActiveRewards() internal {
        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.totalSupply.selector), abi.encode(uint256(1e50)));
        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.rewardRate.selector), abi.encode(uint256(1e18)));
        vm.mockCall(
            oracle.STAKING(),
            abi.encodeWithSelector(IStaking.periodFinish.selector),
            abi.encode(block.timestamp + 1 weeks)
        );
    }

    function _assertSimulatorMatchesOfficialV4Quoter(bytes32 poolId, uint24 fee, int24 tickSpacing, uint256 amountIn)
        internal
    {
        _assertSimulatorMatchesOfficialV4Quoter(poolId, USDC, GROVE, fee, tickSpacing, false, amountIn);
    }

    function _assertSimulatorMatchesOfficialV4Quoter(
        bytes32 poolId,
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        bool zeroForOne,
        uint256 amountIn
    ) internal {
        require(amountIn <= type(uint128).max, "amount in");
        (uint256 amountConsumed, uint256 simulatedOut, bool valid, bool fullyFilled) =
            simulator.quoteWithDirection(STATE_VIEW, poolId, tickSpacing, zeroForOne, amountIn);
        assertTrue(valid);
        assertTrue(fullyFilled);
        assertEq(amountConsumed, amountIn);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });
        (uint256 quotedOut,) = V4_QUOTER.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                // The bound above makes this conversion lossless.
                // forge-lint: disable-next-line(unsafe-typecast)
                exactAmount: uint128(amountIn),
                hookData: bytes("")
            })
        );

        assertEq(simulatedOut, quotedOut);
    }
}
