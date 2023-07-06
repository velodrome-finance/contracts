// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {IRestrictedTeam, RestrictedTeam} from "contracts/v2/RestrictedTeam.sol";
import {VeArtProxy} from "contracts/VeArtProxy.sol";

import "forge-std/Test.sol";

contract RestrictedTeamFork is Test {
    VotingEscrow public escrow;
    FactoryRegistry public factoryRegistry;
    RestrictedTeam public restrictedTeam;

    address public team;

    uint256 optimismFork;
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    uint256 BLOCK_NUMBER = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));

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
        escrow = VotingEscrow(0xFAf8FD17D9840595845582fCB047DF13f006787d);
        factoryRegistry = FactoryRegistry(0xF4c67CdEAaB8360370F41514d06e32CcD8aA1d7B);
        restrictedTeam = new RestrictedTeam(address(escrow));
        team = factoryRegistry.owner();

        vm.prank(address(escrow.team()));
        escrow.setTeam(address(restrictedTeam)); // limit team functionality

        vm.label(address(escrow), "VotingEscrow");
        vm.label(address(factoryRegistry), "Factory Registry");
        vm.label(address(restrictedTeam), "Restricted Team");
    }

    function testInitialState() public {
        assertEq(address(restrictedTeam.escrow()), address(escrow));
        assertEq(address(restrictedTeam.factoryRegistry()), address(factoryRegistry));
        assertTrue(restrictedTeam.isTrustedForwarder(address(escrow.forwarder())));
    }

    function testCannotSetArtProxyOnVotingEscrowWithTeam() public {
        VeArtProxy artProxy = new VeArtProxy(address(escrow));

        vm.prank(team);
        vm.expectRevert(IVotingEscrow.NotTeam.selector);
        escrow.setArtProxy(address(artProxy));
    }

    function testSetArtProxyWithRestrictedTeam() public {
        VeArtProxy artProxy = new VeArtProxy(address(escrow));

        vm.prank(team);
        restrictedTeam.setArtProxy(address(artProxy));

        assertEq(escrow.artProxy(), address(artProxy));
    }

    function testCannotSetTeamOnVotingEscrowWithTeam() public {
        vm.prank(team);
        vm.expectRevert(IVotingEscrow.NotTeam.selector);
        escrow.setTeam(address(1));
    }

    function testCannotToggleSplitOnVotingEscrowWithTeam() public {
        vm.prank(team);
        vm.expectRevert(IVotingEscrow.NotTeam.selector);
        escrow.toggleSplit(address(0), true);
    }
}
