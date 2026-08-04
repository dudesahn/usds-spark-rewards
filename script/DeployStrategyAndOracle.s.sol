// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {GroveCompounderAprOracle} from "src/periphery/GroveCompounderAprOracle.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// ---- Usage ----
// forge script script/DeployStrategyAndOracle.s.sol:DeployStrategyAndOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true

// do real deployment, try slow to see if that helps w/ verification
// forge script script/DeployStrategyAndOracle.s.sol:DeployStrategyAndOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true --etherscan-api-key $ETHERSCAN_TOKEN --slow --verify --broadcast

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// no constructor (or thus, constructor args) on this one
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0x1a5579C4fBcC89Cc8ae46D551C53d7cecc9bD046" GroveCompounderAprOracle

contract DeployStrategyAndOracle is Script {
    bytes32 internal constant GROVE_USDC_V4_POOL_ID_FIVE_PERCENT =
        0xaa0b1a90c6188f42c3603998536418f4eeedccf20b999377dab7e4c6aafc5286;
    bytes32 internal constant GROVE_USDC_V4_POOL_ID =
        0x2897b6ccd757711791a90b723df4f89567568859d040ff97d25cc4a5cb93ea03;
    bytes32 internal constant GROVE_USDC_V4_POOL_ID_TWO =
        0x9fe7fb249f5fdacc3c102cb8f9c5e5b59b70da2ea96377804bcb58328b93441f;
    bytes32 internal constant GROVE_USDC_V4_POOL_ID_VOLUME =
        0x20d117a32203158c46d0dce34ade2b2cbf846d151e9cea406e0463fe361d82ce;
    bytes32 internal constant GROVE_USDC_V4_POOL_ID_KYBER =
        0x0d40eef4d9600a37016f34d089705e83d8d9e40ac80838abb04a278fa049e874;
    bytes32 internal constant GROVE_USDC_V4_POOL_ID_KYBER_TWO =
        0x31c6aeb8a664ed9ef2ec68791e7043e1aee1481ab4507b227b179072c9e4871b;

    function run() external {
        vm.startBroadcast();

        GroveCompounderAprOracle aprOracle = new GroveCompounderAprOracle();
        aprOracle.setUniV4Pools(_initialOraclePools());

        console2.log("-----------------------------");
        console2.log("apr oracle deployed at: %s", address(aprOracle));
        console2.log("-----------------------------");

        //GroveCompounder strategy = new GroveCompounder();

        console2.log("-----------------------------");
        //console2.log("strategy deployed at: %s", address(strategy));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }

    function _initialOraclePools() internal pure returns (bytes32[] memory pools) {
        pools = new bytes32[](6);
        pools[0] = GROVE_USDC_V4_POOL_ID_FIVE_PERCENT;
        pools[1] = GROVE_USDC_V4_POOL_ID;
        pools[2] = GROVE_USDC_V4_POOL_ID_TWO;
        pools[3] = GROVE_USDC_V4_POOL_ID_VOLUME;
        pools[4] = GROVE_USDC_V4_POOL_ID_KYBER;
        pools[5] = GROVE_USDC_V4_POOL_ID_KYBER_TWO;
    }
}

// apr oracle deployed at: 0xed26eAAEDC6F77DdCfb3BE260ED1C3C257D68402
// strategy deployed at: 0xc9f01b5c6048B064E6d925d1c2d7206d4fEeF8a3
// apr oracle v2 deployed at: 0x1a5579C4fBcC89Cc8ae46D551C53d7cecc9bD046
