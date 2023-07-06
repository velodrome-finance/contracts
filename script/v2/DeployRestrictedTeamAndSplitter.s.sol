// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Splitter} from "contracts/v2/Splitter.sol";
import {RestrictedTeam} from "contracts/v2/RestrictedTeam.sol";
import {FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {VotingEscrow} from "contracts/VotingEscrow.sol";

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console2.sol";

/// @notice Deploy restricted team and splitter
contract DeployRestrictedTeamAndSplitter is Script {
    using stdJson for string;
    uint256 deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");

    RestrictedTeam public restrictedTeam;
    Splitter public splitter;

    function run() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/output/DeployVelodromeV2-Optimism.json");
        string memory jsonOutput = vm.readFile(path);
        address factoryRegistry = abi.decode(jsonOutput.parseRaw(".FactoryRegistry"), (address));
        address escrow = abi.decode(jsonOutput.parseRaw(".VotingEscrow"), (address));

        // sanity check to ensure ownership is equal
        require(VotingEscrow(escrow).team() == FactoryRegistry(factoryRegistry).owner());
        require(!VotingEscrow(escrow).canSplit(address(0)));

        vm.startBroadcast(deployPrivateKey);
        restrictedTeam = new RestrictedTeam(escrow);
        splitter = new Splitter(escrow);
        vm.stopBroadcast();

        console2.log("Restricted Team Deployed At: ", address(restrictedTeam));
        console2.log("Splitter Deployed At: ", address(splitter));
    }
}
