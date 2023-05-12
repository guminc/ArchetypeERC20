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
	uint256 rewardsWeightPerDay; // Bps
	uint256 rewardsDistributionStarted;
	mapping (uint40 => uint40) lastTimeClaimed;
}

contract RewardsDistributor {
    
    mapping (address => RewardedNftHoldingConfig) nftHoldingRewardsConfigFor;
    mapping (address => WeightedRewardedAuctionConfig) auctionRewardsConfigFor;
   
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
        uint256 rewardsWeightPerDay
    ) external {
        require(Ownable(rewardToken).owner() == msg.sender);
        RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardToken];
        conf.isEnabled = true;
        conf.nftContract = nftToHold;
        conf.rewardsWeightPerDay = rewardsWeightPerDay;
        conf.rewardsDistributionStarted = block.timestamp;
    }

    function disableRewardsForHoldingNft(address rewardToken) external {
        require(Ownable(rewardToken).owner() == msg.sender);
        nftHoldingRewardsConfigFor[rewardToken].isEnabled = false;
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
        IRewardToken token = IRewardToken(rewardToken);
		WeightedRewardedAuctionConfig storage conf = auctionRewardsConfigFor[rewardToken];

		if (!conf.isEnabled) revert RewardModelDisabled();

		ISharesHolder auction = ISharesHolder(conf.auctionContract);
		uint256 shares = auction.getAndClearSharesFor(msg.sender);
	    
        if (!verify(proof, msg.sender, timesConditionMet, conf.weightedVariableRoot))
			timesConditionMet = 0;
		
        _tryToReward(
            token, 
            min(_calcAuctionRewards(conf, timesConditionMet, shares), token.rewardsLeftToMint()),
            msg.sender
        );
	}


    // TODO hard test this, its dangerous code
	/**
     * @dev This method will reward `msg.sender` based on how long has he held the nft
     * associated with the `rewardToken` via the `nftHoldingRewardsConfigFor` mapping.
	 * @param ids Array with all the nft ids to claim the rewards for.
	 */
	function claimRewardsForNftsHeld(
		address rewardToken, uint16[] calldata ids
	) public {
        IRewardToken token = IRewardToken(rewardToken);
		RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardToken];

		if (!conf.isEnabled) revert RewardModelDisabled();

		uint256 amountToClaim;

		for (uint16 i; i < ids.length; ) {
			if (IERC721(conf.nftContract).ownerOf(ids[i]) != msg.sender)
				revert OwnershipError(conf.nftContract, ids[i]);

			amountToClaim += _calcNftHoldingRewards(conf, ids[i]);
			conf.lastTimeClaimed[ids[i]] = SafeCastLib.toUint40(block.timestamp);
		}
	    
        _tryToReward(token, amountToClaim, msg.sender);
	}
    
    /**
     * @dev This method will try to use its own `rewardToken`s holdings
     * to pay for rewards. If its not holding any `rewardToken`s then
     * it will try to mint some. In this way you can manually fund the
     * contract with already existing `rewardToken`s that don't
     * necessarily implement the `IRewardToken` interface.
     */
    function _tryToReward(
        IRewardToken rewardToken, uint256 amountToClaim, address to 
    ) private {
		amountToClaim = min(amountToClaim, rewardToken.rewardsLeftToMint());
        uint256 availableRewards = min(rewardToken.balanceOf(address(this)), amountToClaim);

        if (availableRewards > 0) {
            rewardToken.transfer(to, availableRewards);
            amountToClaim -= availableRewards;
        }
        if (amountToClaim > 0 && rewardToken.isRewardsMinter(address(this))) {
            uint256 amountToMint = min(amountToClaim, rewardToken.rewardsLeftToMint());
            if (amountToMint == 0) return;
            rewardToken.mintRewards(to, amountToMint);
        }
    }

    /********************\
	|* Helper Functions *|
	\********************/
	function max(uint256 a, uint256 b) public pure returns (uint256) {
		return a >= b ? a : b;
	}

	function min(uint256 a, uint256 b) public pure returns (uint256) {
		return a >= b ? b : a;
	}
    
    // TODO Test if the following helper functions cost a lot of gas :(.
    /*
     * @dev Computes the rewards for a single `config.nftContract`
     * with token id `id`.
     */
    function _calcNftHoldingRewards(
        RewardedNftHoldingConfig storage config, uint16 id
    ) internal view returns (uint256) {
		return _timeSinceLastClaim(config, id) * config.rewardsWeightPerDay / 1 days;
    }

    function _calcAuctionRewards(
        WeightedRewardedAuctionConfig storage config, uint256 timesConditonMet, uint256 shares
	) internal view returns (uint256) {
		uint256 baseAmount = shares * config.baseRewardsWeight / 10000;
		return baseAmount * (
			1 + timesConditonMet * config.extraRewardsWeight / 10000
		);
	}

    /**
     * @dev It will return the time passed since the last claim for an
     * `config.nftContract` with token id `id`.
     */
    function _timeSinceLastClaim(
        RewardedNftHoldingConfig storage config, uint16 id
    ) private view returns (uint256) {
        return block.timestamp - max(
            config.rewardsDistributionStarted, config.lastTimeClaimed[id]
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
}
