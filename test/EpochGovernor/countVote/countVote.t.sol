// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

import {EpochGovernorCountingFractional} from "contracts/governance/EpochGovernorCountingFractional.sol";

contract CountVoteTest is BaseTest {
    address[] public targets;
    uint256[] public values;
    bytes[] public calldatas;
    string public description;
    uint256 pid;
    uint256 tokenId;
    uint256 nftBalance;

    function _setUp() public override {
        VELO.approve(address(escrow), 2 * TOKEN_1);
        tokenId = escrow.createLock(2 * TOKEN_1, MAXTIME); // 1
        vm.roll(block.number + 1);

        skipToNextEpoch(0);

        targets = new address[](1);
        targets[0] = address(minter);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);

        description = "";

        pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(1 hours + 2);

        nftBalance = escrow.balanceOfNFT(1);

        skipAndRoll(1); // allow voting
    }

    function test_WhenRemainingWeightIs0() external {
        // It should revert with {GovernorAlreadyCastVote}

        epochGovernor.castVote(pid, tokenId, 1);
        assertEq(epochGovernor.hasVoted(pid, tokenId), true);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, tokenId));
        epochGovernor.castVote(pid, tokenId, 1);
    }

    modifier whenRemainingWeightIsGreaterThan0() {
        _;
    }

    modifier whenCastingANominalVote() {
        _;
    }

    function test_WhenParamsLengthIsNotEmpty() external whenRemainingWeightIsGreaterThan0 whenCastingANominalVote {
        // It should revert with {GovernorInvalidVoteParams}

        bytes memory voteFractionsParam = abi.encodePacked(uint128(0), uint128(0), uint128(0));

        vm.expectRevert(IGovernor.GovernorInvalidVoteParams.selector);
        epochGovernor.castVoteWithReasonAndParams(pid, 1, 1, "", voteFractionsParam);
    }

    function test_WhenParamsIsEmpty() external whenRemainingWeightIsGreaterThan0 whenCastingANominalVote {
        // It should cast a nominal vote for the selected option

        epochGovernor.castVoteWithReasonAndParams(pid, 1, 1, "", bytes(""));

        assertEq(epochGovernor.hasVoted(pid, tokenId), true);
        assertEq(epochGovernor.usedVotes(pid, tokenId), nftBalance);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);

        assertEq(againstVotes, 0);
        assertEq(forVotes, nftBalance);
        assertEq(abstainVotes, 0);
    }

    modifier whenCastingAFractionalVote() {
        _;
    }

    function test_WhenParamsLengthIsInvalid() external whenRemainingWeightIsGreaterThan0 whenCastingAFractionalVote {
        // It should revert with {GovernorInvalidVoteParams}

        bytes memory voteFractionsParam = abi.encodePacked(uint128(0), uint128(0), uint128(0), uint128(0));

        vm.expectRevert(IGovernor.GovernorInvalidVoteParams.selector);
        epochGovernor.castVoteWithReasonAndParams(pid, 1, 255, "", voteFractionsParam);
    }

    modifier whenParamsLengthIsValid() {
        _;
    }

    function test_WhenUsedWeightIsMoreThanRemainingWeight()
        external
        whenRemainingWeightIsGreaterThan0
        whenCastingAFractionalVote
        whenParamsLengthIsValid
    {
        // It should revert with {GovernorExceedRemainingWeight}

        bytes memory voteFractionsParam = abi.encodePacked(uint128(nftBalance), uint128(nftBalance / 3), uint128(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                EpochGovernorCountingFractional.GovernorExceedRemainingWeight.selector,
                1,
                nftBalance + nftBalance / 3,
                nftBalance
            )
        );
        epochGovernor.castVoteWithReasonAndParams(pid, 1, 255, "", voteFractionsParam);
    }

    function test_WhenUsedWeightIsLessThanRemainingWeight()
        external
        whenRemainingWeightIsGreaterThan0
        whenCastingAFractionalVote
        whenParamsLengthIsValid
    {
        // It should update proposal vote details

        bytes memory voteFractionsParam =
            abi.encodePacked(uint128(nftBalance / 3), uint128(nftBalance / 3), uint128(nftBalance / 3));

        vm.expectEmit(address(epochGovernor));
        emit IGovernor.VoteCastWithParams({
            _voter: address(owner),
            _tokenId: tokenId,
            _proposalId: pid,
            _support: 255,
            _weight: nftBalance - 1,
            _reason: "",
            _params: voteFractionsParam
        });
        epochGovernor.castVoteWithReasonAndParams(pid, 1, 255, "", voteFractionsParam); // against: 1/3 for: 1/3 abstain: 1/3

        assertEq(epochGovernor.hasVoted(pid, 1), true);
        assertApproxEqAbs(epochGovernor.usedVotes(pid, 1), nftBalance, 1);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);

        assertEq(againstVotes, nftBalance / 3);
        assertEq(forVotes, nftBalance / 3);
        assertEq(abstainVotes, nftBalance / 3);
    }

    function test_WhenCastingAnInvalidVoteType() external whenRemainingWeightIsGreaterThan0 {
        // It should revert with {GovernorInvalidVoteType}

        bytes memory voteFractionsParam = abi.encodePacked(uint128(nftBalance), uint128(nftBalance / 3), uint128(0));

        vm.expectRevert(IGovernor.GovernorInvalidVoteType.selector);
        epochGovernor.castVoteWithReasonAndParams(pid, 1, 111, "", voteFractionsParam);
    }
}
