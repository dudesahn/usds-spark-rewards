// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {SparkCompounder} from "src/SparkCompounder.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Dry run:
// forge script script/spark/DeploySparkStrategy.s.sol:DeploySparkStrategy --rpc-url "$PUBLICNODE_ETH_RPC_URL" --account llc2
// Add --broadcast only when intentionally deploying a new strategy.
// Uses Spark's existing constructor defaults: closed deposits and UniV3 reward sales.
// Configure management roles and an auction separately if enabling auction sales.

contract DeploySparkStrategy is Script {
    function run() external {
        vm.startBroadcast();
        SparkCompounder strategy = new SparkCompounder();
        vm.stopBroadcast();
        console2.log("Spark strategy deployed at:", address(strategy));
    }
}
