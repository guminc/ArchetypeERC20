// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MinimalErc721 is ERC721, Ownable {
    constructor() Ownable(msg.sender) ERC721("MinimalErc721", "MIN721") {}

    function mint(address to, uint256 id) public onlyOwner {
        _safeMint(to, id);
    }
}


