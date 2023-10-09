// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVelo, Velo} from "contracts/Velo.sol";
import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {IVoter, Voter} from "contracts/Voter.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {PatchedManagedRewardsFactory} from "contracts/v2/PatchedManagedRewardsFactory.sol";
import {PatchedReward} from "contracts/v2/PatchedReward.sol";
import "forge-std/Test.sol";

contract ManagedNftForkTest is Test {
    Velo public VELO;
    VotingEscrow public escrow;
    Voter public voter;
    FactoryRegistry public factoryRegistry;
    PatchedManagedRewardsFactory public managedRewardsFactory;

    address public owner = address(1);
    address public owner2 = address(2);
    address public team;
    address public pool;

    uint256 public constant TOKEN_1 = 1e18;
    uint256 constant MAXTIME = 4 * 365 * 86400;

    uint256 public optimismFork;
    string public OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    uint256 public BLOCK_NUMBER = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));

    function setUp() public {
        assertFalse(bytes(OPTIMISM_RPC_URL).length == 0);
        if (BLOCK_NUMBER != 0) {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL, BLOCK_NUMBER);
        } else {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL);
        }
        vm.selectFork(optimismFork);

        /// @dev Addresses taken from /script/output/DeployVelodromeV2-Optimism.json
        ///      i.e. Optimism mainnet deployment
        VELO = Velo(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
        escrow = VotingEscrow(0xFAf8FD17D9840595845582fCB047DF13f006787d);
        voter = Voter(0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C);
        factoryRegistry = FactoryRegistry(0xF4c67CdEAaB8360370F41514d06e32CcD8aA1d7B);
        team = factoryRegistry.owner();
        pool = address(0x0df083de449F75691fc5A36477a6f3284C269108);

        // deploy new managed rewards factory
        managedRewardsFactory = new PatchedManagedRewardsFactory();
        vm.prank(team);
        factoryRegistry.setManagedRewardsFactory(address(managedRewardsFactory));

        vm.label(address(VELO), "Velo V2");
        vm.label(address(escrow), "VotingEscrow");
        vm.label(address(voter), "Voter");
        vm.label(address(factoryRegistry), "Factory Registry");
        vm.label(address(managedRewardsFactory), "Patched Managed Rewards Factory");
    }

    function testCannotDepositManagedIfNotReset() public {
        vm.prank(voter.governor());
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        deal(address(VELO), address(this), TOKEN_1, true);
        VELO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;

        voter.vote(tokenId, pools, weights);

        skipToNextEpoch(1 hours + 1);

        vm.expectRevert(PatchedReward.NotReset.selector);
        voter.depositManaged(tokenId, mTokenId);
    }

    function skipToNextEpoch(uint256 offset) public {
        uint256 ts = block.timestamp;
        uint256 nextEpoch = ts - (ts % (1 weeks)) + (1 weeks);
        vm.warp(nextEpoch + offset);
        vm.roll(block.number + 1);
    }
}
