// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {VotingEscrow} from "contracts/VotingEscrow.sol";
import {Voter} from "contracts/Voter.sol";
import {Velo} from "contracts/Velo.sol";
import {TestOwner} from "test/utils/TestOwner.sol";
import {TimeStore} from "./TimeStore.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract EscrowHandlerForGovernance is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    VotingEscrow public immutable escrow;
    Voter public immutable voter;
    Velo public immutable VELO;
    TimeStore public immutable timeStore;
    address[] public actors;
    uint256 public numActors;
    address internal currentActor;
    /// @dev tokenId of mveNFT receiving deposits
    uint256 public mTokenId;
    uint256[] public mTokenIds;
    uint256 public mTokenIdsLength;

    /// @dev Stores the owner of permanent locks
    EnumerableSet.AddressSet internal permanentLocks;
    /// @dev Stores the owner of normal locks
    EnumerableSet.AddressSet internal normalLocks;

    uint256 public constant WEEK = (7 days);
    uint256 public constant TOKEN_1 = 1e18;

    /// @dev owner => tokenId
    mapping(address => uint256) public ownerToId;

    constructor(VotingEscrow _escrow, TimeStore _timeStore, address[] memory owners) {
        escrow = _escrow;
        voter = Voter(escrow.voter());
        VELO = Velo(escrow.token());
        timeStore = _timeStore;
        actors = new address[](owners.length + 2);

        // use existing owners as actors
        for (uint256 i = 0; i < actors.length; i++) {
            if (i < owners.length) {
                actors[i] = owners[i];
            } else {
                // create actor6, actor7
                // will house managed nfts
                actors[i] = address(new TestOwner());
            }
        }

        timeStore.increaseCurrentTimestamp(1695882232);
        vm.warp(timeStore.currentTimestamp());
        vm.roll(timeStore.currentBlockNumber());

        createLocks();
    }

    // @dev Simulates the passage of time.
    //      Time jump is bounded to ensure veNFTs do not expire too quickly.
    modifier increaseTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = bound(timeJumpSeed, 0, 2 weeks);
        timeStore.increaseCurrentTimestamp(timeJump);
        vm.warp(timeStore.currentTimestamp());
        vm.roll(timeStore.currentBlockNumber());
        _;
    }

    modifier useActorNormal(uint256 actorIndexSeed) {
        currentActor = normalLocks.at(bound(actorIndexSeed, 0, normalLocks.length() - 1));
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useActorPermanent(uint256 actorIndexSeed) {
        currentActor = permanentLocks.at(bound(actorIndexSeed, 0, permanentLocks.length() - 1));
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    // add locked rewards
    function addLockedRewards(uint256 amount, uint256 timeJumpSeed) public increaseTimestamp(timeJumpSeed) {
        amount = bound(amount, 1, 10_000 ether);
        address managedOwner = actors[numActors - 2];
        vm.startPrank(managedOwner);
        deal(address(VELO), managedOwner, amount, true);
        VELO.approve(address(escrow), amount);
        escrow.increaseAmount(mTokenId, amount);
        vm.stopPrank();
    }

    // increase amount randomly
    function increaseAmount(
        uint256 amount,
        uint256 actorIndexSeed,
        uint256 timeJumpSeed
    ) public increaseTimestamp(timeJumpSeed) useActorNormal(actorIndexSeed) {
        uint256 balanceOf = VELO.balanceOf(currentActor);
        amount = bound(amount, 1, balanceOf / 2);
        VELO.approve(address(escrow), amount);
        escrow.increaseAmount(ownerToId[currentActor], amount);
    }

    // delegate randomly, includes dedelegation
    function delegate(
        uint256 delegatee,
        uint256 actorIndexSeed,
        uint256 timeJumpSeed
    ) public increaseTimestamp(timeJumpSeed) useActorPermanent(actorIndexSeed) {
        delegatee = bound(delegatee, 0, numActors - 2);
        uint256 currentTokenId = ownerToId[currentActor];
        uint256 delegateeTokenId = ownerToId[actors[delegatee]];
        escrow.delegate(currentTokenId, delegateeTokenId);
    }

    function createLocks() internal {
        // seed each actor with at least one veNFT
        // actor1 =~ 1 yr lock, actor2 =~ 2yr lock ...
        uint256 tokenId;
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(address(actors[i]));
            VELO.approve(address(escrow), TOKEN_1 * (i + 1));
            tokenId = escrow.createLock(TOKEN_1, WEEK * (52 * (i + 1)));
            ownerToId[actors[i]] = tokenId;
            normalLocks.add(actors[i]);
            numActors++;
            vm.stopPrank();
        }

        // actor4 = locked lock, will deposit into mveNFT below
        vm.startPrank(address(actors[3]));
        VELO.approve(address(escrow), TOKEN_1 * 5);
        tokenId = escrow.createLock(TOKEN_1 * 5, WEEK * (52 * 4));
        ownerToId[actors[3]] = tokenId;
        numActors++;
        vm.stopPrank();

        // actor5 = permanent lock
        vm.startPrank(actors[4]);
        VELO.approve(address(escrow), TOKEN_1 * 6);
        tokenId = escrow.createLock(TOKEN_1 * 6, WEEK);
        escrow.lockPermanent(tokenId);
        permanentLocks.add(actors[4]);
        ownerToId[actors[4]] = tokenId;
        numActors++;
        vm.stopPrank();

        // actor6 = managed lock used for deposits
        vm.startPrank(voter.governor());
        tokenId = escrow.createManagedLockFor(actors[5]);
        mTokenId = tokenId;
        permanentLocks.add(actors[5]);
        ownerToId[actors[5]] = tokenId;
        numActors++;
        mTokenIds.push(tokenId);
        mTokenIdsLength++;
        vm.stopPrank();

        // actor7 = managed lock, will remain empty
        vm.startPrank(voter.governor());
        tokenId = escrow.createManagedLockFor(actors[6]);
        permanentLocks.add(actors[6]);
        ownerToId[actors[6]] = tokenId;
        numActors++;
        mTokenIds.push(tokenId);
        mTokenIdsLength++;
        vm.stopPrank();

        // actor3 deposits into mveNFT owned by actor6
        vm.startPrank(actors[3]);
        voter.depositManaged(ownerToId[actors[3]], mTokenId);
        vm.stopPrank();
    }
}
