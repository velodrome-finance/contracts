// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Forwarder} from "@opengsn/contracts/src/forwarder/Forwarder.sol";

contract VeloForwarder is Forwarder {
    constructor() Forwarder() {}
}
