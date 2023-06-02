// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/utils/SafeCastLib.sol";
import "solady/src/utils/MerkleProofLib.sol";
import "./IRewardToken.sol";

error RewardModelDisabled();
error MaxSupplyExceded(address rewardToken);
error OwnershipError(address forToken, uint256 withId);
error WrongRewardConfig();
error AuctionContractNotConfigured();

/**
 * @dev Rewards will be distributed based on `nftContract` holds.
 * @param rewardsDistributionStarted Will return a timestamp when the
 * rewards were configured (or set) so `lastTimeCreated` can be computed.
 * @param lastTimeClaimed Will return when was the last time that
 * the rewards for a token id were claimed.
 */
struct RewardedNftHoldingConfig {
	bool isEnabled;
    address rewardsToken;
	address nftContract;
    // Wont overflow: 1 MPARTY for 1000 years is (10**18)*(365*1000) <<< 2**96-1.
	uint96 rewardsPerDay; // In Wei
	uint256 rewardsDistributionStarted;
	mapping (uint256 => uint256) lastTimeClaimed; 
}

contract MPartyRewardsDistributor {
    
    RewardedNftHoldingConfig public config;

    /**
     * @param rewardsToken Is the `IRewardToken` such that 
     * `IRewardToken(rewardToken).isRewardsMinter(address(this))`.
     * @param nftToHold Is the NFT address to hold to get rewarded.
     * @param rewardsPerDay Is the amount of reward tokens that will 
     * be distributed to the NFT holders per day, in WEI. Generally,
     * for $MPARTY, it will be 10**18, so if you own 3 Milady Maker 
     * Party NFTs, you will get 3 $MPARTY tokens per day.
     * @param rewardsDistributionStartTime Is the unix timestamp when
     * the rewards distribution starts. Usually it will be equal to
     * `block.timestamp`.
     */
    function configRewardsForHoldingNft(
        address rewardsToken,
        address nftToHold,
        uint96 rewardsPerDay,
        uint256 rewardsDistributionStartTime
    ) public {
        require(Ownable(rewardsToken).owner() == msg.sender);
        require(block.timestamp >= rewardsDistributionStartTime);
        config.isEnabled = true;
        config.rewardsToken = rewardsToken;
        config.nftContract = nftToHold;
        config.rewardsPerDay = rewardsPerDay;
        config.rewardsDistributionStarted = rewardsDistributionStartTime;
    }

    function disableRewardsForHoldingNft(address rewardToken) external {
        require(Ownable(rewardToken).owner() == msg.sender);
        config.isEnabled = false;
    }

	/**
     * @dev This method will reward `msg.sender` based on how long has he held the nft
     * associated with the `rewardToken` via the `nftHoldingRewardsConfigFor` mapping.
	 * @param ids Array with all the nft ids to claim the rewards for.
	 */
	function claimRewardsForNftsHeld(uint256[] calldata ids) public {
		if (!config.isEnabled) revert RewardModelDisabled();
        
        // Rewards calculation.
		uint256 amountToClaim;

		for (uint256 i; i < ids.length; i++) {
			if (IERC721(config.nftContract).ownerOf(ids[i]) != msg.sender)
				revert OwnershipError(config.nftContract, ids[i]);

			amountToClaim += _calcNftHoldingRewards(ids[i]);
			config.lastTimeClaimed[ids[i]] = block.timestamp;
		}
	    
        // Rewards distribution.
        IRewardToken token = IRewardToken(config.rewardsToken);
        
        uint256 amountToMint = amountToClaim >= token.supplyLeft() ? token.supplyLeft() : amountToClaim;

        token.mintRewards(msg.sender, amountToMint);
	}

    /********************\
	|* Helper Functions *|
	\********************/
    function lastTimeClaimed(uint256 id) public view returns (uint256) {
        return config.lastTimeClaimed[id];
    }

    function calcNftHoldingRewards(
        uint256[] calldata ids
    ) public view returns (uint256 rewards) {
		for (uint256 i; i < ids.length; i++)
            rewards += _calcNftHoldingRewards(ids[i]);
    }
    
    /*
     * @dev Computes the rewards for a single `config.nftContract` with token id `id`.
     */
    function _calcNftHoldingRewards(uint256 id) private view returns (uint256) {
        uint256 lastClaim = config.rewardsDistributionStarted > config.lastTimeClaimed[id] ?
            config.rewardsDistributionStarted : config.lastTimeClaimed[id];
        return (block.timestamp - lastClaim) * config.rewardsPerDay / 1 days;
    }

}
