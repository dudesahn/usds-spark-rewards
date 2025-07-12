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

// apr oracle deployed at: 0xed26eAAEDC6F77DdCfb3BE260ED1C3C257D68402
// strategy deployed at: 0xc9f01b5c6048B064E6d925d1c2d7206d4fEeF8a3
