import { expect } from 'chai'
import { deployTestToken } from '../scripts/deploy'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import { randomWei, toWei } from '../scripts/helpers'
import * as R from 'fp-ts/lib/Random';

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


})
