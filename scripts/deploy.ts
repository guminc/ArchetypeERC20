import { ethers } from "hardhat"
import { toWei } from "../lib/ArchetypeAuction/scripts/helpers"
import { getLastTimestamp } from "./helpers"
import { IERC721__factory, MPARTY__factory } from "../typechain-types"

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


const deployMpartyProd = async () => {
    const TokenFactory = await ethers.getContractFactory('MPARTY')
    const RewardsDistributorFactory = await ethers.getContractFactory('MPartyRewardsDistributor')
    
    const [deployer, ] = await ethers.getSigners()
    
    const mpartyNft = new ethers.Contract(
        '0x05C63282c87f620aF5a658cBb53548257F3A6186',
        IERC721__factory.abi,
        deployer
    )
    const mparty = await TokenFactory.connect(deployer).deploy()
    await mparty.connect(deployer).setMaxSupply(toWei(1_000_000))

    const rewardsDistributor = await RewardsDistributorFactory.connect(deployer).deploy()

    await mparty.connect(deployer).addRewardsMinter(rewardsDistributor.address)

    const rewardsStart = 1684800000

    await rewardsDistributor.connect(deployer).configRewardsForHoldingNft(
        mparty.address,
        mpartyNft.address,
        toWei(1), // 1 $MPARTY reward per day.
        rewardsStart
    )
    
    console.log(`Reward token: ${mparty.address}`)
    console.log(`Rewards distributor: ${rewardsDistributor.address}`)
    console.log(`With timestamp: ${rewardsStart}`)
    console.log(`With current timestamp: ${await getLastTimestamp()}`)
}

const prodFixDeploy = async () => {
    
    const RewardsDistributorFactory = await ethers.getContractFactory('MPartyRewardsDistributor')
    
    const [deployer, ] = await ethers.getSigners()
    
    const mpartyToken = new ethers.Contract(
        '0xDe950e159655cA981cb46d4ccfE251Ba8D6c7772',
        MPARTY__factory.abi,
        deployer
    )

    const mpartyNft = new ethers.Contract(
        '0x05C63282c87f620aF5a658cBb53548257F3A6186',
        IERC721__factory.abi,
        deployer
    )
    const rewardsDistributor = await RewardsDistributorFactory.connect(deployer).deploy()

    await mpartyToken.connect(deployer).addRewardsMinter(rewardsDistributor.address)

    const rewardsStart = 1684800000

    await rewardsDistributor.connect(deployer).configRewardsForHoldingNft(
        mpartyToken.address,
        mpartyNft.address,
        toWei(1), // 1 $MPARTY reward per day.
        rewardsStart
    )
    
    console.log(`Reward token: ${mpartyToken.address}`)
    console.log(`Rewards distributor: ${rewardsDistributor.address}`)
    console.log(`With timestamp: ${rewardsStart}`)
    console.log(`With current timestamp: ${await getLastTimestamp()}`)
     
}

prodFixDeploy().catch(e => console.error(e))
