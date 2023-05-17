// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../lib/ArchetypeAuction/contracts/ISharesHolder.sol";
import "solady/src/utils/MerkleProofLib.sol";
import "./IRewardToken.sol";


error MintLocked();
error OwnerMintLocked();
error NotAMinter(address triedToMint);
error MaxRewardsExceded();

struct Config {
	bool mintLocked;
	bool ownerMintLocked;
	uint256 maxSupply;
}

contract ArchetypeERC20 is Ownable, ERC20, IRewardToken {
    
    Config config;
    mapping (address => bool) private _isRewardsMinter;

	// TODO add cute UTFs and asciis to the code and test them on etherscan (Critical).
	/*****************************************************\
	|* Contract Initialization And Configuration Methods *|
	\*****************************************************/
	constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

	function setMaxSupply(uint256 maxSupply) public onlyOwner {
        require(maxSupply >= totalSupply(), "Max supply can't be below current supply");
		config.maxSupply = maxSupply;
	}
	
	/********************\
	|* Minting  Methods *|
	\********************/
	function _mint(address account, uint256 amount) internal virtual override {
		if (config.mintLocked) revert MintLocked();
		super._mint(account, amount);
	}

	function ownerMint(address account, uint256 amount) public onlyOwner() {
		if (config.ownerMintLocked) revert OwnerMintLocked();
        _mint(account, amount);
	}

	/*******************************\
	|* IRewardToken implementation *|
	\*******************************/

    function mintRewards(address account, uint256 amount) external {
        if (!_isRewardsMinter[msg.sender]) revert NotAMinter(msg.sender);
        if (amount > supplyLeft()) revert MaxRewardsExceded();
        _mint(account, amount);
    }

    function isRewardsMinter(address minter) public view returns (bool) {
        return _isRewardsMinter[minter];
    }

    function addRewardsMinter(address minter) external onlyOwner {
        _isRewardsMinter[minter] = true;
    }

    function supplyLeft() public view returns (uint256) {
        return totalSupply() > config.maxSupply ?
            0 : config.maxSupply - totalSupply();  
    }

}
