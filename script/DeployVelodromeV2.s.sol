// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/StdJson.sol";

import "./DeployBase.s.sol";

contract DeployVelodromeV2 is DeployBase {
    using stdJson for string;

    function run() public {
        vm.startBroadcast(deployerAddress);

        _deploySetupBefore();
        _coreSetup();
        _deploySetupAfter();

        vm.stopBroadcast();
    }

    function _deploySetupBefore() public {
        // more constants loading - this needs to be done in-memory and not storage
        address[78] memory _tokens = _whitelistTokens;
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokens.push(_tokens[i]);
        }
    }

    /// @notice only executed if called from TestDeploy or actual deploy
    function _deploySetupAfter() public {
        if (deployerAddress != address(1)) return;
        // Set protocol state to _params.team
        escrow.setTeam(_params.team);
        minter.setTeam(_params.team);
        factory.setPauser(_params.team);
        factory.setPoolAdmin(_params.team);
        voter.setEmergencyCouncil(_params.emergencyCouncil);
        voter.setEpochGovernor(_params.team);
        voter.setGovernor(_params.team);
        factoryRegistry.transferOwnership(_params.team);

        // Set notifyAdmin in gauge factory
        gaugeFactory.setNotifyAdmin(_params.notifyAdmin);

        // Set contract vars
        factory.setFeeManager(_params.feeManager);

        if (isTest) return;

        // Loading output and use output path to later save deployed contracts
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/deployment-addresses/", _params.outputFilename));

        // write to file
        vm.writeJson(vm.serializeAddress("v2", "VELO", address(VELO)), path);
        vm.writeJson(vm.serializeAddress("v2", "VotingEscrow", address(escrow)), path);
        vm.writeJson(vm.serializeAddress("v2", "Forwarder", address(forwarder)), path);
        vm.writeJson(vm.serializeAddress("v2", "ArtProxy", address(artProxy)), path);
        vm.writeJson(vm.serializeAddress("v2", "Distributor", address(distributor)), path);
        vm.writeJson(vm.serializeAddress("v2", "Voter", address(voter)), path);
        vm.writeJson(vm.serializeAddress("v2", "Router", address(router)), path);
        vm.writeJson(vm.serializeAddress("v2", "Minter", address(minter)), path);
        vm.writeJson(vm.serializeAddress("v2", "PoolFactory", address(factory)), path);
        vm.writeJson(vm.serializeAddress("v2", "VotingRewardsFactory", address(votingRewardsFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "GaugeFactory", address(gaugeFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "ManagedRewardsFactory", address(managedRewardsFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "FactoryRegistry", address(factoryRegistry)), path);
    }
}
