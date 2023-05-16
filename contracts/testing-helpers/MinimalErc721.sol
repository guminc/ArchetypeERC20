// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../IMintTimeSaver.sol";

contract MinimalErc721 is ERC721, Ownable, IMintTimeSaver {
    
    // TODO optimize mapping types.
    mapping (uint256 => uint256) private _mintTimeFor;

    constructor() ERC721("MinimalErc721", "MIN721") {}

    function mint(address to, uint256 id) public onlyOwner {
        _safeMint(to, id);
        _mintTimeFor[id] = block.timestamp;
    }

    function getMintTimeFor(uint256 tokenId) external view returns (uint256) {
        return _mintTimeFor[tokenId];
    }
}


