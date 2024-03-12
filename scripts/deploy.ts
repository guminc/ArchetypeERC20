import { ethers } from "hardhat"
import { getRandomFundedAccount, toWei } from "./helpers"
import { time } from "@nomicfoundation/hardhat-network-helpers"

export const deployTestToken = async ({
    maxSupply = 100,
    rewardsPerSecond = 1
}: {
    maxSupply?: number | bigint,
    rewardsPerSecond?: number | bigint
}) => {
    const nft = await ethers
        .getContractFactory('MinimalErc721')
        .then(f => f.deploy())

    const user = await getRandomFundedAccount()
    
    const weiPerSecond = typeof rewardsPerSecond === 'bigint'
        ? rewardsPerSecond
        : toWei(rewardsPerSecond)
    
    const weiPerDay = weiPerSecond * 60n * 60n * 24n

    const weiMaxSupply = typeof maxSupply === 'bigint'
        ? maxSupply
        : toWei(maxSupply)

    const token = await ethers
        .getContractFactory('Gamer')
        .then(f => f.deploy(nft.getAddress(), weiMaxSupply, weiPerDay))

    const deploymentTime = await time.latest()
    
    return { nft, user, token, deploymentTime }
}
