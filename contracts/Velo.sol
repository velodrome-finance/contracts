// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IVelo} from "./interfaces/IVelo.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract Velo is IVelo, ERC20Votes {
    address public minter;
    address private owner;
    address public sinkManager;

    constructor() ERC20("VelodromeV2", "VELO") ERC20Permit("VelodromeV2") {
        minter = msg.sender;
        owner = msg.sender;
    }

    // No checks as its meant to be once off to set minting rights to BaseV1 Minter
    function setMinter(address _minter) external {
        require(msg.sender == minter, "Velo: not minter");
        minter = _minter;
    }

    function setSinkManager(address _sinkManager) external {
        require(msg.sender == owner, "Velo: not owner");
        require(sinkManager == address(0), "Velo: sink manager already set");
        sinkManager = _sinkManager;
    }

    function mint(address account, uint256 amount) external returns (bool) {
        require(msg.sender == minter || msg.sender == sinkManager, "Velo: not minter or sink manager");
        _mint(account, amount);
        return true;
    }
}
