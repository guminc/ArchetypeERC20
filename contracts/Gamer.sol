// SPDX-License-Identifier: MIT
// Archetype ERC20
//
//        d8888                 888               888
//       d88888                 888               888
//      d88P888                 888               888
//     d88P 888 888d888 .d8888b 88888b.   .d88b.  888888 888  888 88888b.   .d88b.
//    d88P  888 888P"  d88P"    888 "88b d8P  Y8b 888    888  888 888 "88b d8P  Y8b
//   d88P   888 888    888      888  888 88888888 888    888  888 888  888 88888888
//  d8888888888 888    Y88b.    888  888 Y8b.     Y88b.  Y88b 888 888 d88P Y8b.
// d88P     888 888     "Y8888P 888  888  "Y8888   "Y888  "Y88888 88888P"   "Y8888
//                                                            888 888
//                                                       Y8b d88P 888
//                                                        "Y88P"  888

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IRewardToken.sol";


error MintLocked();
error OwnerMintLocked();
error NotAMinter(address triedToMint);
error MaxRewardsExceded();
error OwnershipError(address forToken, uint256 withId);

struct Config {
	bool mintLocked;
	bool ownerMintLocked;
    bool rewardsMintersLocked;
	uint96 maxSupply;
}

contract Gamer is Ownable, ERC20 {
    
    struct Uint32Map {
        uint256 spacer;
    }

    // TODO Fix storage layout.
    Config config;
    Uint32Map private _packedLastTimeClaimed;
    uint256 rewardsPerDay;
    uint256 deploymentTime;

    address kawamii;

	constructor() ERC20("MiladyMakerParty", "MPARTY") {}

	function setMaxSupply(uint96 maxSupply) public onlyOwner {
        require(maxSupply >= totalSupply(), "Max supply can't be below current supply");
		config.maxSupply = maxSupply;
	}
	
	function _mint(address account, uint256 amount) internal virtual override {
		if (config.mintLocked) revert MintLocked();
		super._mint(account, amount);
	}

	function ownerMint(address account, uint256 amount) public onlyOwner {
		if (config.ownerMintLocked) revert OwnerMintLocked();
        _mint(account, amount);
	}

    function claimRewardsForNftsHeld(uint256[] calldata ids) public {
        // TODO Add lock.
        uint256 amountToClaim;
        
        for (uint256 i; i < ids.length; ) {
            if (IERC721(kawamii).ownerOf(ids[i]) != msg.sender)
				revert OwnershipError(kawamii, ids[i]);
            
            // Update amount to claim.
            { 
                uint32 lastTimeClaimed = _getLastTimeClaimed(ids[i]);
                if (lastTimeClaimed > 0) {
                    // Calc rewards relative to distribution start.
                    amountToClaim += (block.timestamp - deploymentTime) * rewardsPerDay / 1 days;
                } else {
                    // Calc rewards relative to last claim
                    amountToClaim += (block.timestamp - lastTimeClaimed) * rewardsPerDay / 1 days;
                }
            }

            _setLastTimeClaimed(ids[i], uint32(block.timestamp));

            unchecked { i++; }
        }

        if (amountToClaim + totalSupply() > config.maxSupply) {
            amountToClaim = config.maxSupply - totalSupply();
        }

        _mint(msg.sender, amountToClaim);
    }

    function _setLastTimeClaimed(uint256 index, uint32 value) internal {
        assembly {
            let s := add(shl(96, _packedLastTimeClaimed.slot), shr(3, index)) // Storage slot.
            let o := shl(5, and(index, 7)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            let m := 0xffffffff // Value mask.
            sstore(s, xor(v, shl(o, and(m, xor(shr(o, v), value)))))
        }
    }

    function _getLastTimeClaimed(uint256 index) internal view returns (uint32 result) {
        assembly {
            let s := add(shl(96, _packedLastTimeClaimed.slot), shr(3, index)) // Storage slot.
            result := and(0xffffffff, shr(shl(5, and(index, 7)), sload(s)))
        }
    }

    // Contract Locks.
    function lockMintsForever() external onlyOwner {
        config.mintLocked = true; 
    }

    function lockOwnerMintsForever() external onlyOwner {
        config.ownerMintLocked = true; 
    }

    function lockRewardsMintersForever() external onlyOwner {
        config.rewardsMintersLocked = true; 
    }

}
