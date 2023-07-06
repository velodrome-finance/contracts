// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";
import {IRestrictedTeam} from "contracts/interfaces/v2/IRestrictedTeam.sol";

/// @title Velodrome RestrictedTeam contract
/// @author velodrome.finance, @pegahcarter, @figs999
/// @notice Team role for VotingEscrow without toggleSplit(), setTeam() abilities.
/// @dev Uses same owner role as FactoryRegistry
contract RestrictedTeam is IRestrictedTeam, ERC2771Context {
    /// @inheritdoc IRestrictedTeam
    IVotingEscrow public immutable escrow;
    /// @inheritdoc IRestrictedTeam
    Ownable public immutable factoryRegistry;

    /// @param _escrow The VotingEscrow contract
    constructor(address _escrow) ERC2771Context(IVotingEscrow(_escrow).forwarder()) {
        escrow = IVotingEscrow(_escrow);
        factoryRegistry = Ownable(escrow.factoryRegistry());
    }

    /// @inheritdoc IRestrictedTeam
    function setArtProxy(address _proxy) external {
        if (_msgSender() != factoryRegistry.owner()) revert NotTeam();
        escrow.setArtProxy(_proxy);
    }
}
