// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {MainnetForkTestGCC} from "../MainnetForkTestGCC.sol";
import "forge-std/console.sol";
import {IGCC} from "@/interfaces/IGCC.sol";
import "forge-std/StdError.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
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
import {GCC} from "@/GCC.sol";
import {EstimateNominationsHandler} from "./Handlers/EstimateNominationsHandler.t.sol";

bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
uint256 constant GCC_MAGNIFICATION = 1e18;
uint256 constant USDC_MAGNIFICATION = 1e24;

contract EstimateNominationsLargerNumbersTest is Test {
    bool saveLogs = vm.envBool("SAVE_RETIRE_RUNS");
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockUSDC usdc;
    MainnetForkTestGCC public gcc;
    Governance public gov;
    CarbonCreditDescendingPriceAuction public auction;
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
    string forkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;

    address uniswapFactoryMainnetAddress = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address uniswapRouterMainnetAddress = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address weth9MainnetAddress = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint256 numGCC_Swap_Successes;
    uint256 numGCC_Swap_Failures;
    uint256 numUSDC_Swap_Successes;
    uint256 numUSDC_Swap_Failures;

    EstimateNominationsHandler handler;

    address deployer = tx.origin;

    function setUp() public {
        deployFixture();
    }

    function deployFixture() public {
        vm.startPrank(deployer);
        mainnetFork = vm.createFork(forkUrl);
        vm.selectFork(mainnetFork);
        // uniswapFactory = new UnifapV2Factory();
        uniswapFactory = UnifapV2Factory(uniswapFactoryMainnetAddress);
        weth = WETH9(weth9MainnetAddress);
        uniswapRouter = UnifapV2Router(uniswapRouterMainnetAddress);
        // uniswapRouter = new UnifapV2Router(address(uniswapFactory));

        uint256 deployerNonce = vm.getNonce(deployer);
        usdc = new MockUSDC(); //deployerNonce
        glwContract =
            new TestGLOW(earlyLiquidity, vestingContract, GCA_AND_MINER_POOL_CONTRACT, vetoCouncil, grantsTreasury); //deployerNonce + 1
        glw = address(glwContract);
        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 3);
        gcc = new MainnetForkTestGCC( //deployerNonce + 2
        GCA_AND_MINER_POOL_CONTRACT, address(precomputedGovernance), glw, address(usdc), address(uniswapRouter));
        gov = new Governance({
            gcc: address(gcc),
            gca: GCA_AND_MINER_POOL_CONTRACT,
            vetoCouncil: vetoCouncil,
            grantsTreasury: grantsTreasury,
            glw: glw
        }); //deployerNonce + 2

        auction = CarbonCreditDescendingPriceAuction(address(gcc.CARBON_CREDIT_AUCTION()));

        vm.stopPrank();
        // bytes32 initCodePair = keccak256(abi.encodePacked(type(UnifapV2Pair).creationCode));

        // address pair = gcc.IMPACT_CATALYST().UNISWAP_V2_PAIR();

        handler = new EstimateNominationsHandler(address(gcc), address(uniswapRouter));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = EstimateNominationsHandler.seedAndCommitGCCHandler.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetSelector(fs);
        targetContract(address(handler));
    }

    /**
     * forge-config: default.invariant.runs = 1
     * forge-config: default.invariant.depth = 100
     * forge-config: default.fail_on_revert = true
     */
    function invariant_testDivergenceNominations_gccCommit() public {
        string memory csvFilename = "logs/nomination_divergence.csv";
        string memory dustFileName = "logs/nomination_dust.csv";

        if (saveLogs) {
            // string memory headers = "round,expected,actual";
            // if (vm.exists(csvFilename)) {
            //     vm.removeFile(csvFilename);
            // }
            // vm.writeLine(csvFilename, headers);
        }
        uint256 rounds = handler.round();
        for (uint256 i; i < rounds; ++i) {
            uint256 expected = handler.estimatedmpactPowerForRound(i);
            uint256 actual = handler.actualImpactPowerForRound(i);
            EstimateNominationsHandler.Dust memory dust = handler.dustForRound(i);
            if (saveLogs) {
                string memory line =
                    string(abi.encodePacked(vm.toString(i), ",", vm.toString(expected), ",", vm.toString(actual)));
                vm.writeLine(csvFilename, line);

                string memory dustLine = string(
                    abi.encodePacked(
                        vm.toString(i),
                        ",",
                        vm.toString(dust.amountGCCToSwap),
                        ",",
                        vm.toString(dust.gccDust),
                        ",",
                        vm.toString(dust.usdcDust)
                    )
                );
                vm.writeLine(dustFileName, dustLine);
            }
            assertFalse(isDivergenceGreaterThanThreshold(expected, actual));
        }
    }

    function writeCSV(string memory filename, string memory contents) public {
        vm.writeLine(filename, contents);
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

    function commitGCC(address from, uint256 amount) internal returns (bool) {
        vm.startPrank(from);
        if (gcc.balanceOf(from) < amount) {
            uint256 amountNeeded = amount - gcc.balanceOf(from);
            gcc.mint(from, amountNeeded);
        }
        // gcc.commitGCC(amount, from, 0);
        (bool success, bytes memory data) = address(gcc).call(abi.encodeWithSelector(0x4ca9a234, amount, from, 0));
        if (!success) {
            numGCC_Swap_Failures++;
            //Uniswap error for insufficient amount in case we need it
            //0x08c379a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000025556e697377617056323a20494e53554646494349454e545f4f55545055545f414d4f554e54000000000000000000000000000000000000000000000000000000
        } else {
            numGCC_Swap_Successes++;
        }

        vm.writeLine("t.txt", string(abi.encodePacked("num gcc failures ", vm.toString(numGCC_Swap_Failures))));

        vm.writeLine("t.txt", string(abi.encodePacked("num gcc successes ", vm.toString(numGCC_Swap_Successes))));
        // if(!success && )
        vm.stopPrank();
        return success;
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
