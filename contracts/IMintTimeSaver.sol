// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMintTimeSaver is IERC721 {
    /**
     * @return Time when a `tokenId` was minted, 0 if it was not.
     */
    function getMintTimeFor(uint256 tokenId) external view returns (uint256);
}
