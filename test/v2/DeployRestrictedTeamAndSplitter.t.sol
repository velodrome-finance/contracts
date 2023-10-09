// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {ISplitter, Splitter} from "contracts/v2/Splitter.sol";
import {IRestrictedTeam, RestrictedTeam} from "contracts/v2/RestrictedTeam.sol";

import "../../script/v2/DeployRestrictedTeamAndSplitter.s.sol";
import "forge-std/Test.sol";

contract DeployRestrictedTeamAndSplitterTest is Test {
    VotingEscrow public escrow;
    FactoryRegistry public factoryRegistry;
    DeployRestrictedTeamAndSplitter deployRestrictedTeamAndSplitter;

    uint256 optimismFork;
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    uint256 BLOCK_NUMBER = 106378138;

    function setUp() public {
        assertFalse(bytes(OPTIMISM_RPC_URL).length == 0);
        if (BLOCK_NUMBER != 0) {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL, BLOCK_NUMBER);
        } else {
            optimismFork = vm.createFork(OPTIMISM_RPC_URL);
        }
        vm.selectFork(optimismFork);

        escrow = VotingEscrow(0xFAf8FD17D9840595845582fCB047DF13f006787d);
        factoryRegistry = FactoryRegistry(0xF4c67CdEAaB8360370F41514d06e32CcD8aA1d7B);

        deployRestrictedTeamAndSplitter = new DeployRestrictedTeamAndSplitter();
    }

    function testDeployRestrictedTeamAndSplitter() public {
        deployRestrictedTeamAndSplitter.run();

        RestrictedTeam restrictedTeam = RestrictedTeam(deployRestrictedTeamAndSplitter.restrictedTeam());
        Splitter splitter = Splitter(deployRestrictedTeamAndSplitter.splitter());

        assertEq(address(restrictedTeam.escrow()), address(escrow));
        assertEq(address(restrictedTeam.factoryRegistry()), address(factoryRegistry));
        assertTrue(restrictedTeam.isTrustedForwarder(escrow.forwarder()));

        assertEq(address(splitter.escrow()), address(escrow));
        assertEq(address(splitter.factoryRegistry()), address(factoryRegistry));
        assertTrue(splitter.isTrustedForwarder(escrow.forwarder()));
    }
}
