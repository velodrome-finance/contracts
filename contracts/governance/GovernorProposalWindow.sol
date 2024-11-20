// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IGovernorProposalWindow} from "./IGovernorProposalWindow.sol";
import {GovernorSimple} from "./GovernorSimple.sol";

import {VelodromeTimeLibrary} from "../libraries/VelodromeTimeLibrary.sol";

abstract contract GovernorProposalWindow is GovernorSimple, IGovernorProposalWindow {
    /// @inheritdoc IGovernorProposalWindow
    uint256 public proposalWindow = 24 hours;

    /// @inheritdoc GovernorSimple
    function propose(
        uint256 tokenId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        /// @dev Proposal creation is permissionless after `epochStart + proposalWindow`
        if (block.timestamp < VelodromeTimeLibrary.epochStart(block.timestamp) + proposalWindow) {
            _checkOwner();
        }
        return super.propose(tokenId, targets, values, calldatas, description);
    }

    /// @inheritdoc IGovernorProposalWindow
    function setProposalWindow(uint256 _proposalWindow) external onlyOwner {
        if (_proposalWindow > 24) revert InvalidProposalWindow();
        uint256 oldProposalWindow = proposalWindow;
        proposalWindow = _proposalWindow * 1 hours;
        emit ProposalWindowSet({oldProposalWindow: oldProposalWindow / 1 hours, newProposalWindow: _proposalWindow});
    }
}
