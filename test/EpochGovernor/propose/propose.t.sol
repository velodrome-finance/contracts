// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseTest.sol";

contract ProposeTest is BaseTest {
    modifier whenTimestampIsSmallerThanEndOfProposalWindow() {
        skipToNextEpoch(0);
        _;
    }

    function test_WhenCallerIsNotTheOwner() external whenTimestampIsSmallerThanEndOfProposalWindow {
        // It should revert with {OwnableUnauthorizedAccount}
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        vm.prank(address(owner2));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(owner2)));
        epochGovernor.propose({
            _tokenId: 1,
            _targets: targets,
            _values: values,
            _calldatas: calldatas,
            _description: description
        });
    }

    modifier whenCallerIsTheOwner() {
        vm.startPrank(address(owner));
        _;
    }

    function test_WhenTheDescriptionIsNotValid()
        external
        whenTimestampIsSmallerThanEndOfProposalWindow
        whenCallerIsTheOwner
    {
        // It should revert with {GovernorRestrictedProposer}
    }

    modifier whenTheDescriptionIsValid() {
        _;
    }

    function test_WhenTheProposerVotingPowerIsSmallerThanTheProposalThreshold()
        external
        whenTimestampIsSmallerThanEndOfProposalWindow
        whenCallerIsTheOwner
        whenTheDescriptionIsValid
    {
        // It should revert with {GovernorInsufficientProposerVotes}
    }

    modifier whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold() {
        _;
    }

    function test_WhenThereIsAProposalActiveForTheCurrentEpoch()
        external
        whenTimestampIsSmallerThanEndOfProposalWindow
        whenCallerIsTheOwner
        whenTheDescriptionIsValid
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold
    {
        // It should revert with {GovernorUnexpectedProposalState}
    }

    modifier whenThereIsNoProposalActiveForTheCurrentEpoch() {
        _;
    }

    function test_WhenTheLengthOfAllParametersIsNot1()
        external
        whenTimestampIsSmallerThanEndOfProposalWindow
        whenCallerIsTheOwner
        whenTheDescriptionIsValid
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold
        whenThereIsNoProposalActiveForTheCurrentEpoch
    {
        // It should revert with {GovernorInvalidProposalLength}
    }

    modifier whenTheLengthOfAllParametersIs1() {
        _;
    }

    function test_WhenTheTargetIsNotMinter()
        external
        whenTimestampIsSmallerThanEndOfProposalWindow
        whenCallerIsTheOwner
        whenTheDescriptionIsValid
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold
        whenThereIsNoProposalActiveForTheCurrentEpoch
        whenTheLengthOfAllParametersIs1
    {
        // It should revert with {GovernorInvalidTargetOrCalldata}
    }

    modifier whenTheTargetIsMinter() {
        _;
    }

    function test_WhenFunctionToCallIsNotNudge()
        external
        whenTimestampIsSmallerThanEndOfProposalWindow
        whenCallerIsTheOwner
        whenTheDescriptionIsValid
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold
        whenThereIsNoProposalActiveForTheCurrentEpoch
        whenTheLengthOfAllParametersIs1
        whenTheTargetIsMinter
    {
        // It should revert with {GovernorInvalidTargetOrCalldata}
    }

    function test_WhenFunctionToCallIsNudge()
        external
        whenTimestampIsSmallerThanEndOfProposalWindow
        whenCallerIsTheOwner
        whenTheDescriptionIsValid
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold
        whenThereIsNoProposalActiveForTheCurrentEpoch
        whenTheLengthOfAllParametersIs1
        whenTheTargetIsMinter
    {
        // It should set epochAlreadyActive to true for the current epoch
        // It should store the proposer address
        // It should store the vote start timestamp
        // It should store the vote duration
        // It should emit a {ProposalCreated} event
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        uint256 expectedSnapshot = block.timestamp + 1 hours;
        uint256 expectedDeadline = expectedSnapshot + 1 weeks - 2 hours;
        uint256 expectedPid = epochGovernor.hashProposal({
            _targets: targets,
            _values: values,
            _calldatas: calldatas,
            _descriptionHash: bytes32(expectedDeadline)
        });

        vm.expectEmit(address(epochGovernor));
        emit IGovernor.ProposalCreated({
            _proposalId: expectedPid,
            _proposer: address(owner),
            _targets: targets,
            _values: values,
            _signatures: new string[](targets.length),
            _calldatas: calldatas,
            _voteStart: expectedSnapshot,
            _voteEnd: expectedDeadline,
            _description: description
        });
        uint256 pid = epochGovernor.propose({
            _tokenId: 1,
            _targets: targets,
            _values: values,
            _calldatas: calldatas,
            _description: description
        });
        assertEq(pid, expectedPid);
        assertEq(epochGovernor.proposalProposer(pid), address(owner));
        assertEq(epochGovernor.proposalSnapshot(pid), expectedSnapshot + 2);
        assertEq(epochGovernor.proposalDeadline(pid), expectedDeadline + 2);
    }

    modifier whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow() {
        skip(epochGovernor.proposalWindow());
        /// @dev Propose calls are permissionless after `proposalWindow`
        vm.startPrank(address(owner2));
        _;
    }

    function test_WhenTheDescriptionIsNotValid_() external whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow {
        // It should revert with {GovernorRestrictedProposer}
    }

    modifier whenTheDescriptionIsValid_() {
        _;
    }

    function test_WhenTheProposerVotingPowerIsSmallerThanTheProposalThreshold_()
        external
        whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow
        whenTheDescriptionIsValid_
    {
        // It should revert with {GovernorInsufficientProposerVotes}
    }

    modifier whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold_() {
        _;
    }

    function test_WhenThereIsAProposalActiveForTheCurrentEpoch_()
        external
        whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow
        whenTheDescriptionIsValid_
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold_
    {
        // It should revert with {GovernorUnexpectedProposalState}
    }

    modifier whenThereIsNoProposalActiveForTheCurrentEpoch_() {
        _;
    }

    function test_WhenTheLengthOfAllParametersIsNot1_()
        external
        whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow
        whenTheDescriptionIsValid_
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold_
        whenThereIsNoProposalActiveForTheCurrentEpoch_
    {
        // It should revert with {GovernorInvalidProposalLength}
    }

    modifier whenTheLengthOfAllParametersIs1_() {
        _;
    }

    function test_WhenTheTargetIsNotMinter_()
        external
        whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow
        whenTheDescriptionIsValid_
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold_
        whenThereIsNoProposalActiveForTheCurrentEpoch_
        whenTheLengthOfAllParametersIs1_
    {
        // It should revert with {GovernorInvalidTargetOrCalldata}
    }

    modifier whenTheTargetIsMinter_() {
        _;
    }

    function test_WhenFunctionToCallIsNotNudge_()
        external
        whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow
        whenTheDescriptionIsValid_
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold_
        whenThereIsNoProposalActiveForTheCurrentEpoch_
        whenTheLengthOfAllParametersIs1_
        whenTheTargetIsMinter_
    {
        // It should revert with {GovernorInvalidTargetOrCalldata}
    }

    function test_WhenFunctionToCallIsNudge_()
        external
        whenTimestampIsGreaterThanOrEqualToEndOfProposalWindow
        whenTheDescriptionIsValid_
        whenTheProposerVotingPowerIsGreaterThanOrEqualToTheProposalThreshold_
        whenThereIsNoProposalActiveForTheCurrentEpoch_
        whenTheLengthOfAllParametersIs1_
        whenTheTargetIsMinter_
    {
        // It should set epochAlreadyActive to true for the current epoch
        // It should store the proposer address
        // It should store the vote start timestamp
        // It should store the vote duration
        // It should emit a {ProposalCreated} event
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        uint256 expectedSnapshot = block.timestamp;
        uint256 expectedDeadline = VelodromeTimeLibrary.epochVoteEnd(block.timestamp);
        uint256 expectedPid = epochGovernor.hashProposal({
            _targets: targets,
            _values: values,
            _calldatas: calldatas,
            _descriptionHash: bytes32(expectedDeadline)
        });

        vm.expectEmit(address(epochGovernor));
        emit IGovernor.ProposalCreated({
            _proposalId: expectedPid,
            _proposer: address(owner2),
            _targets: targets,
            _values: values,
            _signatures: new string[](targets.length),
            _calldatas: calldatas,
            _voteStart: expectedSnapshot,
            _voteEnd: expectedDeadline,
            _description: description
        });
        uint256 pid = epochGovernor.propose({
            _tokenId: 1,
            _targets: targets,
            _values: values,
            _calldatas: calldatas,
            _description: description
        });
        assertEq(pid, expectedPid);
        assertEq(epochGovernor.proposalProposer(pid), address(owner2));
        assertEq(epochGovernor.proposalSnapshot(pid), expectedSnapshot + 2);
        assertEq(epochGovernor.proposalDeadline(pid), expectedDeadline + 2);
    }
}
