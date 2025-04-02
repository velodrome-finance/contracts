// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./DeployBase.s.sol";
import {SimpleEpochGovernor} from "contracts/SimpleEpochGovernor.sol";

contract DeploySimpleEpochGovernor is DeployBase {
    using stdJson for string;

    SimpleEpochGovernor public simpleGovernor;

    string public outputFilename = "optimism.json";
    string public path;

    constructor() {
        string memory root = vm.projectRoot();
        path = string.concat(root, "/deployment-addresses/");
        path = string.concat(path, outputFilename);
        string memory jsonOutput = vm.readFile(path);

        minter = Minter(abi.decode(jsonOutput.parseRaw(".Minter"), (address)));
        voter = Voter(abi.decode(jsonOutput.parseRaw(".Voter"), (address)));
    }

    function run() public {
        vm.startBroadcast();

        simpleGovernor = new SimpleEpochGovernor({_minter: address(minter), _voter: address(voter)});
        console.log("SimpleEpochGovernor deployed to: ", address(simpleGovernor));

        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(simpleGovernor)), path, ".SimpleEpochGovernor");
    }
}
