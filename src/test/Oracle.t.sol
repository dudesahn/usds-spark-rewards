pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "src/test/utils/Setup.sol";

import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {IUniswapV4StateView} from "src/interfaces/IUniswapV4StateView.sol";

interface IUniV3Router {
    function factory() external view returns (address);
}

interface IUniV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

contract OracleTest is Setup {
    GroveCompounderAprOracle public oracle;

    uint256 public fuzzAmount;

    function setUp() public override {
        super.setUp();
        oracle = new GroveCompounderAprOracle();
    }

    function test_oracleDefaults() public {
        assertEq(oracle.management(), address(this));
        assertEq(oracle.rewardToBaseUniV3Fee(), oracle.DEFAULT_REWARD_TO_BASE_UNI_V3_FEE());
        assertEq(oracle.uniV3Pool(), GROVE_USDC_V3_POOL);
        assertEq(oracle.uniV4PoolCount(), 4);
        assertEq(oracle.groveUsdcV4PoolId(), GROVE_USDC_V4_POOL_ID);
        assertTrue(!oracle.v4GroveIsToken0());

        (bytes32 poolId, bool groveIsToken0) = oracle.uniV4Pool(0);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID);
        assertTrue(!groveIsToken0);

        (poolId, groveIsToken0) = oracle.uniV4Pool(1);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_TWO);
        assertTrue(!groveIsToken0);

        (poolId, groveIsToken0) = oracle.uniV4Pool(2);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_THREE);
        assertTrue(!groveIsToken0);

        (poolId, groveIsToken0) = oracle.uniV4Pool(3);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_FOUR);
        assertTrue(!groveIsToken0);
    }

    function test_managementCanUpdateUniV3Fee() public {
        uint24 newFee = 500;
        address factory = IUniV3Router(oracle.UNISWAP_V3_ROUTER()).factory();

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.setUniV3Fee(newFee);

        vm.expectRevert("!pool");
        oracle.setUniV3Fee(newFee);

        vm.mockCall(
            factory,
            abi.encodeWithSelector(IUniV3Factory.getPool.selector, oracle.GROVE(), oracle.USDC(), newFee),
            abi.encode(GROVE_USDC_V3_POOL)
        );

        oracle.setUniV3Fee(newFee);

        assertEq(oracle.rewardToBaseUniV3Fee(), newFee);
        assertEq(oracle.uniV3Pool(), GROVE_USDC_V3_POOL);
    }

    function test_managementCanUpdateUniV4Pool() public {
        bytes32 newPoolId = keccak256("new grove/usdc v4 pool");

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.setUniV4Pool(newPoolId, true);

        oracle.setUniV4Pool(newPoolId, true);

        assertEq(oracle.uniV4PoolCount(), 1);
        assertEq(oracle.groveUsdcV4PoolId(), newPoolId);
        assertTrue(oracle.v4GroveIsToken0());
    }

    function test_managementCanSetUniV4Pools() public {
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = GROVE_USDC_V4_POOL_ID_TWO;
        poolIds[1] = GROVE_USDC_V4_POOL_ID_THREE;

        bool[] memory groveIsToken0 = new bool[](2);
        groveIsToken0[0] = false;
        groveIsToken0[1] = true;

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        bool[] memory shortDirections = new bool[](1);
        vm.expectRevert("length");
        oracle.setUniV4Pools(poolIds, shortDirections);

        poolIds[1] = bytes32(0);
        vm.expectRevert("!pool");
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        poolIds[1] = poolIds[0];
        vm.expectRevert("duplicate");
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        poolIds[1] = GROVE_USDC_V4_POOL_ID_THREE;
        oracle.setUniV4Pools(poolIds, groveIsToken0);

        assertEq(oracle.uniV4PoolCount(), 2);

        (bytes32 poolId, bool isToken0) = oracle.uniV4Pool(0);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_TWO);
        assertTrue(!isToken0);

        (poolId, isToken0) = oracle.uniV4Pool(1);
        assertEq(poolId, GROVE_USDC_V4_POOL_ID_THREE);
        assertTrue(isToken0);
    }

    function test_managementCanAddAndRemoveUniV4Pool() public {
        bytes32 newPoolId = keccak256("new grove/usdc v4 pool");

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.addUniV4Pool(newPoolId, true);

        oracle.addUniV4Pool(newPoolId, true);

        assertEq(oracle.uniV4PoolCount(), 5);
        (bytes32 poolId, bool isToken0) = oracle.uniV4Pool(4);
        assertEq(poolId, newPoolId);
        assertTrue(isToken0);

        vm.expectRevert("duplicate");
        oracle.addUniV4Pool(newPoolId, true);

        vm.prank(user);
        vm.expectRevert("!management");
        oracle.removeUniV4Pool(3);

        oracle.removeUniV4Pool(4);
        assertEq(oracle.uniV4PoolCount(), 4);

        vm.expectRevert("!index");
        oracle.removeUniV4Pool(4);

        oracle.setUniV4Pool(newPoolId, true);
        vm.expectRevert("!pool");
        oracle.removeUniV4Pool(0);
    }

    function test_oracleSelectsMostLiquidConfiguredV4PoolNearMedian() public {
        bytes32[] memory poolIds = new bytes32[](3);
        poolIds[0] = GROVE_USDC_V4_POOL_ID;
        poolIds[1] = GROVE_USDC_V4_POOL_ID_TWO;
        poolIds[2] = GROVE_USDC_V4_POOL_ID_FOUR;

        bool[] memory groveIsToken0 = new bool[](3);
        groveIsToken0[0] = false;
        groveIsToken0[1] = false;
        groveIsToken0[2] = false;

        oracle.setUniV4Pools(poolIds, groveIsToken0);

        uint128 outlierLiquidity = 10e12;
        uint128 selectedLiquidity = 5e12;

        _mockV4Pool(poolIds[0], outlierLiquidity, 453061755611786389487367678109067002);
        _mockV4Pool(poolIds[1], selectedLiquidity, 487958752947811275626586785558519091);
        _mockV4Pool(poolIds[2], 3e12, 490481118378931851683740558437355049);

        (bytes32 bestPoolId, bool isToken0, uint128 liquidity) = oracle.bestUniV4Pool();

        assertEq(bestPoolId, poolIds[1]);
        assertTrue(!isToken0);
        assertEq(liquidity, selectedLiquidity);

        uint256 price;
        (bestPoolId, isToken0, liquidity, price) = oracle.selectedUniV4Pool();

        assertEq(bestPoolId, poolIds[1]);
        assertTrue(!isToken0);
        assertEq(liquidity, selectedLiquidity);
        assertEq(price, 26_362_000_000_000_000);
    }

    function test_oracleCanUseConfiguredV4PoolTwo() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_TWO);
    }

    function test_oracleCanUseConfiguredV4PoolThree() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_THREE);
    }

    function test_oracleCanUseConfiguredV4PoolFour() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_FOUR);
    }

    function testSimpleOracleCheck() public {
        if (!rewardPricingHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        console2.log("currentAPR:", currentApr);
        _assertReasonableApr(currentApr);
    }

    function test_oracleCanUseV4Backup() public {
        _forceV4Pricing();

        if (!rewardV4PoolHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        _assertReasonableApr(currentApr);
    }

    function test_oracleRevertsWhenAprAboveCap() public {
        bytes32 poolId = keccak256("mock grove/usdc v4 pool");
        oracle.setUniV4Pool(poolId, false);

        _forceV4Pricing();
        _mockV4Pool(poolId, 5e12, 487958752947811275626586785558519091);

        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.totalSupply.selector), abi.encode(1e18));
        vm.mockCall(oracle.STAKING(), abi.encodeWithSelector(IStaking.rewardRate.selector), abi.encode(1e18));
        vm.mockCall(
            oracle.STAKING(),
            abi.encodeWithSelector(IStaking.periodFinish.selector),
            abi.encode(block.timestamp + 1 weeks)
        );

        vm.expectRevert("apr too high");
        oracle.aprAfterDebtChange(address(strategy), 0);
    }

    function _checkConfiguredV4Pool(bytes32 _poolId) internal {
        oracle.setUniV4Pool(_poolId, false);
        assertEq(oracle.uniV4PoolCount(), 1);
        assertEq(oracle.groveUsdcV4PoolId(), _poolId);
        assertTrue(!oracle.v4GroveIsToken0());

        _forceV4Pricing();

        if (!_v4PoolHasUsableLiquidity(_poolId)) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        _assertReasonableApr(currentApr);
    }

    function _forceV4Pricing() internal {
        vm.mockCall(
            oracle.uniV3Pool(), abi.encodeWithSelector(bytes4(keccak256("liquidity()"))), abi.encode(uint128(0))
        );
    }

    function _mockV4Pool(bytes32 _poolId, uint128 _liquidity) internal {
        _mockV4Pool(_poolId, _liquidity, uint160(1 << 96));
    }

    function _mockV4Pool(bytes32 _poolId, uint128 _liquidity, uint160 _sqrtPriceX96) internal {
        vm.mockCall(
            address(UNISWAP_V4_STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getLiquidity.selector, _poolId),
            abi.encode(_liquidity)
        );

        vm.mockCall(
            address(UNISWAP_V4_STATE_VIEW),
            abi.encodeWithSelector(IUniswapV4StateView.getSlot0.selector, _poolId),
            abi.encode(_sqrtPriceX96, int24(0), uint24(0), uint24(0))
        );
    }

    function checkOracle(address _strategy, uint256 _delta) public {
        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        _assertReasonableApr(currentApr);

        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(_strategy, -int256(_delta));
        _assertReasonableApr(negativeDebtChangeApr);

        // The apr should go up if deposits go down
        if (fuzzAmount < ORACLE_FUZZ_MIN) {
            assertLe(currentApr, negativeDebtChangeApr, "negative change");
        } else {
            assertLt(currentApr, negativeDebtChangeApr, "negative change");
        }

        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(_strategy, int256(_delta));
        _assertReasonableApr(positiveDebtChangeApr);

        // The apr should go down if deposits go up
        if (fuzzAmount < ORACLE_FUZZ_MIN) {
            assertGe(currentApr, positiveDebtChangeApr, "positive change");
        } else {
            assertGt(currentApr, positiveDebtChangeApr, "positive change");
        }
    }

    function _assertReasonableApr(uint256 _apr) internal {
        assertGt(_apr, 0, "ZERO");
        assertLe(_apr, oracle.MAX_EXPECTED_APR(), "+50%");
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        if (!rewardPricingHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));
        fuzzAmount = _amount;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

    // TODO: Deploy multiple strategies with different tokens as `asset` to test against the oracle.
}
