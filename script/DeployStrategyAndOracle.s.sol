// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {SparkCompounderAprOracle} from "src/periphery/SparkCompounderAprOracle.sol";
import {SparkCompounder} from "src/SparkCompounder.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployStrategyAndOracle.s.sol:DeployStrategyAndOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true

// do real deployment, try slow to see if that helps w/ verification
// forge script script/DeployStrategyAndOracle.s.sol:DeployStrategyAndOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true --etherscan-api-key $ETHERSCAN_TOKEN --slow --verify --broadcast

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// no constructor (or thus, constructor args) on this one
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "CONTRACT_ADDRESS" CONTRACT_NAME

contract DeployStrategyAndOracle is Script {
    function run() external {
        vm.startBroadcast();

        SparkCompounderAprOracle aprOracle = new SparkCompounderAprOracle();

        console2.log("-----------------------------");
        console2.log("apr oracle deployed at: %s", address(aprOracle));
        console2.log("-----------------------------");

        SparkCompounder strategy = new SparkCompounder();

        console2.log("-----------------------------");
        console2.log("strategy deployed at: %s", address(strategy));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// apr oracle deployed at: 0x20bd8551D498641427E2534469Ae2A30304d2b7e
// strategy deployed at: 0xA0342237a5F99888b92C94F15aa2B330A75D4641
