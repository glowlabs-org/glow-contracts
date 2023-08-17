import { expect } from "chai";
import { ethers } from "hardhat";

describe("Token", function () {
  it("Should return name Token", async function () {
    const [signer,other] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();
    // await mockUSDC.deployed();

    /// @dev mint a ton of USDC to the signer
    // await mockUSDC.mint(signer.address, ethers.utils.parseEther("1000000000"));
    // const EarlyLiquidity = await ethers.getContractFactory("EarlyLiquidity");
    // const earlyLiquidity = await EarlyLiquidity.deploy(mockUSDC.address);
    // await earlyLiquidity.deployed();
    // const MockGlow = await ethers.getContractFactory("TestGLOW");
    // const vestingContractPlaceholderAddress = "0x591749484BFb1737473bf1E7Bb453257BdA452A9";
    // const mockGlow = await MockGlow.deploy(earlyLiquidity.address,vestingContractPlaceholderAddress);
    // await mockGlow.deployed();


  
  });
});
