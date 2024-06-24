// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "@/testing/TestGCC.sol";
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

bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
uint256 constant GCC_MAGNIFICATION = 1e18;
uint256 constant USDC_MAGNIFICATION = 1e24;

contract SmallLPTest is Test {
    bool saveLogs = vm.envBool("SAVE_RETIRE_RUNS");
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockUSDC usdc;
    TestGCC public gcc;
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

    address deployer = tx.origin;

    function setUp() public {
        vm.startPrank(deployer);

        uint256 deployerNonce = vm.getNonce(deployer);
        uniswapFactory = new UnifapV2Factory(); //deployerNonce
        weth = new WETH9(); //deployerNonce + 1
        uniswapRouter = new UnifapV2Router(address(uniswapFactory)); //deployerNonce + 2
        usdc = new MockUSDC(); //deployerNonce + 3
        // mainnetFork = vm.createFork(forkUrl);
        glwContract =
            new TestGLOW(earlyLiquidity, vestingContract, GCA_AND_MINER_POOL_CONTRACT, vetoCouncil, grantsTreasury); //deployerNonce + 4
        glw = address(glwContract);

        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 6);
        gcc = new TestGCC(
            GCA_AND_MINER_POOL_CONTRACT, address(precomputedGovernance), glw, address(usdc), address(uniswapRouter)
        ); //deployerNonce + 5

        gov = new Governance({
            gcc: address(gcc),
            gca: GCA_AND_MINER_POOL_CONTRACT,
            vetoCouncil: vetoCouncil,
            grantsTreasury: grantsTreasury,
            glw: glw
        }); //deployerNonce + 6
        auction = CarbonCreditDescendingPriceAuction(address(gcc.CARBON_CREDIT_AUCTION()));
        // gov.setContractAddresses(address(gcc), gca, vetoCouncil, grantsTreasury, glw);

        bytes32 initCodePair = keccak256(abi.encodePacked(type(UnifapV2Pair).creationCode));
        console.logBytes32(initCodePair);

        vm.stopPrank();
        seedLP(1 ether, 10 * 1e6);
        address pair = uniswapFactory.pairs(address(usdc), address(gcc));

        (uint256 reserveA, uint256 reserveB,) = UnifapV2Pair(pair).getReserves();
    }

    function testFuzz_commitWithSmallLp(uint64 amountToCommit) public {
        vm.assume(amountToCommit > 0.1 ether);
        commitGCC(SIMON, amountToCommit);
        address pair = uniswapFactory.pairs(address(usdc), address(gcc));
        uint256 gccReserve;
        uint256 usdcReserve;
        (uint256 reserveA, uint256 reserveB,) = UnifapV2Pair(pair).getReserves();
        gccReserve = address(gcc) < address(usdc) ? reserveA : reserveB;
        usdcReserve = address(gcc) < address(usdc) ? reserveB : reserveA;
        console.log("gccReserve", gccReserve);
        console.log("usdcReserve", usdcReserve);
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
