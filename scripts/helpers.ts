import { ethers } from 'hardhat';
import { zip } from 'fp-ts/lib/ReadonlyNonEmptyArray';
import { ReadonlyNonEmptyArray } from 'fp-ts/lib/ReadonlyNonEmptyArray';
import * as O from 'fp-ts/lib/Option';
import * as R from 'fp-ts/lib/Random';
import { flow } from 'fp-ts/lib/function';
import { time } from '@nomicfoundation/hardhat-network-helpers';

export const toWei = (x: number) => ethers.parseUnits(x.toString(), 'ether')
export const fromWei = flow(ethers.formatEther, Number)
export const randomWei = (min: number, max: number) => toWei(R.randomInt(min, max)())

export const or = <T, U>(x: T, y: U) => R.randomElem([x, y])()
export const zeroOr = <T>(x: T) => R.randomElem([0 as const, x])()

// -------- Random pure utilities --------

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

