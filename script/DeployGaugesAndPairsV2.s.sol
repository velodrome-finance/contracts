// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

/// @notice Deploy script to deploy new pairs and gauges for v2
contract DeployGaugesAndPairsV2 is Script {
    using stdJson for string;

    uint256 deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    string constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string outputFilename = vm.envString("OUTPUT_FILENAME");
    string jsonConstants;
    string jsonOutput;

    PairFactory public factory;
    Voter public voter;

    struct PairV2 {
        bool stable;
        address tokenA;
        address tokenB;
    }

    address[] pairsV2;
    address[] gauges;

    constructor() {}

    function run() public {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");
        string memory path = string.concat(basePath, constantsFilename);

        // load in vars
        jsonConstants = vm.readFile(path);
        PairV2[] memory pairs = abi.decode(jsonConstants.parseRaw(".pairsV2"), (PairV2[]));

        path = string.concat(basePath, "output/DeployVelodromeV2-");
        path = string.concat(path, outputFilename);
        jsonOutput = vm.readFile(path);
        factory = PairFactory(abi.decode(jsonOutput.parseRaw(".PairFactory"), (address)));
        voter = Voter(abi.decode(jsonOutput.parseRaw(".Voter"), (address)));
        address votingRewardsFactory = abi.decode(jsonOutput.parseRaw(".VotingRewardsFactory"), (address));
        address gaugeFactory = abi.decode(jsonOutput.parseRaw(".GaugeFactory"), (address));

        vm.startBroadcast(deployPrivateKey);

        for (uint256 i = 0; i < pairs.length; i++) {
            address newPair = factory.createPair(pairs[i].tokenA, pairs[i].tokenB, pairs[i].stable);
            address newGauge = voter.createGauge(address(factory), votingRewardsFactory, gaugeFactory, newPair);

            pairsV2.push(newPair);
            gauges.push(newGauge);
        }

        vm.stopBroadcast();

        // Write to file
        path = string.concat(basePath, "output/DeployGaugesAndPairsV2-");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "gaugesPairsV2", gauges), path);
        vm.writeJson(vm.serializeAddress("v2", "pairsV2", pairsV2), path);
    }
}
