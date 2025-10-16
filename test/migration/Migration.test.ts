import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import {data} from "./data.js";

describe("Counter", async function () {
  const { viem,networkHelpers,networkConfig } = await network.connect("hardhatMainnetFork");
  const publicClient = await viem.getPublicClient();

  it("Should emit the Increment event when calling t    he inc() function", async function () {
    const minerPoolAndGCA = await viem.getContractAt("MinerPoolAndGCA","0x6fa8c7a89b22bf3212392b778905b12f3dbaf5c4");
    const rewardKernel = await viem.getContractAt("FoundationRewardKernel","0xd6d3139d40a32F8bA71D576c1A743529AB4786BB");

    const cfhFactory = await viem.getContractAt("CounterfactualHolderFactory","0x5bB7eC88cA80146FF47019079Cf0330532A1157F");
   const glow = await viem.getContractAt("Glow","0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6");
   const usdg = await viem.getContractAt("USDG","0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2");
   const _usdcAddress = await usdg.read.USDC();
   const usdc = await viem.getContractAt("ERC20",_usdcAddress as `0x${string}`);
    const GCA = "0xB2d687b199ee40e6113CD490455cC81eC325C496"
    const walletClient = await viem.getWalletClient(GCA);
   await networkHelpers.impersonateAccount(GCA);
   const _fees = await publicClient.estimateFeesPerGas();
   const res = await minerPoolAndGCA.write.submitWeeklyReport([BigInt(98),
    BigInt(1),BigInt(data.totalGlowInflationRewardsLeafWeight),
    BigInt(data.totalV1UsdgWeight), data.v1MerkleRoot as `0x${string}`],{
     account: walletClient.account.address as `0x${string}`,
     maxFeePerGas: _fees.maxFeePerGas * 2n,
     maxPriorityFeePerGas: _fees.maxPriorityFeePerGas * 2n
   });

   await networkHelpers.stopImpersonatingAccount(GCA);



  const poster = await rewardKernel.read.FOUNDATION_MULTISIG();

  await networkHelpers.impersonateAccount(poster);

  const onchainTokensAndAmounts = data.fullOnchainTokensAndAmountsArray.map((item) => ({
    token: item.assetAddress as `0x${string}`,
    amount: BigInt(item.amount)
  }));
  await networkHelpers.setBalance(poster, BigInt(1000000000000000000000000000000000000000));
  const fees0 = await publicClient.estimateFeesPerGas();
  await rewardKernel.write.postPayoutRoot([data.v2MerkleRoot as `0x${string}`,onchainTokensAndAmounts],{
    account: poster,
    maxFeePerGas: fees0.maxFeePerGas * 2n,
    maxPriorityFeePerGas: fees0.maxPriorityFeePerGas * 2n
  });
  await networkHelpers.stopImpersonatingAccount(poster);

   await networkHelpers.time.increase(86400 * 7 * 3);

   //log readable leaves .length
   console.log("readable leaves length", data.readableLeaves.length);

   let totalGlowDelta = 0n;

   const protocolDepositHolder = "0x77040BbBD506F5e5a7D65f6917416Bae6C78B9fa" as `0x${string}`;
   const usdcHolder = "0xc5174BBf649a92F9941e981af68AaA14Dd814F85" as `0x${string}`;

   //Impersonate usdcHolder
   await networkHelpers.impersonateAccount(usdcHolder);
   
   const fees = await publicClient.estimateFeesPerGas();
    const amount = BigInt(21_000_000 * 10 ** 6);
    await networkHelpers.setBalance(usdcHolder, BigInt(1000000000000000000000000000000000000000));
   const tx = await  usdc.write.transfer([GCA,amount],{
      account: usdcHolder,
      maxFeePerGas: fees.maxFeePerGas * 2n,
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas * 2n
    });
 
    
    
    await networkHelpers.stopImpersonatingAccount(usdcHolder);

    await networkHelpers.impersonateAccount(GCA);
    await usdc.write.approve([usdg.address,amount],{  
        account: GCA,
        maxFeePerGas: fees.maxFeePerGas * 2n,
        maxPriorityFeePerGas: fees.maxPriorityFeePerGas * 2n
    });
   
    await usdg.write.swap([GCA,amount],{
      account: GCA,
      maxFeePerGas: fees.maxFeePerGas * 2n,
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas * 2n
    });
   //log the balanceOf GCA usdg
   const usdgBalanceBefore = await usdg.read.balanceOf([GCA]);
//    console.log("usdgBalanceBefore", usdgBalanceBefore);

   //aprove usdg for cfh factory
   await usdg.write.approve([cfhFactory.address,amount],{
    account: GCA,
    maxFeePerGas: fees.maxFeePerGas * 2n,
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas * 2n
   });
   await cfhFactory.write.transferToCFH([protocolDepositHolder,usdg.address,amount],{
    account: GCA,
    maxFeePerGas: fees.maxFeePerGas * 2n,
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas * 2n
   });
   await networkHelpers.stopImpersonatingAccount(GCA);

   // now impersonate the protocol deposit holder
   await networkHelpers.impersonateAccount(protocolDepositHolder);
   //send it some eth for gas
   await networkHelpers.setBalance(protocolDepositHolder, BigInt(1000000000000000000000000000000000000000));
   await cfhFactory.write.setApprovalStatus([rewardKernel.address,true],{
    account: protocolDepositHolder,
    maxFeePerGas: fees.maxFeePerGas * 2n,
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas * 2n
   });
   await networkHelpers.stopImpersonatingAccount(protocolDepositHolder);





   let totalAssetsEarned:Map<`0x${string}`,bigint> = new Map();

   for(let i=0; i<data.readableLeaves.length;++i) {
    const item = data.readableLeaves[i];
    const user = item.user as `0x${string}`;
    await networkHelpers.impersonateAccount(user);
    await networkHelpers.setBalance(user, BigInt(1000000000000000000000000000000000000000));
    const glowBalanceBefore = await glow.read.balanceOf([user]);
    await minerPoolAndGCA.write.claimRewardFromBucket([
        98n,
        BigInt(item.glowInflationEarnedLeafWeight),
        0n,
        item.v1MerkleProof as `0x${string}`[],
        0n,
        user,
        true,
        "0x"
    ],{account:   user});

    const glowBalanceAfter = await glow.read.balanceOf([user]);
    totalGlowDelta += glowBalanceAfter - glowBalanceBefore;

    const isGuardedToken = item.onchainAssetsEarned.map((item) => item.asset === "USDG" || item.asset === "GLOW" || item.asset === "GLW");
    const toCounterfactual = isGuardedToken.map((_) => false);
    const tokensAndAmounts = item.onchainAssetsEarned.map((item) => ({
      token: item.assetAddress as `0x${string}`,
      amount: BigInt(item.amount)
    }));


    // Claim it from v2
    await rewardKernel.write.claimPayout([0n,item.v2MerkleProof as `0x${string}`[],
        tokensAndAmounts,protocolDepositHolder,user, isGuardedToken,toCounterfactual],{
      account: user,
      maxFeePerGas: fees.maxFeePerGas * 2n,
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas * 2n
    });
    for(const token of tokensAndAmounts) {
        const existing =  BigInt(totalAssetsEarned.get(token.token) ||0n);
        totalAssetsEarned.set(token.token, existing + token.amount);
    }


    await networkHelpers.stopImpersonatingAccount(user);
    
}

console.log("totalAssetsEarned", totalAssetsEarned);

const maxReward = await rewardKernel.read.getMaxReward([0n,usdg.address]);
console.log("maxReward", maxReward);
const amountClaimed = await rewardKernel.read.getAmountClaimed([0n,usdg.address]);
console.log("amountClaimed", amountClaimed);

// console.log("totalGlowDelta", totalGlowDelta);


    
    // await viem.assertions.emitWithArgs(
    //   counter.write.inc(),
    //   counter,
    //   "Increment",
    //   [1n],
    // );
  });

  it("The sum of the Increment events should match the current value", async function () {
    // const counter = await viem.deployContract("Counter");
    // const deploymentBlockNumber = await publicClient.getBlockNumber();

    // // run a series of increments
    // for (let i = 1n; i <= 10n; i++) {
    //   await counter.write.incBy([i]);
    // }

    // const events = await publicClient.getContractEvents({
    //   address: counter.address,
    //   abi: counter.abi,
    //   eventName: "Increment",
    //   fromBlock: deploymentBlockNumber,
    //   strict: true,
    // });

    // // check that the aggregated events match the current value
    // let total = 0n;
    // for (const event of events) {
    //   total += event.args.by;
    // }

    // assert.equal(total, await counter.read.x());
  });
});
