// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {XERC20} from "xERC20/solidity/contracts/XERC20.sol";

contract TestXERC20 is XERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        address _factory
    ) XERC20(_name, _symbol, _factory) {}
}
