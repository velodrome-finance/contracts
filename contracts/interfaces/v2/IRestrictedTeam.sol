// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVotingEscrow} from "../IVotingEscrow.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IRestrictedTeam {
    error NotTeam();

    /// @notice Address of the VotingEscrow contract.
    function escrow() external view returns (IVotingEscrow);

    /// @notice Address of the factory registry contract.
    function factoryRegistry() external view returns (Ownable);

    /// @notice Set art proxy address
    /// @dev Only callable by factory registry owner
    function setArtProxy(address _proxy) external;
}
