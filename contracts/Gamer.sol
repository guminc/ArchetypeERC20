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

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/utils/MerkleProofLib.sol";


error MintLocked();
error OwnerMintLocked();
error RewardsMintLocked();
error OwnershipError(address forToken, uint256 withId);
error FreeClaimsLocked();
error FreeTokensAlreadyClaimed();
error NonEligibleForFreeClaim();

struct Config {
	uint96 maxSupply;
    uint96 rewardsPerDay;
    uint32 deploymentTime;
    // TODO Use flags.
	bool ownerMintLocked;
    bool rewardsMintLocked;
    bool freeClaimsLocked;
    bool maxSupplyLocked;
    bool rewardsPerDayLocked;
}

contract Gamer is Ownable, ERC20 {
    
    struct Uint32Map {
        uint256 spacer;
    }

    Config private _config;
    Uint32Map private _packedLastTimeClaimed;

    mapping (address => bool) private _userAlreadyClaimedFreeTokens;
    bytes32 freeClaimRoot;

    address immutable private _kawamii;

	constructor(
        address kawamii, uint96 maxSupply, uint96 rewardsPerDay
    ) Ownable(msg.sender) ERC20("GamerToken", "GAMER") {
        require(maxSupply > 0);
        require(rewardsPerDay > 0);

        _config.deploymentTime = uint32(block.timestamp);
        _config.maxSupply = maxSupply;
        _config.rewardsPerDay = rewardsPerDay;

        _kawamii = kawamii;
    }

	function setMaxSupply(uint96 maxSupply) external onlyOwner {
        require(_config.maxSupplyLocked);
        require(maxSupply > 0);
        require(maxSupply >= totalSupply());
		_config.maxSupply = maxSupply;
	}

    function setRewardsPerDay(uint96 rewardsPerDay) external onlyOwner {
        require(_config.rewardsPerDayLocked);
        require(rewardsPerDay > 0);
        _config.rewardsPerDay = rewardsPerDay;
    }

	function ownerMint(address account, uint256 amount) public onlyOwner {
		if (_config.ownerMintLocked) revert OwnerMintLocked();
        _mint(account, amount);
	}

    function claimRewardsForNftsHeld(uint256[] calldata ids) public {
        uint256 amountToClaim;

        if (_config.rewardsMintLocked) revert RewardsMintLocked();
        
        for (uint256 i; i < ids.length; ) {
            if (IERC721(_kawamii).ownerOf(ids[i]) != msg.sender)
				revert OwnershipError(_kawamii, ids[i]);
            
            // Update amount to claim.
            uint32 lastTimeClaimed = _getLastTimeClaimed(ids[i]);
            unchecked {
                if (lastTimeClaimed == 0) {
                    // Calc rewards relative to distribution start.
                    // Wont overflow because:
                    // - `deploymentTime < block.timestamp` always.
                    // - timestamps fit in `uint32`.
                    // - `rewardsPerDay` is `uint96`.
                    // - Thus, `2**96 * 2**32 <<< 2**256`.
                    amountToClaim += (
                        block.timestamp - _config.deploymentTime
                    ) * _config.rewardsPerDay / 1 days;
                } else {
                    // Calc rewards relative to last claim.
                    // Wont overflow becuase `lastTimeClaimed` will
                    // always be a valid timestamp.
                    amountToClaim += (
                        block.timestamp - lastTimeClaimed
                    ) * _config.rewardsPerDay / 1 days;
                }
            }

            _setLastTimeClaimed(ids[i], uint32(block.timestamp));

            unchecked { i++; }
        }

        unchecked {
            // `maxSupply >= totalSupply` is invariant, thus it wont overflow.
            uint256 maxPossibleAmountToClaim = _config.maxSupply - totalSupply();
            if (amountToClaim > maxPossibleAmountToClaim) {
                amountToClaim = maxPossibleAmountToClaim;
            }
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
    
    function claimFreeTokens(address user, uint96 amountToClaim, bytes32[] memory proof) external {
        if (_config.freeClaimsLocked) 
            revert FreeClaimsLocked();
        if (_userAlreadyClaimedFreeTokens[user]) 
            revert FreeTokensAlreadyClaimed();

        _userAlreadyClaimedFreeTokens[user] = true;

        if (!MerkleProofLib.verify(
            proof, freeClaimRoot, keccak256(abi.encodePacked(user, amountToClaim))
        )) revert NonEligibleForFreeClaim();

        unchecked {
            // `maxSupply >= totalSupply` is invariant, thus it wont overflow.
            uint96 maxPossibleAmountToClaim = uint96(_config.maxSupply - totalSupply());
            if (amountToClaim > maxPossibleAmountToClaim) {
                amountToClaim = maxPossibleAmountToClaim;
            }
        }

        _mint(user, amountToClaim);
    }

    // Contract Locks.
    function lockOwnerMintsForever() external onlyOwner {
        _config.ownerMintLocked = true; 
    }

    function lockRewardsMintForever() external onlyOwner {
        _config.rewardsMintLocked = true;
    }

    function lockFreeClaimsForever() external onlyOwner {
        _config.freeClaimsLocked = true;
    }

    function lockMaxSupplyForever() external onlyOwner {
        _config.maxSupplyLocked = true; 
    }

    function lockRewardsPerDayForever() external onlyOwner {
        _config.rewardsPerDayLocked = true; 
    }
}
