// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";
import {SinkManager} from "contracts/v1/sink/SinkManager.sol";

/// @notice Finish deployment setup of SinkManager
contract SetupSinkManager is Script {

    using stdJson for string;

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployerPublicKey = vm.envAddress("PUBLIC_KEY");
    string chainName = vm.envString("CHAIN_NAME");
    string json;

    function run() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/");
        path = string.concat(path, chainName);
        path = string.concat(path, ".json");
        json = vm.readFile(path);

        // Set state
        uint256 ownedTokenId = abi.decode(vm.parseJson(json, ".ownedTokenId"), (uint256));
        IVotingEscrow vEscrow = IVotingEscrow(abi.decode(vm.parseJson(json, ".v1.Escrow"), (address)));
        SinkManager sinkManager = SinkManager(abi.decode(vm.parseJson(json, ".SinkManager"), (address)));
        address sinkDrain = abi.decode(vm.parseJson(json, ".SinkDrain"), (address));

        // Transfer veNFT to sink manager
        vEscrow.safeTransferFrom(deployerPublicKey, address(sinkManager), ownedTokenId);
        
        // Finish setting up sink manager
        sinkManager.setOwnedTokenId(ownedTokenId);
        sinkManager.setupSinkDrain(sinkDrain);
    }
}