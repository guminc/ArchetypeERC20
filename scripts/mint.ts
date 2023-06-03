import { ethers } from "hardhat"
import { IMPartyRewardsDistributor, IMPartyRewardsDistributor__factory, MinimalErc721, MinimalErc721__factory } from "../typechain-types"

const deployMpartyTestnet = async () => {
    
    const [deployer, ] = await ethers.getSigners()

    const nft = new ethers.Contract(
        '0xB0Ae85133340D50ebba03aC731b03d8D6E0ee344',
        MinimalErc721__factory.abi
    ) as MinimalErc721

    
    await nft.connect(deployer).mint(deployer.address, 420)
}

const query = async () => {

    const distributor = new ethers.Contract(
        '0xA7a31bCcC00E8ac43526d90cB357D2B8dDE5115A',
        IMPartyRewardsDistributor__factory.abi
    ) as IMPartyRewardsDistributor

    const [deployer, ] = await ethers.getSigners()

    const c = distributor.connect(deployer)
    
    const ids = [3, 420]

    const tx = c.calcNftHoldingRewards(ids)
    console.log(tx)
    console.log(await tx)
}

query().catch(e => console.error(e))
