// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {SinkDrain} from "contracts/v1/sink/SinkDrain.sol";
import "../test/Base.sol";

/// @notice setup the sinkDrain contract in advance so that v1 governance can create the gauge
contract DeploySinkDrain is Script {
    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.addr(deployPrivateKey);
    string public outputFilename = vm.envString("OUTPUT_FILENAME");

    SinkDrain public sinkDrain;

    function run() public {
        vm.startBroadcast(deployerAddress);
        sinkDrain = new SinkDrain();
        vm.stopBroadcast();

        string memory json = vm.serializeAddress("v2", "SinkDrain", address(sinkDrain));
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/output/DeployVelodromeV2-");
        path = string.concat(path, outputFilename);
        vm.writeJson(json, path);
    }
}
