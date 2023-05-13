// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MinimalErc20 is ERC20, Ownable {
    constructor(uint256 supp) ERC20("MinimalErc20", "MIN20") {
        _mint(msg.sender, supp);
    }
}


