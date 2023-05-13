import { ethers } from 'hardhat';
import { ArchetypeERC20 } from '../typechain-types';
import { 
    toWei 
} from '../lib/ArchetypeAuction/scripts/helpers'
import { RewardsDistributor } from '../typechain-types';
import { zip } from 'fp-ts/lib/ReadonlyNonEmptyArray';
import { ReadonlyNonEmptyArray } from 'fp-ts/lib/ReadonlyNonEmptyArray';
import { RewardsDistributor__factory } from '../typechain-types';


// -------- Random pure utilities --------

export const randomAddress = () => `0x${[...Array(40)]
    .map(() => Math.floor(Math.random() * 16).toString(16))
    .join('')}`;

export const getRandomAccount = async () => 
    await ethers.getImpersonatedSigner(randomAddress())

export const zipIntoObject = <T>(
    keys: ReadonlyNonEmptyArray<string>, values: ReadonlyNonEmptyArray<T>
) => zip(keys, values).reduce((obj, [fst, snd]) => ({...obj, [fst]: snd}), {})

// @param f Is a function with an object as arg.
// @param v Is a value for this object.
// @returns A new function with the exact same type, but with `v` as default value.
export const partialApplier = <T extends object, U>(f: (args: T) => U, v: T) =>
    async (args: T) => await f({...args, ...v})
        
export type OptPartialApplierRes<F extends (...args: any) => any> = 
    ReturnType<typeof partialApplier<
        Parameters<F>[0],
        ReturnType<F>
    >> | F;

// @dev If `c` is true, then return a function with argument `v`. When calling this 
// return function, `v` will be partially applied over `f`. If `c` is not true, 
// return a function that will ignore the partial application intent.
export const conditionalPartialApplier = <T, U>(
    c: boolean, f: (args: T) => U
): (v: Pick<T, keyof T>) => OptPartialApplierRes<typeof f> =>
    c ? v => partialApplier(f, v) : _ => f


// -------- System utilities -------- 

/**
 * @dev It deploys an non Archetype ERC20, an ERC721 to reward for holding 
 * and an RewardsDistributor.
 */
export const rewardingForHoldingFactory = async ({
    rewardTokenSupply = 1000, rewardsPerSecond = 1, rewardsDistributor = undefined
}:{
    rewardTokenSupply?: number, rewardsPerSecond? : number, rewardsDistributor?: RewardsDistributor
}) => {
    const TokenFactory = await ethers.getContractFactory('MinimalErc20')
    const NftFactory = await ethers.getContractFactory('MinimalErc721')
    const RewardsDistributorFactory = await ethers.getContractFactory('RewardsDistributor')
    
    const [defaultAcc, ] = await ethers.getSigners()

    const deployer = await getRandomAccount()
    const owner = await getRandomAccount()

    defaultAcc.sendTransaction({to: deployer.address, value: toWei(100)})
    defaultAcc.sendTransaction({to: owner.address, value: toWei(100)})
    
    const erc20 = await TokenFactory.connect(owner).deploy(toWei(rewardTokenSupply));
    const nft = await NftFactory.connect(owner).deploy();
    if (!rewardsDistributor) 
        rewardsDistributor = await RewardsDistributorFactory.connect(deployer).deploy();

    await rewardsDistributor.connect(owner).configRewardsForHoldingNft(
        erc20.address, nft.address, toWei(rewardsPerSecond * 60 * 60 * 24)
    )

    return {
        deployer, owner, erc20, nft, rewardsDistributor
    }
};

type WeightedRewardedAuctionConfig = {
	isEnabled: boolean,
	hasExtraRewards:boolean,
	baseRewardsWeight: BigInt,
	extraRewardsWeight: BigInt,
	weightedVariableRoot: string,
	auctionContract: string,
}

type RewardedNftHoldingConfig = {
    isEnabled: boolean,
    nftContract: string,
    rewardsWeightPerDay: BigInt,
    rewardsDistributionStarted: BigInt
};

export const getWeightedRewardedAuctionConfig = async (
    distributor: RewardsDistributor, rewardToken: string
): Promise<WeightedRewardedAuctionConfig> => {
    const data = await distributor.auctionRewardsConfigFor(rewardToken)
    return data as WeightedRewardedAuctionConfig
}

export const getRewardedNftHoldingConfig = async (
    distributor: RewardsDistributor, rewardToken: string
): Promise<RewardedNftHoldingConfig> => {
    const data = await distributor.nftHoldingRewardsConfigFor(rewardToken)
    return data as RewardedNftHoldingConfig
}

