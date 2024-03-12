import { ethers } from 'hardhat';
import * as R from 'fp-ts/lib/Random';
import { flow } from 'fp-ts/lib/function';

export const toWei = (x: number) => ethers.parseUnits(x.toString(), 'ether')
export const fromWei = flow(ethers.formatEther, Number)
export const randomWei = (min: number, max: number) => toWei(R.randomInt(min, max)())

export const or = <T, U>(x: T, y: U) => R.randomElem([x, y])()
export const zeroOr = <T>(x: T) => R.randomElem([0 as const, x])()

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
}

