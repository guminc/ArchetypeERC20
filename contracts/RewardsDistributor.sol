// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/utils/SafeCastLib.sol";
import "solady/src/utils/MerkleProofLib.sol";
import "../lib/ArchetypeAuction/contracts/ISharesHolder.sol";
import "./IRewardToken.sol";

error RewardModelDisabled();
error MaxSupplyExceded(address rewardToken);
error OwnershipError(address forToken, uint256 withId);
error WrongRewardConfig();
error AuctionContractNotConfigured();

/**
 * @dev An WeightedRewardedAuction will distribute weighted rewards based on a
 * variable in the `weightedVariableRoot`. For example, if `weightedVariableRoot`
 * defined an mapping between `address bidder` and `uint256 derivsHeld`, and if `sh`
 * were the shares for `bidder`, then the rewards will be calculated as:
 * 
 *    sh * baseRewardWeight * (1 + extraRewardWeight * derivsHeld) 
 *
 * Note that the weights are codified as Bps, so some conversions are required. 
 * @param acutionContract Should implement the ISharesHolder interface so
 * `getAndClaimShares` can be called when implementing rewards claiming logic.
 * @param hasExtraRewards Will determine if the rewards are weighted based on
 * `weightedVariableRoot`. If thats the case, the contract owner should call
 * `configureWeightedAuctionRewards` instead of `configureAuctionRewards`.
 */
struct WeightedRewardedAuctionConfig {
	bool isEnabled;
	bool hasExtraRewards;
	uint256 baseRewardsWeight; // Bps
	uint256 extraRewardsWeight; // Bps
	bytes32 weightedVariableRoot;
	address auctionContract;
}

/**
 * @dev Rewards will be distributed based on `nftContract` holds.
 * @param rewardsDistributionStarted Will return a timestamp when the
 * rewards were configured so `lastTimeCreated` can be computed.
 * @param lastTimeClaimed Will return when was the last time that
 * the rewards for a token id were claimed.
 */
struct RewardedNftHoldingConfig {
	bool isEnabled;
	address nftContract;
	uint256 rewardsWeightPerDay; // In Wei
	uint256 rewardsDistributionStarted;
	mapping (uint40 => uint256) lastTimeClaimed;
}

