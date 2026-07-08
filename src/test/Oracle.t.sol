pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "src/test/utils/Setup.sol";

import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";

interface IUniV3Router {
    function factory() external view returns (address);
}

interface IUniV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address);
}

contract OracleTest is Setup {
    bytes32 internal constant GROVE_USDC_V4_POOL_ID_TWO =
        0x813d0e6a7c95c0cc09a06c27e8320e783183356df1587b53e6fee33d1cd837d9;
    bytes32 internal constant GROVE_USDC_V4_POOL_ID_THREE =
        0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;

    GroveCompounderAprOracle public oracle;

    uint256 public fuzzAmount;

    function setUp() public override {
        super.setUp();
        oracle = new GroveCompounderAprOracle();
    }

    function test_oracleDefaults() public {
        assertEq(oracle.management(), address(this));
        assertEq(
            oracle.rewardToBaseUniV3Fee(),
            oracle.DEFAULT_REWARD_TO_BASE_UNI_V3_FEE()
        );
        assertEq(oracle.uniV3Pool(), GROVE_USDC_V3_POOL);
        assertEq(oracle.groveUsdcV4PoolId(), GROVE_USDC_V4_POOL_ID);
        assertTrue(!oracle.v4GroveIsToken0());
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
            abi.encodeWithSelector(
                IUniV3Factory.getPool.selector,
                oracle.GROVE(),
                oracle.USDC(),
                newFee
            ),
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

        assertEq(oracle.groveUsdcV4PoolId(), newPoolId);
        assertTrue(oracle.v4GroveIsToken0());
    }

    function test_oracleCanUseConfiguredV4PoolTwo() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_TWO);
    }

    function test_oracleCanUseConfiguredV4PoolThree() public {
        _checkConfiguredV4Pool(GROVE_USDC_V4_POOL_ID_THREE);
    }

    function testSimpleOracleCheck() public {
        if (!rewardPricingHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        console2.log("currentAPR:", currentApr);
    }

    function test_oracleCanUseV4Backup() public {
        _forceV4Pricing();

        if (!rewardV4PoolHasUsableLiquidity()) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");
    }

    function _checkConfiguredV4Pool(bytes32 _poolId) internal {
        oracle.setUniV4Pool(_poolId, false);
        assertEq(oracle.groveUsdcV4PoolId(), _poolId);
        assertTrue(!oracle.v4GroveIsToken0());

        _forceV4Pricing();

        if (!_v4PoolHasUsableLiquidity(_poolId)) {
            vm.expectRevert("insufficient pool liquidity");
            oracle.aprAfterDebtChange(address(strategy), 0);
            return;
        }

        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");
    }

    function _forceV4Pricing() internal {
        vm.mockCall(
            oracle.uniV3Pool(),
            abi.encodeWithSelector(bytes4(keccak256("liquidity()"))),
            abi.encode(uint128(0))
        );
    }

    function _v4PoolHasUsableLiquidity(
        bytes32 _poolId
    ) internal view returns (bool) {
        try UNISWAP_V4_STATE_VIEW.getLiquidity(_poolId) returns (
            uint128 liquidity
        ) {
            return liquidity >= MIN_REWARD_POOL_LIQUIDITY;
        } catch {
            return false;
        }
    }

    function checkOracle(address _strategy, uint256 _delta) public {
        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        // Should be greater than 0 but likely less than 100%
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");

        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            -int256(_delta)
        );

        // The apr should go up if deposits go down
        if (fuzzAmount < ORACLE_FUZZ_MIN) {
            assertLe(currentApr, negativeDebtChangeApr, "negative change");
        } else {
            assertLt(currentApr, negativeDebtChangeApr, "negative change");
        }

        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            int256(_delta)
        );

        // The apr should go down if deposits go up
        if (fuzzAmount < ORACLE_FUZZ_MIN) {
            assertGe(currentApr, positiveDebtChangeApr, "positive change");
        } else {
            assertGt(currentApr, positiveDebtChangeApr, "positive change");
        }
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
