import { ethers } from "hardhat"
import { toWei } from "../lib/ArchetypeAuction/scripts/helpers"
import { getLastTimestamp } from "./helpers"

const deployMpartyTestnet = async () => {
    const TokenFactory = await ethers.getContractFactory('MPARTY')
    const NftFactory = await ethers.getContractFactory('MinimalErc721')
    const RewardsDistributorFactory = await ethers.getContractFactory('MPartyRewardsDistributor')
    
    const [deployer, ] = await ethers.getSigners()
    
    const mpartyNft = await NftFactory.connect(deployer).deploy()
    const mparty = await TokenFactory.connect(deployer).deploy()
    await mparty.connect(deployer).setMaxSupply(toWei(1_000_000))

    const rewardsDistributor = await RewardsDistributorFactory.connect(deployer).deploy()

    await mparty.connect(deployer).addRewardsMinter(rewardsDistributor.address)

    const rewardsStart = await getLastTimestamp()

    await rewardsDistributor.connect(deployer).configRewardsForHoldingNft(
        mparty.address,
        mpartyNft.address,
        toWei(1), // 1 $MPARTY reward per day.
        rewardsStart
    )
    
    // Mints for testing purposes
    await mpartyNft.mint(deployer.address, 3)
    await mpartyNft.mint(deployer.address, 7)

    console.log(`Mparty NFT: ${mpartyNft.address}`)
    console.log(`Reward token: ${mparty.address}`)
    console.log(`Rewards distributor: ${rewardsDistributor.address}`)
}

deployMpartyTestnet().catch(e => console.error(e))
