// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fake pair used to create the gauge which directs all emissions of velo v1 to the SinkManager
/// @dev Used in voter v1
contract SinkDrain is ERC20 {
    address public sinkManager;

    constructor(address _sinkManager) ERC20("SinkDrain", "DRAIN") {
        sinkManager = _sinkManager;

        // Mint to sinkManager so that it can provide all the liquidity
        _mint(sinkManager, 1e18);
    }
}
