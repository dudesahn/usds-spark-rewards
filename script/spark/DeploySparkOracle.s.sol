// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {SparkCompounderAprOracle} from "src/periphery/SparkCompounderAprOracle.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Dry run:
// forge script script/spark/DeploySparkOracle.s.sol:DeploySparkOracle --rpc-url "$PUBLICNODE_ETH_RPC_URL" --account llc2
// Add --broadcast only when intentionally deploying a new oracle.
// Existing Spark strategy: 0xc9f01b5c6048B064E6d925d1c2d7206d4fEeF8a3
// Existing v2 APR oracle: 0x1a5579C4fBcC89Cc8ae46D551C53d7cecc9bD046

contract DeploySparkOracle is Script {
    function run() external {
        vm.startBroadcast();
        SparkCompounderAprOracle oracle = new SparkCompounderAprOracle();
        vm.stopBroadcast();
        console2.log("Spark APR oracle deployed at:", address(oracle));
    }
}
