import { ethers } from 'hardhat';
import { expect } from 'chai';

import {
    OptPartialApplierRes,
    archetypeRewardingforHoldingNft,
    conditionalPartialApplier,
    getRandomFundedAccount,
} from '../scripts/helpers'
import { getLastTimestamp, sleep, toWei, fromWei } from '../lib/ArchetypeAuction/scripts/helpers';
import { MPartyRewardsDistributor } from '../typechain-types';
import { range } from 'fp-ts/lib/ReadonlyNonEmptyArray';

describe('MPartyRewardsDistributor', async () => {

    let nftAndArchetypeTokenFactory: OptPartialApplierRes<typeof archetypeRewardingforHoldingNft>
    let REWARDS_DISTRIBUTOR: MPartyRewardsDistributor

    before(async () => {
        // NOTE that all tests should work using the same `rewardsDistributor`, as it
        // is an singleton.
        const USE_SAME_REWARDS_DISTRIBUTOR_FOR_ALL_TESTS = false;

        REWARDS_DISTRIBUTOR = await ethers.getContractFactory('MPartyRewardsDistributor')
            .then(f => f.deploy())

        nftAndArchetypeTokenFactory = conditionalPartialApplier(
            USE_SAME_REWARDS_DISTRIBUTOR_FOR_ALL_TESTS, archetypeRewardingforHoldingNft
        )({ rewardsDistributor: REWARDS_DISTRIBUTOR })

    })

    /**
     * @dev System case analyzed in this `describe` block:
     * - It's using an archetype erc20 token as rewards, that means that
     *   the token gets automatically minted when needed.
     */
    describe('distributing archetype rewards for holding nfts', async () => {

        describe('contract configuration', async () => {
            it('should allow reward token configuration', async () => {
                const {rewardsDistributor, erc20} = await nftAndArchetypeTokenFactory({
                    rewardTokenSupply: 0, rewardTokenMaxSupply: 100
                })

                expect(await erc20.isRewardsMinter(rewardsDistributor.address)).to.true
                expect(await erc20.supplyLeft()).to.equal(toWei(100))
            })
            
            it('shouldn\'t allow contract reconfiguration by not owner', async () => {
                const {rewardsDistributor, erc20, nft} = await nftAndArchetypeTokenFactory({
                    rewardTokenSupply: 0, rewardTokenMaxSupply: 100
                })

                const hacker = await getRandomFundedAccount()
                
                expect(rewardsDistributor.connect(hacker).disableRewardsForHoldingNft()).reverted

                const TokenFactory = await ethers.getContractFactory('MPARTY')
                const hackToken = await TokenFactory.deploy()

                expect(rewardsDistributor.connect(hacker).configRewardsForHoldingNft(
                    hackToken.address,
                    nft.address,
                    toWei(1),
                    await getLastTimestamp() - 100
                )).reverted
            })
        })
        

        it('should allow rewards mint', async () => {
            const rewardsPerSecond = 1
            const {
                rewardsDistributor, erc20, nft, rewardsStart, deployer
            } = await nftAndArchetypeTokenFactory({rewardsPerSecond})

            const rewardedUser = await getRandomFundedAccount()
            await nft.connect(deployer).mint(rewardedUser.address, 1)
            
            await rewardsDistributor.connect(rewardedUser).claimRewardsForNftsHeld([1])
            const expectedRewards = (await getLastTimestamp() - rewardsStart) * rewardsPerSecond

            expect(await erc20.balanceOf(rewardedUser.address)).to.equal(toWei(expectedRewards))
        })

        it('shouldn\'t allow exceding max rewards supply', async () => {
            const iniSupply = 10
            const {rewardsDistributor, erc20, deployer, nft} = await nftAndArchetypeTokenFactory({
                rewardTokenSupply: iniSupply, rewardTokenMaxSupply: iniSupply
            })
            expect(await erc20.totalSupply()).to.equal(toWei(iniSupply))

            const rewardedUser = await getRandomFundedAccount()
            await nft.connect(deployer).mint(rewardedUser.address, 1)

            await rewardsDistributor.connect(rewardedUser).claimRewardsForNftsHeld([1])
            expect(await erc20.balanceOf(rewardedUser.address)).to.equal(0)
            expect(await erc20.totalSupply()).to.equal(toWei(iniSupply))
            expect(await erc20.supplyLeft()).to.equal(0)
        })

        it('should allow remaining rewards until max supply', async () => {
            const iniSupply = 10
            const supplyLeft = 0.5
            const rewardsPerSecond = 1
            const {rewardsDistributor, erc20, deployer, nft} = await nftAndArchetypeTokenFactory({
                rewardTokenSupply: iniSupply,
                rewardTokenMaxSupply: iniSupply + supplyLeft,
                rewardsPerSecond
            })

            const rewardedUser = await getRandomFundedAccount()
            await nft.connect(deployer).mint(rewardedUser.address, 1)

            await rewardsDistributor.connect(rewardedUser).claimRewardsForNftsHeld([1])
            expect(await erc20.balanceOf(rewardedUser.address)).to.equal(toWei(supplyLeft))
            expect(await erc20.totalSupply()).to.equal(toWei(iniSupply + supplyLeft))
            expect(await erc20.supplyLeft()).to.equal(0)
        })

        it('should allow claiming lots of ids', async () => {
            const iniSupply = 0
            const maxSupp = 1000
            const rewardsPerSecond = 2
            const {rewardsDistributor, erc20, deployer, nft, rewardsStart} = await nftAndArchetypeTokenFactory({
                rewardTokenSupply: iniSupply,
                rewardTokenMaxSupply: maxSupp,
                rewardsPerSecond
            })

            const rewardedUser = await getRandomFundedAccount()

            const ids = range(1, 10)
            for (const id of ids) {
                await nft.connect(deployer).mint(rewardedUser.address, id)
            }

            await rewardsDistributor.connect(rewardedUser).claimRewardsForNftsHeld([...ids])
            const expectedRewards = (await getLastTimestamp() - rewardsStart) 
                * rewardsPerSecond * ids.length
            
            expect(await erc20.balanceOf(rewardedUser.address)).to.equal(toWei(expectedRewards))
            expect(await erc20.totalSupply()).to.equal(toWei(expectedRewards))
            expect(await erc20.supplyLeft()).to.equal(toWei(maxSupp - expectedRewards))
        })

    })

})
