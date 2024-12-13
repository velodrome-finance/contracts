// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/StdJson.sol";

import "./DeployBase.s.sol";

contract DeployGovernors is DeployBase {
    using stdJson for string;

    address public vetoer;
    address public team;

    function run() public {
        vetoer = _params.vetoer;
        team = _params.team;
        escrow = VotingEscrow(_params.votingEscrow);
        voter = Voter(_params.voter);
        forwarder = Forwarder(payable(_params.forwarder));
        minter = Minter(_params.minter);

        require(address(escrow) != address(0)); // sanity check for constants file fillled out correctly

        vm.startBroadcast(deployerAddress);

        governor = new VeloGovernor(escrow, voter);
        epochGovernor = new EpochGovernor(escrow, address(_params.minter), team);

        governor.setVetoer(vetoer);
        governor.setTeam(team);

        vm.stopBroadcast();

        if (isTest) return;
        // write to file
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/deployment-addresses/governors/", _params.outputFilename));
        vm.writeJson(vm.serializeAddress("v2", "Governor", address(governor)), path);
        vm.writeJson(vm.serializeAddress("v2", "EpochGovernor", address(epochGovernor)), path);
    }
}
