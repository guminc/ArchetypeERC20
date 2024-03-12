import { expect } from 'chai'
import { deployTestToken } from '../scripts/deploy'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import { getRandomFundedAccount, randomAddress, randomWei, toWei } from '../scripts/helpers'
import * as R from 'fp-ts/lib/Random';
import * as RNEA from 'fp-ts/lib/ReadonlyNonEmptyArray';

describe('Gamer', () => {
    it('should be able to claim tokens', async () => {
        const rewardsPerSecond = 1
        const { nft, user, token, deploymentTime } = await deployTestToken({ rewardsPerSecond })
        await nft.mint(user, 0).then(tx => tx.wait())

        expect(await token.balanceOf(user)).eq(0)
        await token.connect(user).claimRewardsForNftsHeld([0])

        const expectedTokens = toWei(await time.latest() - deploymentTime)
        expect(await token.balanceOf(user)).eq(expectedTokens)
    })

    it('shouldn be able to claim same token twice', async () => {
        const rewardsPerSecond = 1
        const { nft, user, token, deploymentTime } = await deployTestToken({ rewardsPerSecond })
        await nft.mint(user, 0).then(tx => tx.wait())

        await token.connect(user).claimRewardsForNftsHeld([0, 0, 0])

        const expectedTokens = toWei(await time.latest() - deploymentTime)
        expect(await token.balanceOf(user)).eq(expectedTokens)
    })

    it('should be able to claim same token after some time', async () => {
        const rewardsPerSecond = randomWei(1, 5)
        const { nft, user, token, deploymentTime } = await deployTestToken({ rewardsPerSecond })

        await nft.mint(user, 0).then(tx => tx.wait())
        await token.connect(user).claimRewardsForNftsHeld([0])

        await time.increase(R.randomInt(1, 10)())

        await token.connect(user).claimRewardsForNftsHeld([0])
        const expectedTokens = BigInt((await time.latest() - deploymentTime)) * rewardsPerSecond
        expect(await token.balanceOf(user)).eq(expectedTokens)
    })

    it('shouldnt be able to claim non existent ids', async () => {
        const nftIdToMint = R.randomInt(0, 10)()
        const { nft, user, token } = await deployTestToken({})
        await nft.mint(user, nftIdToMint).then(tx => tx.wait())

        for (const i of RNEA.range(1, 10)) {
            if (i == nftIdToMint) continue 
            await expect(token.connect(user).claimRewardsForNftsHeld([i])).reverted
        }
    })

    it('shouldnt be able to claim non owned ids', async () => {
        const nftIdToMint = R.randomInt(0, 10)()
        const { nft, user, token } = await deployTestToken({})
        await nft.mint(user, nftIdToMint).then(tx => tx.wait())

        for (const i of RNEA.range(1, 10)) {
            if (i == nftIdToMint) continue 
            await nft.mint(randomAddress(), i)
        }

        for (const i of RNEA.range(1, 10)) {
            if (i == nftIdToMint) continue 
            await expect(token.connect(user).claimRewardsForNftsHeld([i])).reverted
        }
    })

    it('should be able to claim with different users', async () => {
        const rewardsPerSecond = randomWei(1, 5)
        const { nft, user, token, deploymentTime } = await deployTestToken({ rewardsPerSecond })
        const randomHolder = await getRandomFundedAccount() 

        await nft.mint(randomHolder, 3)
        await nft.mint(randomHolder, 7)
        await token.connect(randomHolder).claimRewardsForNftsHeld([3])
        await nft.mint(user, 11)
        await token.connect(randomHolder).claimRewardsForNftsHeld([7])
        await token.connect(randomHolder).claimRewardsForNftsHeld([3])

        await time.increase(R.randomInt(1, 10)())
        await token.connect(randomHolder).claimRewardsForNftsHeld([3, 7])

        const expectedRandomHolderBalance = BigInt(
            await time.latest() - deploymentTime
        ) * rewardsPerSecond * 2n
        expect(await token.balanceOf(randomHolder)).eq(expectedRandomHolderBalance)

        await token.connect(user).claimRewardsForNftsHeld([11])
        const expectedUserBalance = BigInt(await time.latest() - deploymentTime) * rewardsPerSecond
        expect(await token.balanceOf(user)).eq(expectedUserBalance)
    })

    it('shouldnt be able to exceed max supply', async () => {
        const rewardsPerSecond = 1
        const maxSupply = 10
        const { 
            nft, user, token, deploymentTime 
        } = await deployTestToken({ rewardsPerSecond, maxSupply })

        await nft.mint(user, 11)

        await time.increase(R.randomInt(1, 3)())
        for (var i = 0; i < 100; i++) {
            await token.connect(user).claimRewardsForNftsHeld([11])
        }
        expect(await token.totalSupply()).eq(toWei(maxSupply))
    })

    it('TODO Test root', async () => {
        
    })
})
