// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVelo, Velo} from "contracts/Velo.sol";
import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {ISplitter, Splitter} from "contracts/v2/Splitter.sol";
import {IRestrictedTeam, RestrictedTeam} from "contracts/v2/RestrictedTeam.sol";
import {SafeCastLibrary} from "contracts/libraries/SafeCastLibrary.sol";

import "forge-std/Test.sol";

contract SplitterFork is Test {
    using SafeCastLibrary for int128;

    Velo public VELO;
    VotingEscrow public escrow;
    FactoryRegistry public factoryRegistry;
    Splitter public splitter;
    RestrictedTeam public restrictedTeam;

    address public owner = address(1);
    address public owner2 = address(2);
    address public team;

    uint256 public constant TOKEN_1 = 1e18;
    uint256 constant MAXTIME = 4 * 365 * 86400;

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
        VELO = Velo(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
        escrow = VotingEscrow(0xFAf8FD17D9840595845582fCB047DF13f006787d);
        factoryRegistry = FactoryRegistry(0xF4c67CdEAaB8360370F41514d06e32CcD8aA1d7B);
        splitter = new Splitter(address(escrow));
        restrictedTeam = new RestrictedTeam(address(escrow));
        team = factoryRegistry.owner();

        vm.startPrank(address(escrow.team()));
        escrow.toggleSplit(address(splitter), true);
        escrow.setTeam(address(restrictedTeam)); // limit team functionality
        vm.stopPrank();

        vm.label(address(VELO), "Velo V2");
        vm.label(address(escrow), "VotingEscrow");
        vm.label(address(factoryRegistry), "Factory Registry");
        vm.label(address(splitter), "Splitter");
    }

    function testInitialState() public {
        assertEq(address(splitter.escrow()), address(escrow));
        assertTrue(splitter.isTrustedForwarder(escrow.forwarder()));
        assertEq(address(splitter.factoryRegistry()), address(factoryRegistry));

        // team is not splitter and is not owner of factory registry
        assertEq(escrow.team(), address(restrictedTeam));
        assertFalse(address(restrictedTeam) == team);
        assertFalse(address(restrictedTeam) == address(splitter));

        // only splitter can split
        assertTrue(escrow.canSplit(address(splitter)));
    }

    function testCannotToggleSplitIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(ISplitter.NotTeam.selector);
        splitter.toggleSplit(owner, true);
    }

    function testToggleSplitForAll() public {
        assertFalse(splitter.canSplit(address(0)));

        vm.prank(team);
        splitter.toggleSplit(address(0), true);
        assertTrue(splitter.canSplit(address(0)));

        vm.prank(team);
        splitter.toggleSplit(address(0), false);
        assertFalse(splitter.canSplit(address(0)));

        vm.prank(team);
        splitter.toggleSplit(address(0), true);
        assertTrue(splitter.canSplit(address(0)));
    }

    function testToggleSplitForSingle() public {
        assertFalse(splitter.canSplit(owner));

        vm.prank(team);
        splitter.toggleSplit(owner, true);
        assertTrue(splitter.canSplit(owner));

        vm.prank(team);
        splitter.toggleSplit(owner, false);
        assertFalse(splitter.canSplit(owner));
    }

    function testCannotSplitIfNotApprovedToSplit() public {
        deal(address(VELO), address(owner2), TOKEN_1, true);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        escrow.approve(address(splitter), tokenId);
        vm.expectRevert(ISplitter.NotAllowed.selector);
        splitter.split(tokenId, TOKEN_1 / 4);
    }

    function testCannotSplitIfNotApprovedForVeNFT() public {
        vm.prank(team);
        splitter.toggleSplit(address(owner2), true);

        deal(address(VELO), address(owner2), TOKEN_1, true);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.approve(address(splitter), tokenId);
        vm.stopPrank();

        vm.expectRevert(ISplitter.NotApprovedOrOwner.selector);
        vm.prank(address(owner)); // cannot split if not approved on veNFT
        splitter.split(tokenId, TOKEN_1 / 4);

        // zero out approval
        vm.startPrank(address(owner2));
        escrow.approve(address(0), tokenId);
        escrow.setApprovalForAll(address(splitter), true);
        vm.stopPrank();

        vm.expectRevert(ISplitter.NotApprovedOrOwner.selector);
        vm.prank(address(owner)); // cannot split if not approved on veNFT
        splitter.split(tokenId, TOKEN_1 / 4);
    }

    function testSplitWhenToggledForAll() public {
        vm.prank(team);
        splitter.toggleSplit(address(0), true);

        deal(address(VELO), address(owner2), TOKEN_1, true);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 lockEnd = escrow.locked(tokenId).end;

        // splitter requires approval of token to split
        escrow.approve(address(splitter), tokenId);
        (uint256 tokenId2, uint256 tokenId3) = splitter.split(tokenId, TOKEN_1 / 4);

        IVotingEscrow.LockedBalance memory lock = escrow.locked(tokenId2);
        assertEq(lock.amount.toUint256(), (TOKEN_1 * 3) / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId2), owner2);

        lock = escrow.locked(tokenId3);
        assertEq(lock.amount.toUint256(), TOKEN_1 / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId3), owner2);
        vm.stopPrank();
    }

    function testSplitWhenToggledForSingleWithApprovalForAll() public {
        vm.prank(team);
        splitter.toggleSplit(owner2, true);

        deal(address(VELO), address(owner2), TOKEN_1, true);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.setApprovalForAll(address(owner), true);

        uint256 lockEnd = escrow.locked(tokenId).end;

        // splitter given approval by owner2
        escrow.approve(address(splitter), tokenId);
        vm.stopPrank();

        vm.prank(address(owner)); // owner can split, as has approval for all
        (uint256 tokenId2, uint256 tokenId3) = splitter.split(tokenId, TOKEN_1 / 4);

        IVotingEscrow.LockedBalance memory lock = escrow.locked(tokenId2);
        assertEq(lock.amount.toUint256(), (TOKEN_1 * 3) / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId2), owner2);

        lock = escrow.locked(tokenId3);
        assertEq(lock.amount.toUint256(), TOKEN_1 / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId3), owner2);
    }

    function testSplitWhenToggledForSingleWithApproval() public {
        vm.prank(team);
        splitter.toggleSplit(owner2, true);

        deal(address(VELO), address(owner2), TOKEN_1, true);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.approve(address(owner), tokenId);

        uint256 lockEnd = escrow.locked(tokenId).end;

        // splitter given approval by owner2
        escrow.setApprovalForAll(address(splitter), true);
        vm.stopPrank();

        vm.prank(address(owner)); // owner can split, as has approval
        (uint256 tokenId2, uint256 tokenId3) = splitter.split(tokenId, TOKEN_1 / 4);

        IVotingEscrow.LockedBalance memory lock = escrow.locked(tokenId2);
        assertEq(lock.amount.toUint256(), (TOKEN_1 * 3) / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId2), owner2);

        lock = escrow.locked(tokenId3);
        assertEq(lock.amount.toUint256(), TOKEN_1 / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId3), owner2);
    }

    function testSplitWhenToggledForSingle() public {
        vm.prank(team);
        splitter.toggleSplit(owner2, true);

        deal(address(VELO), address(owner2), TOKEN_1, true);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 lockEnd = escrow.locked(tokenId).end;

        // splitter requires approval of token to split
        escrow.approve(address(splitter), tokenId);
        (uint256 tokenId2, uint256 tokenId3) = splitter.split(tokenId, TOKEN_1 / 4);

        IVotingEscrow.LockedBalance memory lock = escrow.locked(tokenId2);
        assertEq(lock.amount.toUint256(), (TOKEN_1 * 3) / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId2), owner2);

        lock = escrow.locked(tokenId3);
        assertEq(lock.amount.toUint256(), TOKEN_1 / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId3), owner2);
        vm.stopPrank();
    }

    function testSplitWithDelegatedPermanentLock() public {
        vm.prank(team);
        splitter.toggleSplit(owner2, true);

        deal(address(VELO), address(owner2), TOKEN_1 * 2, true);
        vm.startPrank(address(owner2));
        VELO.approve(address(escrow), TOKEN_1 * 2);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        escrow.lockPermanent(tokenId2);
        escrow.delegate(tokenId, tokenId2);

        uint256 lockEnd = escrow.locked(tokenId).end;

        // splitter requires approval of token to split
        escrow.approve(address(splitter), tokenId);
        (uint256 tokenId3, uint256 tokenId4) = splitter.split(tokenId, TOKEN_1 / 4);
        vm.stopPrank();

        IVotingEscrow.LockedBalance memory lock = escrow.locked(tokenId3);
        assertEq(lock.amount.toUint256(), (TOKEN_1 * 3) / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId3), owner2);

        lock = escrow.locked(tokenId4);
        assertEq(lock.amount.toUint256(), TOKEN_1 / 4);
        assertEq(lock.end, lockEnd);
        assertEq(escrow.ownerOf(tokenId4), owner2);

        assertEq(escrow.ownerOf(tokenId), address(0)); // burned
        assertEq(escrow.balanceOfNFT(tokenId2), TOKEN_1); // dedelegated
    }

    function testSplitWithOverflow() public {
        vm.prank(team);
        splitter.toggleSplit(address(0), true);

        deal(address(VELO), owner, TOKEN_1, true);
        vm.startPrank(address(owner));
        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.startPrank(owner2);
        deal(address(VELO), address(owner2), TOKEN_1, true);
        VELO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        // Creates the create overflow amount
        uint256 escrowBalance = VELO.balanceOf(address(escrow));
        uint256 overflowAmount = uint256(int256(int128(-(int256(escrowBalance)))));
        assertGt(overflowAmount, uint128(type(int128).max));

        escrow.approve(address(splitter), tokenId);
        vm.expectRevert(SafeCastLibrary.SafeCastOverflow.selector);
        splitter.split(tokenId, overflowAmount);
        vm.stopPrank();
    }
}
