import { ethers } from 'hardhat';
import { expect } from 'chai';

import { 
    OptPartialApplierRes,
    conditionalPartialApplier,
    getRewardedNftHoldingConfig,
    rewardingForHoldingFactory 
} from '../scripts/helpers'
import { RewardsDistributor } from '../typechain-types';
import { getLastTimestamp, sleep, toWei, fromWei } from '../lib/ArchetypeAuction/scripts/helpers';

describe('RewardsDistributor', async () => {
    
    let nftAndRewardTokenFactory: OptPartialApplierRes<typeof rewardingForHoldingFactory>
    let REWARDS_DISTRIBUTOR: RewardsDistributor

    before(async () => {
        // NOTE that all tests should work using the same `rewardsDistributor`, as it
        // is an singleton.
        const USE_SAME_REWARDS_DISTRIBUTOR_FOR_ALL_TESTS = true;

        REWARDS_DISTRIBUTOR = await ethers.getContractFactory('RewardsDistributor')
            .then(f => f.deploy())
        
        nftAndRewardTokenFactory = conditionalPartialApplier(
            USE_SAME_REWARDS_DISTRIBUTOR_FOR_ALL_TESTS, rewardingForHoldingFactory
        )({rewardsDistributor: REWARDS_DISTRIBUTOR})
    })

    describe('distributing rewards for holding nfts', async () => {

        describe('contract configuration', async () => {
            it('should have nft address right configured', async () => {
                const { rewardsDistributor, erc20, nft } = await nftAndRewardTokenFactory({})
                const conf = await getRewardedNftHoldingConfig(rewardsDistributor, erc20.address)
                expect(conf.nftContract).to.equal(nft.address)
            })
            it('should have reward model enabled', async () => {
                const { rewardsDistributor, erc20 } = await nftAndRewardTokenFactory({})
                const conf = await getRewardedNftHoldingConfig(rewardsDistributor, erc20.address)
                expect(conf.isEnabled).to.equal(true)
            })
            it('should have rewards per day correctly configured', async () => {
                const { rewardsDistributor, erc20 } = await nftAndRewardTokenFactory({
                    rewardsPerSecond: 30
                })
                const conf = await getRewardedNftHoldingConfig(rewardsDistributor, erc20.address)
                expect(conf.rewardsWeightPerDay).to.equal(toWei(30 * 60 * 60 * 24))
            })
            it('should have rewarding started after configuration', async () => {
                const { rewardsDistributor, erc20 } = await nftAndRewardTokenFactory({})
                const expectedStart = await getLastTimestamp()
                const conf = await rewardsDistributor.nftHoldingRewardsConfigFor(erc20.address)
                expect(expectedStart).to.equal(conf.rewardsDistributionStarted)
            })
            
        })

        it('shouldn\'t allow claiming rewards if contract is empty', async () => {
            const { rewardsDistributor, erc20, nft, owner } = await nftAndRewardTokenFactory({})

            const [, rewardedUser] = await ethers.getSigners()
            await nft.connect(owner).mint(rewardedUser.address, 1)

            expect(await nft.balanceOf(rewardedUser.address)).to.equal(1)
            expect(await nft.ownerOf(1)).to.equal(rewardedUser.address)
            await sleep(1)
            expect(
                rewardsDistributor.connect(rewardedUser).claimRewardsForNftsHeld(erc20.address, [1])
            ).to.be.reverted
        })

        it('shouldn\'t allow claiming rewards if contract is almost empty', async () => {
            const { rewardsDistributor, erc20, nft, owner } = await nftAndRewardTokenFactory({
                rewardsPerSecond: 30
            })

            const [, rewardedUser] = await ethers.getSigners()
            await nft.connect(owner).mint(rewardedUser.address, 1)
            await erc20.connect(owner).transfer(rewardsDistributor.address, toWei(15))

            expect(await erc20.balanceOf(rewardsDistributor.address)).to.equal(toWei(15))
            await sleep(1)
            expect(
                rewardsDistributor.connect(rewardedUser).claimRewardsForNftsHeld(erc20.address, [1])
            ).to.be.reverted
            expect(await erc20.balanceOf(rewardsDistributor.address)).to.equal(toWei(15))
        })

        it('should be able to calc deserved rewards', async () => {
            const { rewardsDistributor, erc20, nft, owner } = await nftAndRewardTokenFactory({
                rewardsPerSecond: 1
            })
    
            const [, rewardedUser] = await ethers.getSigners()
            await nft.connect(owner).mint(rewardedUser.address, 1)
            await sleep(2)
                
            const rewards = await rewardsDistributor.calcNftHoldingRewards(erc20.address, 1)
            expect(fromWei(rewards)).to.equal('2.0')
        })

        it('should have low rewards for recently minted nfts', async () => {
            const { rewardsDistributor, erc20, nft, owner } = await nftAndRewardTokenFactory({
                rewardsPerSecond: 1
            })

            await erc20.connect(owner).transfer(rewardsDistributor.address, toWei(15))
            const [, hacker] = await ethers.getSigners()
        
            await sleep(2)

            await nft.connect(owner).mint(hacker.address, 1)
            await rewardsDistributor.connect(hacker).claimRewardsForNftsHeld(erc20.address, [1])
            expect(await erc20.balanceOf(hacker.address)).to.lessThanOrEqual(toWei(1))
        })
    })
})
