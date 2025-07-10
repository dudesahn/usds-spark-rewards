pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "src/test/utils/Setup.sol";

import {SparkCompounderAprOracle} from "src/periphery/SparkCompounderAprOracle.sol";

contract OracleTest is Setup {
    SparkCompounderAprOracle public oracle;

    uint256 public fuzzAmount;

    function setUp() public override {
        super.setUp();
        oracle = new SparkCompounderAprOracle();
    }

    function testSimpleOracleCheck() public {
        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        console2.log("currentAPR:", currentApr);
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
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));
        fuzzAmount = _amount;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

    // TODO: Deploy multiple strategies with different tokens as `asset` to test against the oracle.
}
