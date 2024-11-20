// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGovernorProposalWindow {
    /// @notice The proposal window to be set is invalid.
    error InvalidProposalWindow();

    /// @notice Emitted when the proposal window length is updated.
    event ProposalWindowSet(uint256 indexed oldProposalWindow, uint256 indexed newProposalWindow);

    /// @notice Duration of proposal window, measured in hours.
    /// @dev Proposals can only be created by owner during proposal window.
    function proposalWindow() external view returns (uint256);

    /// @notice Updates the length of the proposal window.
    /// @dev If `proposalWindow` is set to 0, proposal creation is permissionless.
    function setProposalWindow(uint256 _proposalWindow) external;
}
