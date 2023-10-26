// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {EscrowHandlerForGovernance} from "./EscrowHandlerForGovernance.sol";
import {TimeStore} from "./TimeStore.sol";
import "../BaseTest.sol";

contract GovernorInvariants is BaseTest {
    EscrowHandlerForGovernance public escrowHandler;
    TimeStore public timeStore;
    address public token;

    modifier useCurrentTime() {
        vm.warp(timeStore.currentTimestamp());
        vm.roll(timeStore.currentBlockNumber());
        _;
    }

    function _setUp() public override {
        timeStore = new TimeStore(2);
        escrowHandler = new EscrowHandlerForGovernance(escrow, timeStore, owners);
        token = address(new MockERC20("TEST", "TEST", 18));

        targetContract(address(escrowHandler));

        vm.prank(escrow.team());
        governor.setProposalNumerator(0);
    }

    function invariant_VotesRespectTotalSupplyAtSnapshot() public useCurrentTime {
        uint256 pid = createProposalAndSkipToVotingTime();

        uint256 tokenId = escrow.tokenId();
        address currentOwner;
        // vote with all tokens, including mTokenId
        for (uint256 i = 1; i <= tokenId; i++) {
            currentOwner = escrow.ownerOf(i);
            // try to vote regardless (note 0 balances will revert in practice)
            vm.startPrank(currentOwner);
            try governor.castVote(pid, i, 1) {} catch (bytes memory) {
                // ignore reverts, assumed to be due to zero voting weight, or managed veNFT unable to vote
                continue;
            }
        }

        // In all cases, mTokenVotes is either 0 or delegatedBalance, with votes accounted for elsewhere
        // case 1: mveNFT is not delegating and not receiving delegates, mTokenVotes = 0, votes accounted for in locked nfts
        // case 2: mveNFT is delegating and not receiving delegates, mTokenVotes = 0, votes accounted for in delegatee nft
        // case 3: mveNFT is not delegating and receiving delegates, mTokenVotes = delegatedBalance, votes accounted for in locked nfts
        // case 4: mveNFT is delegating and receiving delegates, mTokenVotes = delegatedBalance, votes accounted for in delegatee nft
        // we use most recent checkpoint as no actions have took place after proposal creation
        uint256 sumDelegatedBalance;
        uint256 mTokenId;
        uint48 checkpoint;
        uint256 mTokenIdLength = escrowHandler.mTokenIdsLength();
        for (uint256 i = 0; i < mTokenIdLength; i++) {
            mTokenId = escrowHandler.mTokenIds(i);
            checkpoint = escrow.numCheckpoints(mTokenId) - 1;
            sumDelegatedBalance += escrow.checkpoints(mTokenId, checkpoint).delegatedBalance;
        }
        (uint256 _againstVotes, uint256 _forVotes, uint256 _abstainVotes) = governor.proposalVotes(pid);
        assertEq(_againstVotes, 0);
        assertEq(
            _forVotes + sumDelegatedBalance,
            escrow.totalSupplyAt(block.timestamp - 1),
            "invariant::sum voting balances at snapshot > total supply at snapshot"
        );
        assertEq(_abstainVotes, 0);
    }

    function createProposalAndSkipToVotingTime() internal returns (uint256 pid) {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(2 days + 1);
    }
}
