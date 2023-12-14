// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {MainnetForkTestGCC} from "./MainnetForkTestGCC.sol";
import "forge-std/console.sol";
import {IGCC} from "@/interfaces/IGCC.sol";
import "forge-std/StdError.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {UnifapV2Pair} from "@unifapv2/UnifapV2Pair.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ImpactCatalyst} from "@/ImpactCatalyst.sol";
import {IUniswapV2Pair} from "@/interfaces/IUniswapV2Pair.sol";

bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
uint256 constant GCC_MAGNIFICATION = 1e18;
uint256 constant USDC_MAGNIFICATION = 1e24;

contract EstimateNominationsTest is Test {
    bool saveLogs = vm.envBool("SAVE_RETIRE_RUNS");
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockUSDC usdc;
    MainnetForkTestGCC public gcc;
    Governance public gov;
    CarbonCreditDutchAuction public auction;
    address public constant GCA_AND_MINER_POOL_CONTRACT = address(0x2);
    address public SIMON = address(0xfffaafdd);
    uint256 public SIMON_PK;
    address gca = address(0x155);
    address vetoCouncil = address(0x156);
    address grantsTreasury = address(0x157);
    address glw;
    TestGLOW glwContract;
    address vestingContract = address(0x412412);
    address earlyLiquidity = address(0x412412);
    address other = address(0xdead);
    address accountWithLotsOfUSDC = 0xcEe284F754E854890e311e3280b767F80797180d; //arbitrum bridge
    string forkUrl = vm.envString("GOERLI_RPC_URL");
    uint256 goerliFork;

    address uniswapFactoryMainnetAddress = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address uniswapRouterMainnetAddress = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address weth9MainnetAddress = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {
        goerliFork = vm.createFork(forkUrl);
        vm.selectFork(goerliFork);
        // uniswapFactory = new UnifapV2Factory();
        uniswapFactory = UnifapV2Factory(uniswapFactoryMainnetAddress);
        weth = WETH9(weth9MainnetAddress);
        uniswapRouter = UnifapV2Router(uniswapRouterMainnetAddress);
        // uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();
        glwContract =
            new TestGLOW(earlyLiquidity, vestingContract, GCA_AND_MINER_POOL_CONTRACT, vetoCouncil, grantsTreasury);
        glw = address(glwContract);
        gov = new Governance();
        gcc = new MainnetForkTestGCC(
            GCA_AND_MINER_POOL_CONTRACT, address(gov), glw, address(usdc), address(uniswapRouter)
        );
        auction = CarbonCreditDutchAuction(address(gcc.CARBON_CREDIT_AUCTION()));
        gov.setContractAddresses(address(gcc), gca, vetoCouncil, grantsTreasury, glw);

        bytes32 initCodePair = keccak256(abi.encodePacked(type(UnifapV2Pair).creationCode));

        seedLP(1 ether, 10 * 1e6);
        address pair = gcc.IMPACT_CATALYST().UNISWAP_V2_PAIR();

        (uint256 reserveA, uint256 reserveB,) = UnifapV2Pair(pair).getReserves();
    }

    function test_commitEstimateGCC() public {
        uint256 amountToCommit = 0.5 ether;
        ImpactCatalyst c = gcc.IMPACT_CATALYST();
        uint256 estimate = c.estimateGCCCommitImpactPower(amountToCommit);
        commitGCC(SIMON, amountToCommit);
        uint256 amount = gcc.totalImpactPowerEarned(SIMON);
        console.log("amount = ", amount);
        // deployNew();
        console.log("estimate = ", estimate);
        // console.log("estimate = ");
        assertFalse(isDivergenceGreaterThanThreshold(estimate, amount), "estimate should be equal to amount");
    }

    function test_commitEstimateUSDC() public {
        uint256 amountToCommit = 1e3;
        ImpactCatalyst c = gcc.IMPACT_CATALYST();
        uint256 estimate = c.estimateUSDCCommitImpactPower(amountToCommit);
        commitUSDC(SIMON, amountToCommit);
        uint256 amount = gcc.totalImpactPowerEarned(SIMON);
        //{total_supply_after}
        uint256 totalSupplyPair = IUniswapV2Pair(c.UNISWAP_V2_PAIR()).totalSupply();
        uint256 balanceUSDC = usdc.balanceOf(c.UNISWAP_V2_PAIR());
        uint256 balanceGCC = gcc.balanceOf(c.UNISWAP_V2_PAIR());
        console.log("amount = ", amount);
        // console.log("[test pair balance usdc after swap] = ", balanceUSDC);
        // console.log("[test pair balance gcc after swap] = ", balanceGCC);
        deployNew();
        console.log("estimate = ", estimate);
        // console.log("estimate = ")
        assertFalse(isDivergenceGreaterThanThreshold(estimate, amount), "estimate should be equal to amount");
    }

    function testFuzz_commitEstimateUSDC(uint64 amountToCommit) public {
        //lp has 10*1e6  usdc, so we must bound carefully
        amountToCommit = uint64(bound(amountToCommit, 1 * 1e3, 10 * 1e6)); //
        // vm.assume(amountToCommit < 10 * 1e6);

        ImpactCatalyst c = gcc.IMPACT_CATALYST();
        uint256 estimate = c.estimateUSDCCommitImpactPower(amountToCommit);
        commitUSDC(SIMON, amountToCommit);
        uint256 amount = gcc.totalImpactPowerEarned(SIMON);
        // console.log("amount = ", amount);
        // deployNew();
        // console.log("estimate = ", estimate);
        // console.log("estimate = ")
        assertFalse(isDivergenceGreaterThanThreshold(estimate, amount), "estimate should be equal to amount");
    }

    function testFuzz_commitEstimateGCC(uint64 amountToCommit) public {
        //lp has 1 ether of gcc
        amountToCommit = uint64(bound(amountToCommit, 1 * 1e13, 1 ether)); //
        // vm.assume(amountToCommit < 10 * 1e6);

        ImpactCatalyst c = gcc.IMPACT_CATALYST();
        uint256 estimate = c.estimateGCCCommitImpactPower(amountToCommit);
        commitGCC(SIMON, amountToCommit);
        uint256 amount = gcc.totalImpactPowerEarned(SIMON);
        // console.log("amount = ", amount);
        // deployNew();
        // console.log("estimate = ", estimate);
        // console.log("estimate = ")
        assertFalse(isDivergenceGreaterThanThreshold(estimate, amount), "estimate should be equal to amount");
    }

    function test_divergenceFunctionWorks() public {
        uint256 expectedAmount = 99;
        uint256 actualAmount = 100;
        assertTrue(
            isDivergenceGreaterThanThreshold(expectedAmount, actualAmount),
            "divergence should be greater than threshold"
        );
    }

    function isDivergenceGreaterThanThreshold(uint256 expectedAmount, uint256 actualAmount)
        public
        view
        returns (bool)
    {
        uint256 divergenceThreshold = 5; // This represents .5% when scaled by 10^2
        uint256 scale = 10 ** 3; // Scaling factor to represent percentages accurately

        // Calculating the absolute difference
        uint256 difference =
            (expectedAmount > actualAmount) ? (expectedAmount - actualAmount) : (actualAmount - expectedAmount);

        // Scaling the expected amount and calculating the threshold value
        uint256 thresholdValue = expectedAmount * divergenceThreshold / scale;

        console.log("difference = ", difference);
        console.log("thresholdValue = ", thresholdValue);
        // console.log(")
        // Checking if the difference is greater than the calculated threshold value
        return difference > thresholdValue;
    }

    function deployNew() public {
        // uniswapFactory = new UnifapV2Factory();
        // weth = new WETH9();
        // uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        // usdc = new MockUSDC();
        // // mainnetFork = vm.createFork(forkUrl);
        // glwContract = new TestGLOW(earlyLiquidity,vestingContract);
        // glw = address(glwContract);
        // gov = new Governance();
        // gcc =
        //     new MainnetForkTestGCC(GCA_AND_MINER_POOL_CONTRACT, address(gov), glw,address(usdc),address(uniswapRouter));
        // auction = CarbonCreditDutchAuction(address(gcc.CARBON_CREDIT_AUCTION()));
        // gov.setContractAddresses(address(gcc), gca, vetoCouncil, grantsTreasury, glw);
        // seedLP(1 ether, 10 * 1e6);
    }

    function commitGCC(address from, uint256 amount) internal {
        vm.startPrank(from);
        if (gcc.balanceOf(from) < amount) {
            uint256 amountNeeded = amount - gcc.balanceOf(from);
            gcc.mint(from, amountNeeded);
        }
        gcc.commitGCC(amount, from, 0);
        vm.stopPrank();
    }

    function commitUSDC(address from, uint256 amount) internal {
        vm.startPrank(from);
        if (usdc.balanceOf(from) < amount) {
            uint256 amountNeeded = amount - usdc.balanceOf(from);
            usdc.mint(from, amountNeeded);
        }
        usdc.approve(address(gcc), amount);
        gcc.commitUSDC(amount, from, 0);
        vm.stopPrank();
    }

    function seedLP(uint256 amountGCC, uint256 amountUSDC) public {
        vm.startPrank(accountWithLotsOfUSDC);
        usdc.mint(accountWithLotsOfUSDC, amountUSDC);
        gcc.mint(accountWithLotsOfUSDC, amountGCC);
        gcc.approve(address(uniswapRouter), amountGCC);
        usdc.approve(address(uniswapRouter), amountUSDC);
        uniswapRouter.addLiquidity(
            address(gcc),
            address(usdc),
            amountGCC,
            amountUSDC,
            amountGCC,
            amountUSDC,
            accountWithLotsOfUSDC,
            block.timestamp
        );
        vm.stopPrank();
    }
}
