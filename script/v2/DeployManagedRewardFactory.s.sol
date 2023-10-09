pragma solidity 0.8.19;

import {PatchedManagedRewardsFactory} from "contracts/v2/PatchedManagedRewardsFactory.sol";

import "forge-std/Script.sol";

/// @notice Deploy patched managed reward factory
contract DeployManagedRewardsFactory is Script {
    uint256 deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");

    PatchedManagedRewardsFactory public managedRewardsFactory;

    function run() public {
        vm.startBroadcast(deployPrivateKey);
        managedRewardsFactory = new PatchedManagedRewardsFactory();
        vm.stopBroadcast();

        console2.log("Patched Managed Rewards Factory deployed at: ", address(managedRewardsFactory));
    }
}
