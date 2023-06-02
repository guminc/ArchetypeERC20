import { ethers } from 'hardhat';
import { 
    toWei 
} from '../lib/ArchetypeAuction/scripts/helpers'
import { zip } from 'fp-ts/lib/ReadonlyNonEmptyArray';
import { ReadonlyNonEmptyArray } from 'fp-ts/lib/ReadonlyNonEmptyArray';
import * as O from 'fp-ts/lib/Option';
import { MPartyRewardsDistributor } from '../typechain-types';


// -------- Random pure utilities --------

export const getLastTimestamp = async () =>
    (await ethers.provider.getBlock('latest')).timestamp

export const randomAddress = () => `0x${[...Array(40)]
    .map(() => Math.floor(Math.random() * 16).toString(16))
    .join('')}`;

export const getRandomAccount = async () => 
    await ethers.getImpersonatedSigner(randomAddress())

export const getRandomFundedAccount = async (funds: number = 10) => {
    const acc = await getRandomAccount() 
    const [admin, ] = await ethers.getSigners()
    await admin.sendTransaction({to: acc.address, value: toWei(funds)})
    return acc
};

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

export const extractPercent = (percent: string): O.Option<number> => {
    if (!percent.endsWith('%')) return O.none;
    const value = parseFloat(percent.slice(0, -1))
    return isNaN(value) ? O.none : O.some(value)
};


// -------- System utilities -------- 

export const archetypeRewardingforHoldingNft = async ({
    rewardTokenSupply = 100,
    rewardTokenMaxSupply = 200,
    rewardsPerSecond = 1,
    rewardsDistributor = undefined,
}: {
    rewardTokenSupply?: number,
    rewardTokenMaxSupply?: number,
    rewardsPerSecond? : number,
    rewardsDistributor?: MPartyRewardsDistributor,
}) => {
    const TokenFactory = await ethers.getContractFactory('MPARTY')
    const NftFactory = await ethers.getContractFactory('MinimalErc721')
    const RewardsDistributorFactory = await ethers.getContractFactory('MPartyRewardsDistributor')
    
    const deployer = await getRandomFundedAccount()
    const owner = await getRandomFundedAccount()

    const erc20 = await TokenFactory.connect(owner).deploy()
    await erc20.connect(owner).setMaxSupply(toWei(rewardTokenMaxSupply))
    await erc20.connect(owner).ownerMint(owner.address, toWei(rewardTokenSupply))

    const nft = await NftFactory.connect(owner).deploy();
    
    if (!rewardsDistributor) 
        rewardsDistributor = await RewardsDistributorFactory.connect(deployer).deploy();

    await erc20.connect(owner).addRewardsMinter(rewardsDistributor.address)

    const rewardsStart = await getLastTimestamp()

    await rewardsDistributor.connect(owner).configRewardsForHoldingNft(
        erc20.address,
        nft.address,
        toWei(rewardsPerSecond * 60 * 60 * 24),
        rewardsStart 
    )

    return {
        deployer, owner, erc20, nft, rewardsDistributor, rewardsStart
    }
}

