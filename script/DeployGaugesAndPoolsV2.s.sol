// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

/// @notice Deploy script to deploy new pools and gauges for v2
contract DeployGaugesAndPoolsV2 is Script {
    using stdJson for string;

    uint256 deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    string constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string outputFilename = vm.envString("OUTPUT_FILENAME");
    string jsonConstants;
    string jsonOutput;

    PoolFactory public factory;
    Voter public voter;

    struct PoolV2 {
        bool stable;
        address tokenA;
        address tokenB;
    }

    address[] poolsV2;
    address[] gauges;

    constructor() {}

    function run() public {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");
        string memory path = string.concat(basePath, constantsFilename);

        // load in vars
        jsonConstants = vm.readFile(path);
        PoolV2[] memory pools = abi.decode(jsonConstants.parseRaw(".poolsV2"), (PoolV2[]));

        path = string.concat(basePath, "output/DeployVelodromeV2-");
        path = string.concat(path, outputFilename);
        jsonOutput = vm.readFile(path);
        factory = PoolFactory(abi.decode(jsonOutput.parseRaw(".PoolFactory"), (address)));
        voter = Voter(abi.decode(jsonOutput.parseRaw(".Voter"), (address)));
        address votingRewardsFactory = abi.decode(jsonOutput.parseRaw(".VotingRewardsFactory"), (address));
        address gaugeFactory = abi.decode(jsonOutput.parseRaw(".GaugeFactory"), (address));

        vm.startBroadcast(deployPrivateKey);

        for (uint256 i = 0; i < pools.length; i++) {
            address newPool = factory.createPool(pools[i].tokenA, pools[i].tokenB, pools[i].stable);
            address newGauge = voter.createGauge(address(factory), votingRewardsFactory, gaugeFactory, newPool);

            poolsV2.push(newPool);
            gauges.push(newGauge);
        }

        vm.stopBroadcast();

        // Write to file
        path = string.concat(basePath, "output/DeployGaugesAndPoolsV2-");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "gaugesPoolsV2", gauges), path);
        vm.writeJson(vm.serializeAddress("v2", "poolsV2", poolsV2), path);
    }
}
