// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

contract DeployGovernors is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.addr(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");
    string public jsonConstants;

    address public vetoer;
    address public team;

    IVoter public voter;
    VotingEscrow public escrow;
    Forwarder public forwarder;
    Minter public minter;
    VeloGovernor public governor;
    EpochGovernor public epochGovernor;

    function run() public {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");

        string memory path = string.concat(basePath, constantsFilename);
        jsonConstants = vm.readFile(path);
        vetoer = abi.decode(vm.parseJson(jsonConstants, ".vetoer"), (address));
        team = abi.decode(vm.parseJson(jsonConstants, ".team"), (address));
        escrow = VotingEscrow(abi.decode(vm.parseJson(jsonConstants, ".current.VotingEscrow"), (address)));
        voter = IVoter(abi.decode(vm.parseJson(jsonConstants, ".current.Voter"), (address)));
        forwarder = Forwarder(abi.decode(vm.parseJson(jsonConstants, ".current.Forwarder"), (address)));
        minter = Minter(abi.decode(vm.parseJson(jsonConstants, ".current.Minter"), (address)));

        require(address(escrow) != address(0)); // sanity check for constants file fillled out correctly

        vm.startBroadcast(deployerAddress);

        governor = new VeloGovernor(escrow, IVoter(voter));
        epochGovernor = new EpochGovernor(address(forwarder), escrow, address(minter), IVoter(voter));

        governor.setVetoer(vetoer);
        governor.setTeam(team);

        vm.stopBroadcast();

        // write to file
        path = string.concat(basePath, "output/DeployGovernors-");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "Governor", address(governor)), path);
        vm.writeJson(vm.serializeAddress("v2", "EpochGovernor", address(epochGovernor)), path);
    }
}
