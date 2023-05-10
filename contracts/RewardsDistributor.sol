// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/utils/SafeCastLib.sol";
import "./IRewardToken.sol";

error RewardModelDisabled();
error MaxSupplyExceded(address rewardToken);
error OwnershipError(address forToken, uint256 withId);

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
    
    function configRewardsForHoldingNft(
        address rewardedToken,
        address nftToHold,
        uint256 rewardsWeightPerDay
    ) external {
        require(Ownable(rewardedToken).owner() == msg.sender);
        RewardedNftHoldingConfig storage conf = nftHoldingRewardsConfigFor[rewardedToken];
        conf.isEnabled = true;
        conf.nftContract = nftToHold;
        conf.rewardsWeightPerDay = rewardsWeightPerDay;
        conf.rewardsDistributionStarted = block.timestamp;
    }

    function disableRewardsForHoldingNft(address rewardedToken) external {
        require(Ownable(rewardedToken).owner() == msg.sender);
        nftHoldingRewardsConfigFor[rewardedToken].isEnabled = false;
    }

    // TODO hard test this, its dangerous code
	/**
     * @dev This method will try to use its own `rewardToken`s holdings
     * to pay for rewards. If its not holding any `rewardToken`s then
     * it will try to mint some. In this way you can manually fund the
     * contract with already existing `rewardToken`s that don't
     * necessarily implement the `IRewardToken` interface.
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
		
		amountToClaim = min(amountToClaim, token.rewardsLeftToMint());
        uint256 availableRewards = min(token.balanceOf(address(this)), amountToClaim);
        
        if (availableRewards > 0) {
            token.transfer(msg.sender, availableRewards);
            amountToClaim -= availableRewards;
        }
        if (amountToClaim > 0 && token.isRewardsMinter(address(this))) {
            uint256 amountToMint = min(amountToClaim, token.rewardsLeftToMint());
            if (amountToMint == 0) return;
            token.mintRewards(msg.sender, amountToMint);
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
    ) private view returns (uint256) {
		return _timeSinceLastClaim(config, id) * config.rewardsWeightPerDay / 1 days;
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
}
