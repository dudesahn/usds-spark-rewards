// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";
import {GroveUniV4PoolConfig} from "script/GroveUniV4PoolConfig.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Verify the generated pool snapshot before deployment:
// python3 scripts/generate_grove_pool_config.py --check
//
// Dry run:
// forge script script/DeployOracleV2.s.sol:DeployOracleV2 --rpc-url "$ETH_RPC_URL" --account llc2 -vvvvv --optimize true
//
// Broadcast:
// forge script script/DeployOracleV2.s.sol:DeployOracleV2 --rpc-url "$ETH_RPC_URL" --account llc2 -vvvvv --optimize true --slow --broadcast

/// @notice Deploys only the replacement APR oracle. The existing strategy is reused.
/// @dev After deployment, register the new oracle for the existing strategy in
///      Yearn's APR oracle and update MAINNET_GROVE_APR_ORACLE in the maintenance
///      script defaults. Until a Kyber reference is submitted, the oracle uses V4.
contract DeployOracleV2 is Script {
    function run() external {
        vm.startBroadcast();

        GroveCompounderAprOracle aprOracle = new GroveCompounderAprOracle();
        aprOracle.setUniV4Pools(GroveUniV4PoolConfig.initialPools());

        console2.log("-----------------------------");
        console2.log("v2 apr oracle deployed at: %s", address(aprOracle));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}