contract RewardsDistributor {
    
    mapping (address => RewardedNftHoldingConfig) public nftHoldingRewardsConfigFor;
    mapping (address => WeightedRewardedAuctionConfig) public auctionRewardsConfigFor;

	function configureWeightedAuctionRewards(
        address rewardToken,
		uint256 rewardWeight,
		uint256 extraRewardsWeight,
		bytes32 weightedVariableRoot,
		address auctionContract
	) public {
        WeightedRewardedAuctionConfig storage conf = auctionRewardsConfigFor[rewardToken];
		if (extraRewardsWeight == 0 || weightedVariableRoot == bytes32(0)) revert WrongRewardConfig();

		configureAuctionRewards(rewardToken, rewardWeight, auctionContract);
		conf.hasExtraRewards = true;
		conf.extraRewardsWeight = extraRewardsWeight;
		conf.weightedVariableRoot = weightedVariableRoot; 
	}

	function configureAuctionRewards(
        address rewardToken,
		uint256 rewardWeight,
        address auctionContract
	) public {
        require(Ownable(rewardToken).owner() == msg.sender);
        WeightedRewardedAuctionConfig storage conf = auctionRewardsConfigFor[rewardToken];

		if (rewardWeight == 0) revert WrongRewardConfig();
		if (!ISharesHolder(auctionContract).getIsSharesUpdater(address(this))) 
			revert AuctionContractNotConfigured();

		conf.isEnabled = true;
		conf.hasExtraRewards = false;
		conf.baseRewardsWeight = rewardWeight;
		conf.auctionContract = auctionContract;
	}

    function configRewardsForHoldingNft(
        address rewardToken,
        address nftToHold,
        uint256 rewardsWeightPerDay,
        uint40 rewardsDistributionStartTime
    ) public {
        require(Ownable(rewardToken).owner() == msg.sender);
        require(block.timestamp >= rewardsDistributionStartTime);
        RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardToken];
        conf.isEnabled = true;
        conf.nftContract = nftToHold;
        conf.rewardsWeightPerDay = rewardsWeightPerDay;
        conf.rewardsDistributionStarted = rewardsDistributionStartTime;
    }

    function disableRewardsForHoldingNft(address rewardToken) external {
        require(Ownable(rewardToken).owner() == msg.sender);
        nftHoldingRewardsConfigFor[rewardToken].isEnabled = false;
    }
    
    function withdrawRewards(address rewardToken) external {
        require(Ownable(rewardToken).owner() == msg.sender);
        IERC20(rewardToken).transfer(
            msg.sender,
            IERC20(rewardToken).balanceOf(address(this))
        );
    }
    
    /**
     * @dev If the auction rewards are not weighted, we will use the
     * weighted remarding method but with `timesConditionMet = 0`.
     */
    function claimAuctionRewards(address rewardToken) public {
        if (auctionRewardsConfigFor[rewardToken].hasExtraRewards)
            revert RewardModelDisabled();

        bytes32[] memory proof = new bytes32[](1);
        claimWeightedAuctionRewards(rewardToken, proof, 0);
    }

    function claimWeightedAuctionRewards(
		address rewardToken, bytes32[] memory proof, uint96 timesConditionMet
	) public {
		WeightedRewardedAuctionConfig storage conf = auctionRewardsConfigFor[rewardToken];

		if (!conf.isEnabled) revert RewardModelDisabled();

		ISharesHolder auction = ISharesHolder(conf.auctionContract);
		uint256 shares = auction.getAndClearSharesFor(msg.sender);
	    
        if (!verify(proof, msg.sender, timesConditionMet, conf.weightedVariableRoot))
			timesConditionMet = 0;
		
        _tryToReward(
            rewardToken, 
            _calcAuctionRewards(conf, timesConditionMet, shares),
            msg.sender
        );
	}

	/**
     * @dev This method will reward `msg.sender` based on how long has he held the nft
     * associated with the `rewardToken` via the `nftHoldingRewardsConfigFor` mapping.
	 * @param ids Array with all the nft ids to claim the rewards for.
	 */
	function claimRewardsForNftsHeld(
		address rewardToken, uint16[] calldata ids
	) public {
		RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardToken];

		if (!conf.isEnabled) revert RewardModelDisabled();

		uint256 amountToClaim;

		for (uint16 i; i < ids.length; i++) {
			if (IERC721(conf.nftContract).ownerOf(ids[i]) != msg.sender)
				revert OwnershipError(conf.nftContract, ids[i]);

			amountToClaim += _calcNftHoldingRewards(conf, ids[i]);
			conf.lastTimeClaimed[ids[i]] = block.timestamp;
		}
	    
        _tryToReward(rewardToken, amountToClaim, msg.sender);
	}
    
    /**
     * @dev This method will try to use its own `rewardToken`s holdings
     * to pay for rewards. If its not holding any `rewardToken`s then
     * it will try to mint some. In this way you can manually fund the
     * contract with already existing `rewardToken`s that don't
     * necessarily implement the `IRewardToken` interface.
     */
    function _tryToReward(
        address rewardToken, uint256 amountToClaim, address to 
    ) private {
        IRewardToken token = IRewardToken(rewardToken);
        uint256 availableRewards = min(token.balanceOf(address(this)), amountToClaim);

        if (availableRewards > 0) {
            token.transfer(to, availableRewards);
            amountToClaim -= availableRewards;
        }
        
        if (amountToClaim > 0 && token.isRewardsMinter(address(this))) {
            uint256 amountToMint = min(amountToClaim, token.supplyLeft());
            if (amountToMint == 0) return;
            token.mintRewards(to, amountToMint);
        }
    }

    /********************\
	|* Helper Functions *|
	\********************/

    function lastTimeClaimed(address rewardToken, uint16 id) public view returns (uint256) {
		RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardToken];
        return conf.lastTimeClaimed[id];
    }

    function calcNftHoldingRewards(
        address rewardToken, uint40[] calldata ids
    ) public view returns (uint256 rewards) {
        RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardToken];
		for (uint16 i; i < ids.length; i++)
            rewards += _calcNftHoldingRewards(conf, ids[i]);
    }
    
    /*
     * @dev Computes the rewards for a single `config.nftContract` with token id `id`.
     */
    function _calcNftHoldingRewards(
        RewardedNftHoldingConfig storage conf, uint40 id
    ) internal view returns (uint256) {
        uint256 lastClaim = max(conf.rewardsDistributionStarted, conf.lastTimeClaimed[id]);
        return (block.timestamp - lastClaim) * conf.rewardsWeightPerDay / 1 days;
    }

    function getRewardsDistributionStarted(
        address rewardToken
    ) public view returns (uint256) {
		RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardToken];
        return conf.rewardsDistributionStarted;
    }

    function _calcAuctionRewards(
        WeightedRewardedAuctionConfig storage config, uint256 timesConditonMet, uint256 shares
	) internal view returns (uint256) {
		uint256 baseAmount = shares * config.baseRewardsWeight / 10000;
		return baseAmount * (
			1 + timesConditonMet * config.extraRewardsWeight / 10000
		);
	}

	function verify(
		bytes32[] memory proof, address bidder, uint96 timesConditonMet, bytes32 root
	) public pure returns (bool) {
    	if (root == bytes32(0)) return false;
		return MerkleProofLib.verify(
			proof, root, keccak256(abi.encodePacked(bidder, timesConditonMet))
		);
    }

	function max(uint256 a, uint256 b) public pure returns (uint256) {
		return a >= b ? a : b;
	}

	function min(uint256 a, uint256 b) public pure returns (uint256) {
		return a >= b ? b : a;
	}
}
