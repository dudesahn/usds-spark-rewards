// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";
import {UniswapV4SwapSimulator} from "src/libraries/UniswapV4SwapSimulator.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
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

contract V4SimulatorHarness {
    function quote(IUniswapV4StateView stateView, bytes32 poolId, int24 tickSpacing, uint256 amountIn)
        external
        view
        returns (uint256 amountConsumed, uint256 amountOut, bool fullyFilled)
    {
        (UniswapV4SwapSimulator.State memory state, uint24 swapFee, bool initialized) =
            UniswapV4SwapSimulator.loadState(stateView, poolId, false);
        if (!initialized) return (0, 0, false);

        UniswapV4SwapSimulator.Preview memory preview =
            UniswapV4SwapSimulator.previewExactInput(stateView, poolId, tickSpacing, false, amountIn, swapFee, state);
        return (preview.amountIn, preview.amountOut, preview.fullyFilled);
    }
}

contract OracleTest is Test {
    GroveCompounderAprOracle public oracle;
    V4SimulatorHarness public simulator;

    uint256 internal constant ORACLE_FORK_BLOCK = 25_648_904;

    IUniswapV4StateView internal constant STATE_VIEW = IUniswapV4StateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IV4Quoter internal constant V4_QUOTER = IV4Quoter(0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203);

    bytes32 internal constant POOL_ONE = 0x2897b6ccd757711791a90b723df4f89567568859d040ff97d25cc4a5cb93ea03;
    bytes32 internal constant POOL_TWO = 0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;
    bytes32 internal constant POOL_THREE = 0xb557b2447a4723741959fe7ebd5a37375023931d19f6383cc83bd0d9c8397bb9;
    bytes32 internal constant POOL_FOUR = 0x2e53ef1a957f41bfba562bac317881d6f0ef2d6c217c7279c11b0878f9791ad5;
    bytes32 internal constant POOL_FIVE = 0xaa0b1a90c6188f42c3603998536418f4eeedccf20b999377dab7e4c6aafc5286;
    bytes32 internal constant POOL_VOLUME = 0x20d117a32203158c46d0dce34ade2b2cbf846d151e9cea406e0463fe361d82ce;
    bytes32 internal constant POOL_KYBER = 0x0d40eef4d9600a37016f34d089705e83d8d9e40ac80838abb04a278fa049e874;

    address internal constant GROVE = 0xB30FE1Cf884B48a22a50D22a9282004F2c5E9406;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal user = address(0xBEEF);

    function setUp() public {
        vm.rollFork(ORACLE_FORK_BLOCK);
        oracle = new GroveCompounderAprOracle();
        simulator = new V4SimulatorHarness();
    }

    function test_oracleDefaults() public {
        assertEq(oracle.management(), address(this));
        assertEq(oracle.uniV4PoolCount(), 5);
        assertEq(oracle.GROVE_PRICE_QUOTE_AMOUNT(), 10_000e18);
        assertEq(oracle.GROVE_PRICE_CHUNK_AMOUNT(), 1_000e18);
        assertEq(oracle.GROVE_PRICE_CHUNK_COUNT(), 10);
        assertEq(oracle.MAX_V4_POOLS(), 10);

        (bytes32 poolId, uint24 fee, int24 tickSpacing) = oracle.uniV4Pool(0);
        assertEq(poolId, POOL_FIVE);
        assertEq(fee, 49_900);
        assertEq(tickSpacing, 998);

        (poolId, fee, tickSpacing) = oracle.uniV4Pool(1);
        assertEq(poolId, POOL_ONE);
        assertEq(fee, 10_000);
        assertEq(tickSpacing, 200);

        (poolId, fee, tickSpacing) = oracle.uniV4Pool(2);
        assertEq(poolId, POOL_TWO);
        assertEq(fee, 49_800);
        assertEq(tickSpacing, 996);

        (poolId, fee, tickSpacing) = oracle.uniV4Pool(3);
        assertEq(poolId, POOL_VOLUME);
        assertEq(fee, 49_898);
        assertEq(tickSpacing, 499);

        (poolId, fee, tickSpacing) = oracle.uniV4Pool(4);
        assertEq(poolId, POOL_KYBER);
        assertEq(fee, 86_400);
        assertEq(tickSpacing, 10);
    }

    function test_managementCanSetPools() public {
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = POOL_TWO;
        poolIds[1] = POOL_VOLUME;

        vm.prank(user);
        vm.expectRevert("!pool setter");
        oracle.setUniV4Pools(poolIds);

        oracle.setUniV4Pools(poolIds);
        assertEq(oracle.uniV4PoolCount(), 2);

        (bytes32 poolId,,) = oracle.uniV4Pool(0);
        assertEq(poolId, POOL_TWO);
        (poolId,,) = oracle.uniV4Pool(1);
        assertEq(poolId, POOL_VOLUME);

        poolIds[1] = POOL_TWO;
        vm.expectRevert("duplicate");
        oracle.setUniV4Pools(poolIds);
    }

    function test_managementCanAddAndRemovePool() public {
        oracle.addUniV4Pool(POOL_THREE);
        assertEq(oracle.uniV4PoolCount(), 6);

        vm.expectRevert("duplicate");
        oracle.addUniV4Pool(POOL_THREE);

        vm.prank(user);
        vm.expectRevert("!pool setter");
        oracle.removeUniV4Pool(5);

        oracle.removeUniV4Pool(5);
        assertEq(oracle.uniV4PoolCount(), 5);

        oracle.addUniV4Pool(POOL_THREE);
        assertEq(oracle.uniV4PoolCount(), 6);

        oracle.setUniV4Pool(POOL_TWO);
        vm.expectRevert("!pool");
        oracle.removeUniV4Pool(0);
    }

    function test_managementControlsPoolSetters() public {
        assertFalse(oracle.poolSetters(user));

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.setPoolSetter(user, true);

        vm.expectRevert("!pool setter");
        oracle.setPoolSetter(address(0), true);

        oracle.setPoolSetter(user, true);
        assertTrue(oracle.poolSetters(user));

        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = POOL_TWO;
        poolIds[1] = POOL_VOLUME;

        vm.prank(user);
        oracle.setUniV4Pools(poolIds);
        assertEq(oracle.uniV4PoolCount(), 2);

        vm.prank(user);
        oracle.addUniV4Pool(POOL_KYBER);
        assertEq(oracle.uniV4PoolCount(), 3);

        vm.prank(user);
        oracle.removeUniV4Pool(2);
        assertEq(oracle.uniV4PoolCount(), 2);

        oracle.setPoolSetter(user, false);
        assertFalse(oracle.poolSetters(user));

        vm.prank(user);
        vm.expectRevert("!pool setter");
        oracle.addUniV4Pool(POOL_KYBER);
    }

    function test_cannotConfigureMoreThanMaximumPools() public {
        bytes32[] memory poolIds = new bytes32[](11);

        vm.expectRevert("length");
        oracle.setUniV4Pools(poolIds);
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

    function test_incompleteRouteReturnsNoPriceAndAprReverts() public {
        _setPoolCount(1);
        vm.mockCall(
            address(STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, POOL_TWO),
            abi.encode(uint160(0), int24(0), uint24(0), uint24(0))
        );

        (, uint256 amountAllocated, uint256 price,,,) = oracle.quoteUniV4Route();
        assertEq(amountAllocated, 0);
        assertEq(price, 0);

        _mockActiveRewards();
        vm.expectRevert("insufficient pool liquidity");
        oracle.aprAfterDebtChange(address(0), 0);
    }

    function test_aprUsesSplitRoutePriceAndRemainsStaticCallable() public {
        _setPoolCount(2);
        _mockIdenticalPool(POOL_ONE);
        _mockIdenticalPool(POOL_TWO);
        _mockActiveRewards();

        (,, uint256 price,,,) = oracle.quoteUniV4Route();
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
        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.totalSupply.selector), abi.encode(uint256(1e18)));

        vm.expectRevert("apr too high");
        oracle.aprAfterDebtChange(address(0), 0);
    }

    function test_singlePoolSimulatorMatchesOfficialV4Quoter() public {
        _assertSimulatorMatchesOfficialV4Quoter(POOL_TWO, 49_800, 996, 0.01e18);
    }

    function test_kyberPoolsMatchOfficialV4Quoter() public {
        _assertSimulatorMatchesOfficialV4Quoter(POOL_VOLUME, 49_898, 499, 1_000e18);
        _assertSimulatorMatchesOfficialV4Quoter(POOL_KYBER, 86_400, 10, 1_000e18);
    }

    function test_simulatorFindsLiquidityBeyondAnEmptyCurrentRange() public {
        uint128 nextRangeLiquidity = 1e24;
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
            abi.encode(nextRangeLiquidity, int128(nextRangeLiquidity))
        );

        (uint256 amountConsumed, uint256 amountOut, bool fullyFilled) =
            simulator.quote(STATE_VIEW, POOL_ONE, 200, 1_000e18);

        assertTrue(fullyFilled);
        assertEq(amountConsumed, 1_000e18);
        assertGt(amountOut, 0);
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
        assertEq(poolIds.length, 5);
        assertEq(allocations.length, 5);
        assertEq(outputs.length, 5);
        assertEq(totalAmountOut, outputs[0] + outputs[1] + outputs[2] + outputs[3] + outputs[4]);
    }

    function _setPoolCount(uint256 count) internal {
        bytes32[] memory poolIds = new bytes32[](count);
        poolIds[0] = POOL_ONE;
        if (count > 1) poolIds[1] = POOL_TWO;
        if (count > 2) poolIds[2] = POOL_THREE;
        if (count > 3) poolIds[3] = POOL_FOUR;
        oracle.setUniV4Pools(poolIds);
    }

    function _mockIdenticalPool(bytes32 poolId) internal {
        _mockPool(poolId, uint160(1 << 96), 0, 1e24, 10_000);
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

    function _mockFinitePool(bytes32 poolId, int24 tickSpacing, uint128 liquidity, uint24 lpFee) internal {
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
            abi.encode(liquidity, -int128(liquidity))
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
        (uint256 amountConsumed, uint256 simulatedOut, bool fullyFilled) =
            simulator.quote(STATE_VIEW, poolId, tickSpacing, amountIn);
        assertTrue(fullyFilled);
        assertEq(amountConsumed, amountIn);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(GROVE),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });
        (uint256 quotedOut,) = V4_QUOTER.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey, zeroForOne: false, exactAmount: uint128(amountIn), hookData: bytes("")
            })
        );

        assertEq(simulatedOut, quotedOut);
    }
}
