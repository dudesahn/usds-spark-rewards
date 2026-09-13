// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {GroveCompounder} from "src/GroveCompounder.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Dry run:
// forge script script/DeployStrategy.s.sol:DeployStrategy --rpc-url "$ETH_RPC_URL" --account llc2 -vvvvv --optimize true
//
// Broadcast:
// forge script script/DeployStrategy.s.sol:DeployStrategy --rpc-url "$ETH_RPC_URL" --account llc2 -vvvvv --optimize true --slow --broadcast
// Deployed for convertor for yvUSD: 0x47c640fDA687B7D20d50D4464e302e36D3D312Ed

/// @notice Deploys a new GroveCompounder strategy without deploying an APR oracle.
contract DeployStrategy is Script {
    function run() external {
        vm.startBroadcast();

        GroveCompounder strategy = new GroveCompounder();

        console2.log("-----------------------------");
        console2.log("strategy deployed at: %s", address(strategy));
        console2.log("auction deployed at: %s", strategy.auction());
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}
