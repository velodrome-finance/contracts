// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

/// @notice Deploy script to deploy new gauges using existing v1 pools
contract DeployGaugesV1 is Script {
    using stdJson for string;

    uint256 deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    string constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string outputFilename = vm.envString("OUTPUT_FILENAME");
    string jsonConstants;
    string jsonOutput;

    PoolFactory public vFactory;
    Voter public voter;

    address[] gauges;

    constructor() {}

    function run() public {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");

        // load in vars
        string memory path = string.concat(basePath, constantsFilename);
        jsonConstants = vm.readFile(path);
        address[] memory pools = abi.decode(jsonConstants.parseRaw(".poolsV1"), (address[]));
        vFactory = PoolFactory(abi.decode(jsonConstants.parseRaw(".v1.Factory"), (address)));

        path = string.concat(basePath, "output/DeployVelodromeV2-");
        path = string.concat(path, outputFilename);
        jsonOutput = vm.readFile(path);
        voter = Voter(abi.decode(jsonOutput.parseRaw(".Voter"), (address)));
        address votingRewardsFactory = abi.decode(jsonOutput.parseRaw(".VotingRewardsFactory"), (address));
        address gaugeFactory = abi.decode(jsonOutput.parseRaw(".GaugeFactory"), (address));

        vm.startBroadcast(deployPrivateKey);

        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            address newGauge = voter.createGauge(address(vFactory), votingRewardsFactory, gaugeFactory, pool);
            gauges.push(newGauge);
        }

        vm.stopBroadcast();

        // Write to file
        path = string.concat(basePath, "output/DeployGaugesV1-");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "gaugesPoolsV1", gauges), path);
    }
}
