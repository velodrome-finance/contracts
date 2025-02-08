// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import {SinkPoolFactory} from "contracts/factories/sink/SinkPoolFactory.sol";
import {SinkGaugeFactory} from "contracts/factories/sink/SinkGaugeFactory.sol";
import {SinkPool} from "contracts/sink/SinkPool.sol";
import {SinkGauge} from "contracts/gauges/sink/SinkGauge.sol";

contract DeploySink is Script {
    using stdJson for string;

    struct SinkDeploymentParameters {
        address voter;
        string outputFilename;
    }

    uint256 temp; // temp var to force deployerAddress into a new package slot for checked_write
    address public deployerAddress = 0x4994DacdB9C57A811aFfbF878D92E00EF2E5C4C2;

    SinkDeploymentParameters public _params;

    // emission sink contracts
    SinkPoolFactory public sinkPoolFactory;
    SinkGaugeFactory public sinkGaugeFactory;
    SinkPool public sinkPool;
    SinkGauge public sinkGauge;

    uint256 temp2; // temp var to force isTest into a new package slot for checked_write
    /// @dev Used by tests to disable logging of output
    bool public isTest;

    constructor() {
        _params = SinkDeploymentParameters({
            voter: 0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C,
            outputFilename: "optimism.json"
        });
    }

    function run() public {
        vm.startBroadcast(deployerAddress);

        require(address(_params.voter) != address(0), "voter not set");

        require(address(_params.voter) == 0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C, "voter not correct");

        sinkPoolFactory = new SinkPoolFactory();
        sinkGaugeFactory = new SinkGaugeFactory({_voter: _params.voter});

        sinkPool = SinkPool(sinkPoolFactory.pool());
        sinkGauge = SinkGauge(sinkGaugeFactory.gauge());

        vm.stopBroadcast();

        if (isTest) return;

        // Loading output and use output path to later save deployed contracts
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/deployment-addresses/", _params.outputFilename));

        // write to file
        vm.writeJson(vm.toString(address(sinkPoolFactory)), path, ".SinkPoolFactory");
        vm.writeJson(vm.toString(address(sinkGaugeFactory)), path, ".SinkGaugeFactory");
        vm.writeJson(vm.toString(address(sinkPool)), path, ".SinkPool");
        vm.writeJson(vm.toString(address(sinkGauge)), path, ".SinkGauge");
    }
}
