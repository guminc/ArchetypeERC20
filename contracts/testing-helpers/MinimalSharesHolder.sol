// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "../../lib/ArchetypeAuction/contracts/ISharesHolder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MinimalSharesHolder is ISharesHolder, Ownable {
    
    mapping (address => bool) private _isSharesUpdater;
    mapping (address => uint256) public _sharesFor;

	function addSharesUpdater(address updater) external onlyOwner {
        _isSharesUpdater[updater] = true;    
    }

	function getAndClearSharesFor(address user) 
        external 
        onlyOwner 
        returns (uint256 shares) 
    {
        require(_isSharesUpdater[msg.sender]);
        shares = _sharesFor[user];
        delete _sharesFor[user];
    }

	function getTokenShares(address user) external view returns (uint256) {
        return _sharesFor[user];
    }

	function getIsSharesUpdater(address updater) external view returns (bool) {
        return _isSharesUpdater[updater];
    }
    
    /**
     * @dev External method to simulate that a `user` has `amount` of shares.
     * For example, in an auction contract, those shares would be automatically
     * updated based on the bid amounts.
     */
    function setSharesFor(address user, uint256 amount) external onlyOwner {
        _sharesFor[user] = amount;
    }
}
