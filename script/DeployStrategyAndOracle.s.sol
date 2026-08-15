// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";
import {GroveCompounder} from "src/GroveCompounder.sol";
import {GroveUniV4PoolConfig} from "script/GroveUniV4PoolConfig.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// ---- Usage ----
// First verify that the generated deployment snapshot matches its JSON source:
// python3 scripts/generate_grove_pool_config.py --check
//
// forge script script/DeployStrategyAndOracle.s.sol:DeployStrategyAndOracle --rpc-url "$ETH_RPC_URL" --account llc2 -vvvvv --optimize true

// do real deployment, try slow to see if that helps w/ verification
// forge script script/DeployStrategyAndOracle.s.sol:DeployStrategyAndOracle --rpc-url "$ETH_RPC_URL" --account llc2 -vvvvv --optimize true --etherscan-api-key $ETHERSCAN_TOKEN --slow --verify --broadcast

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// no constructor (or thus, constructor args) on this one
// forge verify-contract --rpc-url "$ETH_RPC_URL" --watch --etherscan-api-key $ETHERSCAN_TOKEN "0x1a5579C4fBcC89Cc8ae46D551C53d7cecc9bD046" GroveCompounderAprOracle

contract DeployStrategyAndOracle is Script {
    function run() external {
        vm.startBroadcast();

        GroveCompounderAprOracle aprOracle = new GroveCompounderAprOracle();
        aprOracle.setUniV4Pools(GroveUniV4PoolConfig.initialPools());
        aprOracle.refreshStoredGrovePrice();

        console2.log("-----------------------------");
        console2.log("apr oracle deployed at: %s", address(aprOracle));
        console2.log("-----------------------------");

        GroveCompounder strategy = new GroveCompounder();

        console2.log("-----------------------------");
        console2.log("strategy deployed at: %s", address(strategy));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// apr oracle deployed at:
// strategy deployed at:
