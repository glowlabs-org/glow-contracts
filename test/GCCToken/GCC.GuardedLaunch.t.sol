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
import {Handler} from "./Handler.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOWGuardedLaunch} from "@/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {UnifapV2Pair} from "@unifapv2/UnifapV2Pair.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";
import {USDG} from "@/USDG.sol";
import {TestGCCGuardedLaunch} from "@/testing/GuardedLaunch/TestGCC.GuardedLaunch.sol";

// @dev, to test the results for enough precision if you are saving the csv
// run python3 repo-utils/commit-analysis/main.py to get the results

bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
uint256 constant GCC_MAGNIFICATION = 1e18;
uint256 constant USDC_MAGNIFICATION = 1e24;

contract GCCGuardedLaunchTest is Test {
    bool saveLogs = vm.envBool("SAVE_RETIRE_RUNS");
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockUSDC usdc;
    TestGCCGuardedLaunch public gcc;
    TestUSDG public usdg;
    Governance public gov;
    CarbonCreditDescendingPriceAuction public auction;
    address public constant GCA_AND_MINER_POOL_CONTRACT = address(0x2);
    address public SIMON;
    uint256 public SIMON_PK;
    Handler public handler;
    address gca = address(0x155);
    address vetoCouncil = address(0x156);
    address grantsTreasury = address(0x157);
    address glw;
    TestGLOWGuardedLaunch glwContract;
    address vestingContract = address(0x412412);
    address earlyLiquidity = address(0x412412);
    address other = address(0xdead);
    address accountWithLotsOfUSDC = 0xcEe284F754E854890e311e3280b767F80797180d; //arbitrum bridge
    // string forkUrl = vm.envString("MAINNET_RPC");
    // uint256 mainnetFork;
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);
    address holdingContract = address(0xaaa114);

    address deployer = tx.origin;

    function setUp() public {
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();

        vm.startPrank(deployer);

        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputeGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputeGCC = computeCreateAddress(deployer, deployerNonce);
        address precomputeImpactCatalyst = computeCreateAddress(precomputeGCC, 2); //TODO: change this in other tests since contract starts with nonce 1
        address precomputeUSDG = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputeGov = computeCreateAddress(deployer, deployerNonce + 3);
        gcc = new TestGCCGuardedLaunch({
            _gcaAndMinerPoolContract: GCA_AND_MINER_POOL_CONTRACT,
            _governance: precomputeGov,
            _glowToken: precomputeGlow,
            _usdg: precomputeUSDG,
            _vetoCouncilAddress: vetoCouncil,
            _uniswapRouter: address(uniswapRouter),
            _uniswapFactory: address(uniswapFactory)
        }); //deployerNonce
        // mainnetFork = vm.createFork(forkUrl);
        glwContract = new TestGLOWGuardedLaunch({
            _earlyLiquidityAddress: earlyLiquidity,
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: GCA_AND_MINER_POOL_CONTRACT,
            _vetoCouncilAddress: vetoCouncil,
            _grantsTreasuryAddress: grantsTreasury,
            _owner: SIMON,
            _usdg: precomputeUSDG,
            _uniswapV2Factory: address(uniswapFactory),
            _gccContract: address(gcc)
        }); //deployerNonce + 1

        assertEq(address(gcc.IMPACT_CATALYST()), precomputeImpactCatalyst, "impact catalyst address is not precomputed");
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _glow: precomputeGlow,
            _gcc: precomputeGCC,
            _holdingContract: holdingContract,
            _vetoCouncilContract: vetoCouncil,
            _impactCatalyst: precomputeImpactCatalyst
        }); //deployerNonce + 2

        glw = address(glwContract);
        (SIMON, SIMON_PK) = _createAccount(9999, 1e20 ether);
        gov = new Governance({
            gcc: address(gcc),
            gca: GCA_AND_MINER_POOL_CONTRACT,
            vetoCouncil: vetoCouncil,
            grantsTreasury: grantsTreasury,
            glw: glw
        }); //deployerNonce + 3
        // gcc = new TestGCCGuardedLaunch(GCA_AND_MINER_POOL_CONTRACT, address(gov), glw,address(usdg),address(uniswapRouter));

        gcc.allowlistPostConstructionContracts();
        auction = CarbonCreditDescendingPriceAuction(address(gcc.CARBON_CREDIT_AUCTION()));
        handler = new Handler(address(gcc), GCA_AND_MINER_POOL_CONTRACT);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.mintToCarbonCreditAuction.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});

        bytes32 initCodePair = keccak256(abi.encodePacked(type(UnifapV2Pair).creationCode));
        console.logBytes32(initCodePair);

        vm.stopPrank();

        vm.startPrank(usdgOwner);
        // usdg.setAllowlistedContracts({
        //     _glow: address(glwContract),
        //     _gcc: address(gcc),
        //     _holdingContract: address(vetoCouncil),
        //     _vetoCouncilContract: vetoCouncil,
        //     _impactCatalyst: address(gcc.IMPACT_CATALYST())
        // });
        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);
        vm.stopPrank();
        seedLP(400 ether, 1000 * 1e6);

        targetContract(address(handler));
        address pair = uniswapFactory.pairs(address(usdg), address(gcc));

        // (uint256 reserveA, uint256 reserveB,) = UnifapV2Pair(pair).getReserves();
        // console.log("reserveA = %s", reserveA);
        // console.log("reserveB = %s", reserveB);
        //     IUnifapV2Factory unifactory = IUnifapV2Factory(factory);
        // address pairFromFactory = unifactory.pairs(_usdc, address(this));
        // console.log("pair from factory = %s", pairFromFactory);
        // targetSender(GCA_AND_MINER_POOL_CONTRACT);
    }

    /**
     * forge-config: default.fuzz.runs = 250
     */
    function testFuzz_ensureOptimalAmountOutput_isLessThanAmountTocommit(uint256 a, uint256 b) public {
        /**
         * This test exists because our 'findOptimalAmountToSwap' function
         *         can lead to weird results due to precision loss in extreme cases.
         *         This test ensures that the optimal amount is always less than the
         *         amount to commit so that there is no underflow in the commit function.
         *         We choose a sensible range for the amount to commit and total reserves.
         *         Fuzz runs are set to 250 to prevent foundry from throwing errors due to
         *         too many rejected values.
         *         To run this in a more fullproof manner, we created a python script and looped
         *         1000 times on this test.
         */
        vm.assume(a > 0.01 ether && a < 1_000_000_000_000 * 1e6 ether);
        vm.assume(b > 0.01 ether && b < 1_000_000_000_000 * 1e6 ether);

        ImpactCatalyst swapper = gcc.IMPACT_CATALYST();
        uint256 amount = a;
        uint256 totalReserves = b;
        // console.log("amount = ", amount);
        // console.log("totalReserves = ", totalReserves);
        uint256 optimalAmount =
            swapper.findOptimalAmountToSwap(amount * GCC_MAGNIFICATION, totalReserves * GCC_MAGNIFICATION);
        optimalAmount /= GCC_MAGNIFICATION;
        uint256 success = amount >= optimalAmount ? 1 : 0;

        if (success == 0) {
            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(success)
                )
            );
            if (saveLogs) {
                vm.writeLine("gcc.csv", stringToWrite);
            }
        }
        assert(amount > optimalAmount);
    }

    /**
     * forge-config: default.fuzz.runs = 1000
     */
    function testFuzz_uniswapManualRetiringGCC(uint256 a, uint256 b) public {
        // a = amount to commit
        // b = total reserves

        /**
         * The point of this test is to ensure that precision loss for dust
         *         is sensible even in extreme scenarios such as the ranges described below.
         *         Manual analysis was done on the outputs of this test to ensure that
         *         the precision loss and dust is sensible and minimal.
         */
        vm.assume(a > 0.01 ether && a < 1_000_000_000_000 ether);
        vm.assume(b > 0.01 ether && b < 1_000_000_000_000 ether);

        vm.startPrank(deployer);
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();

        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputeGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputeGCC = computeCreateAddress(deployer, deployerNonce);
        address precomputeImpactCatalyst = computeCreateAddress(precomputeGCC, 2); //TODO: change this in other tests since contract starts with nonce 1
        address precomputeUSDG = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputeGov = computeCreateAddress(deployer, deployerNonce + 3);
        gcc = new TestGCCGuardedLaunch({
            _gcaAndMinerPoolContract: GCA_AND_MINER_POOL_CONTRACT,
            _governance: precomputeGov,
            _glowToken: precomputeGlow,
            _usdg: precomputeUSDG,
            _vetoCouncilAddress: vetoCouncil,
            _uniswapRouter: address(uniswapRouter),
            _uniswapFactory: address(uniswapFactory)
        }); //deployerNonce

        glwContract = new TestGLOWGuardedLaunch({
            _earlyLiquidityAddress: earlyLiquidity,
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: GCA_AND_MINER_POOL_CONTRACT,
            _vetoCouncilAddress: vetoCouncil,
            _grantsTreasuryAddress: grantsTreasury,
            _owner: SIMON,
            _usdg: precomputeUSDG,
            _uniswapV2Factory: address(uniswapFactory),
            _gccContract: address(gcc)
        }); //deployerNonce + 1

        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _glow: precomputeGlow,
            _gcc: precomputeGCC,
            _holdingContract: holdingContract,
            _vetoCouncilContract: vetoCouncil,
            _impactCatalyst: precomputeImpactCatalyst
        }); //deployerNonce + 2

        glw = address(glwContract);
        (SIMON, SIMON_PK) = _createAccount(9999, 1e20 ether);
        gov = new Governance({
            gcc: address(gcc),
            gca: GCA_AND_MINER_POOL_CONTRACT,
            vetoCouncil: vetoCouncil,
            grantsTreasury: grantsTreasury,
            glw: glw
        });
        gcc.allowlistPostConstructionContracts();
        vm.stopPrank();
        auction = CarbonCreditDescendingPriceAuction(address(gcc.CARBON_CREDIT_AUCTION()));
        vm.startPrank(usdgOwner);
        // usdg.setAllowlistedContracts({
        //     _glow: address(glwContract),
        //     _gcc: address(gcc),
        //     _holdingContract: address(vetoCouncil),
        //     _vetoCouncilContract: vetoCouncil,
        //     _impactCatalyst: address(gcc.IMPACT_CATALYST())
        // });
        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);
        vm.stopPrank();
        uint256 totalReserves = b;
        seedLP(totalReserves, 1000 * 1e6);

        ImpactCatalyst swapper = gcc.IMPACT_CATALYST();
        uint256 amount = a;
        // console.log("amount = ", amount);
        // console.log("totalReserves = ", totalReserves);
        uint256 optimalAmount =
            swapper.findOptimalAmountToSwap(amount * GCC_MAGNIFICATION, totalReserves * GCC_MAGNIFICATION);
        optimalAmount /= GCC_MAGNIFICATION;
        uint256 success = amount >= optimalAmount ? 1 : 0;

        address[] memory path = new address[](2);
        path[0] = address(gcc);
        path[1] = gcc.USDC();

        vm.startPrank(SIMON);
        gcc.mint(SIMON, amount);
        gcc.approve(address(uniswapRouter), amount);
        // uint256[] memory amounts =
        //     uniswapRouter.swapExactTokensForTokens(optimalAmount, 0, path, SIMON, block.timestamp);
        try uniswapRouter.swapExactTokensForTokens(optimalAmount, 0, path, SIMON, block.timestamp) returns (
            uint256[] memory amounts
        ) {
            // Success. Do something with `amounts` if needed.

            IERC20(gcc.USDC()).approve(address(uniswapRouter), amounts[1]);
            uint256 amountLiquidityToAdd = amount - optimalAmount;

            uniswapRouter.addLiquidity(
                address(gcc), gcc.USDC(), amountLiquidityToAdd, amounts[1], 0, 0, SIMON, block.timestamp
            );
            // This will catch failing revert() or require() with an error message.
            // Handle the error. Maybe emit a log or revert again with a custom message.
            uint256 leftoverGCC = gcc.balanceOf(SIMON);
            uint256 leftoverUSDC = usdc.balanceOf(SIMON);
            uint256 optimalAmountGreaterThanReserves = optimalAmount > totalReserves ? 1 : 0;
            //totalReserves,amount,optimalAmount,leftoverGCC,leftoverUSDC,success,optimalAmountGreaterThanReserves

            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(leftoverGCC),
                    ",",
                    Strings.toString(leftoverUSDC),
                    ",",
                    Strings.toString(success),
                    ",",
                    Strings.toString(optimalAmountGreaterThanReserves)
                )
            );

            if (saveLogs) {
                vm.writeLine("swap-succeses.csv", stringToWrite);
            }
        } catch Error(string memory reason) {
            // This will catch failing revert() or require() with an error message.
            // Handle the error. Maybe emit a log or revert again with a custom message.
            uint256 leftoverGCC = gcc.balanceOf(SIMON);
            uint256 leftoverUSDC = usdc.balanceOf(SIMON);
            uint256 optimalAmountGreaterThanReserves = optimalAmount > totalReserves ? 1 : 0;
            /**
             * CSV Headers:
             *     totalReserves,amount,optimalAmount,,success,optimalAmountGreaterThanReserves,reason
             */
            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(success),
                    ",",
                    Strings.toString(optimalAmountGreaterThanReserves),
                    ",",
                    reason
                )
            );

            if (saveLogs) {
                vm.writeLine("swap-errors.csv", stringToWrite);
            }
        }
    }

    //-------------------  USDC RETIRING  -----------------------------
    /**
     * forge-config: default.fuzz.runs = 250
     */
    function testFuzz_ensureOptimalAmountOutput_isLessThanAmountTocommit_USDC(uint256 a, uint256 b) public {
        /**
         * This test exists because our 'findOptimalAmountToSwap' function
         *         can lead to weird results due to precision loss in extreme cases.
         *         This test ensures that the optimal amount is always less than the
         *         amount to commit so that there is no underflow in the commit function.
         *         We choose a sensible range for the amount to commit and total reserves.
         *         Fuzz runs are set to 250 to prevent foundry from throwing errors due to
         *         too many rejected values.
         *         To run this in a more fullproof manner, we created a python script and looped
         *         1000 times on this test.
         */
        vm.assume(a > 0.01 * 1e6 && a < 1_000_000_000_000 * 1e6 * 1e6);
        vm.assume(b > 0.01 * 1e6 && b < 1_000_000_000_000 * 1e6 * 1e6);

        ImpactCatalyst swapper = gcc.IMPACT_CATALYST();
        uint256 amount = a;
        uint256 totalReserves = b;
        // console.log("amount = ", amount);
        // console.log("totalReserves = ", totalReserves);
        uint256 optimalAmount =
            swapper.findOptimalAmountToSwap(amount * USDC_MAGNIFICATION, totalReserves * USDC_MAGNIFICATION);
        optimalAmount /= USDC_MAGNIFICATION;
        uint256 success = amount >= optimalAmount ? 1 : 0;

        if (success == 0) {
            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(success)
                )
            );
            if (saveLogs) {
                vm.writeLine("usdc-data.csv", stringToWrite);
            }
        }
        assert(amount > optimalAmount);
    }

    /**
     * forge-config: default.fuzz.runs = 1000
     */
    function testFuzz_uniswapManualRetiringUSDC(uint256 a, uint256 b) public {
        // a = amount to commit
        // b = total reserves

        /**
         * The point of this test is to ensure that precision loss for dust
         *         is sensible even in extreme scenarios such as the ranges described below.
         *         Manual analysis was done on the outputs of this test to ensure that
         *         the precision loss and dust is sensible and minimal.
         *         Note: USDC has 6 decimals
         */
        {
            uint256 A_MIN = 10 * 1e6;
            uint256 A_MAX = 1_000_000_000_000 * 1e6;
            a = bound(a, A_MIN, A_MAX);
            uint256 B_MIN = 10 * 1e6;
            uint256 B_MAX = 1_000_000_000_000 * 1e6;
            b = bound(b, B_MIN, B_MAX);
        }

        vm.startPrank(deployer);
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();

        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputeGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputeGCC = computeCreateAddress(deployer, deployerNonce);
        address precomputeImpactCatalyst = computeCreateAddress(precomputeGCC, 2); //TODO: change this in other tests since contract starts with nonce 1
        address precomputeUSDG = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputeGov = computeCreateAddress(deployer, deployerNonce + 3);
        gcc = new TestGCCGuardedLaunch({
            _gcaAndMinerPoolContract: GCA_AND_MINER_POOL_CONTRACT,
            _governance: precomputeGov,
            _glowToken: precomputeGlow,
            _usdg: precomputeUSDG,
            _vetoCouncilAddress: vetoCouncil,
            _uniswapRouter: address(uniswapRouter),
            _uniswapFactory: address(uniswapFactory)
        }); //deployerNonce

        glwContract = new TestGLOWGuardedLaunch({
            _earlyLiquidityAddress: earlyLiquidity,
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: GCA_AND_MINER_POOL_CONTRACT,
            _vetoCouncilAddress: vetoCouncil,
            _grantsTreasuryAddress: grantsTreasury,
            _owner: SIMON,
            _usdg: precomputeUSDG,
            _uniswapV2Factory: address(uniswapFactory),
            _gccContract: address(gcc)
        }); //deployerNonce + 1

        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _glow: precomputeGlow,
            _gcc: precomputeGCC,
            _holdingContract: holdingContract,
            _vetoCouncilContract: vetoCouncil,
            _impactCatalyst: precomputeImpactCatalyst
        }); //deployerNonce + 2

        glw = address(glwContract);
        (SIMON, SIMON_PK) = _createAccount(9999, 1e20 ether);
        gov = new Governance({
            gcc: address(gcc),
            gca: GCA_AND_MINER_POOL_CONTRACT,
            vetoCouncil: vetoCouncil,
            grantsTreasury: grantsTreasury,
            glw: glw
        });
        gcc.allowlistPostConstructionContracts();
        vm.stopPrank();
        vm.startPrank(usdgOwner);
        // usdg.setAllowlistedContracts({
        //     _glow: address(glwContract),
        //     _gcc: address(gcc),
        //     _holdingContract: address(vetoCouncil),
        //     _vetoCouncilContract: vetoCouncil,
        //     _impactCatalyst: address(gcc.IMPACT_CATALYST())
        // });

        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);
        vm.stopPrank();
        auction = CarbonCreditDescendingPriceAuction(address(gcc.CARBON_CREDIT_AUCTION()));

        uint256 totalReserves = b;
        seedLP(100 ether, totalReserves);

        ImpactCatalyst swapper = gcc.IMPACT_CATALYST();
        uint256 amount = a;
        // console.log("amount = ", amount);
        // console.log("totalReserves = ", totalReserves);
        uint256 optimalAmount =
            swapper.findOptimalAmountToSwap(amount * USDC_MAGNIFICATION, totalReserves * USDC_MAGNIFICATION);
        optimalAmount /= USDC_MAGNIFICATION;
        uint256 success = amount >= optimalAmount ? 1 : 0;

        address[] memory path = new address[](2);
        path[0] = gcc.USDC();
        path[1] = address(gcc);
        mintUSDG(SIMON, amount);
        vm.startPrank(SIMON);
        usdg.approve(address(uniswapRouter), amount);

        try uniswapRouter.swapExactTokensForTokens(optimalAmount, 0, path, SIMON, block.timestamp) returns (
            uint256[] memory amounts
        ) {
            // Success. Do something with `amounts` if needed.

            gcc.approve(address(uniswapRouter), amounts[1]);
            uint256 amountLiquidityToAdd = amount - optimalAmount;

            uniswapRouter.addLiquidity(
                address(usdg), address(gcc), amountLiquidityToAdd, amounts[1], 0, 0, SIMON, block.timestamp
            );
            // This will catch failing revert() or require() with an error message.
            // Handle the error. Maybe emit a log or revert again with a custom message.
            uint256 leftoverGCC = gcc.balanceOf(SIMON);
            uint256 leftoverUSDC = usdg.balanceOf(SIMON);
            uint256 optimalAmountGreaterThanReserves = optimalAmount > totalReserves ? 1 : 0;
            //totalReserves,amount,optimalAmount,leftoverGCC,leftoverUSDC,success,optimalAmountGreaterThanReserves

            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(leftoverGCC),
                    ",",
                    Strings.toString(leftoverUSDC),
                    ",",
                    Strings.toString(success),
                    ",",
                    Strings.toString(optimalAmountGreaterThanReserves)
                )
            );

            if (saveLogs) {
                vm.writeLine("swap-succeses-usdc.csv", stringToWrite);
            }
        } catch Error(string memory reason) {
            // This will catch failing revert() or require() with an error message.
            // Handle the error. Maybe emit a log or revert again with a custom message.
            uint256 leftoverGCC = gcc.balanceOf(SIMON);
            uint256 leftoverUSDC = usdg.balanceOf(SIMON);
            uint256 optimalAmountGreaterThanReserves = optimalAmount > totalReserves ? 1 : 0;
            /**
             * CSV Headers:
             *     totalReserves,amount,optimalAmount,,success,optimalAmountGreaterThanReserves,reason
             */
            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(success),
                    ",",
                    Strings.toString(optimalAmountGreaterThanReserves),
                    ",",
                    reason
                )
            );

            if (saveLogs) {
                vm.writeLine("swap-errors-usdc.csv", stringToWrite);
            }
        }
    }

    //-------------------  END USDC RETIRING  -----------------------------

    // A manual test we used to confirm suspicions about certain inputs/outputs
    function test_guarded_manualGCCcommit() public {
        ImpactCatalyst swapper = gcc.IMPACT_CATALYST();
        uint256 amount = 9392183157865769199004733;
        uint256 totalReserves;

        {
            (uint256 reserveA, uint256 reserveB,) =
                UnifapV2Pair(uniswapFactory.pairs(address(gcc), address(usdg))).getReserves();
            uint256 gccReserve = address(gcc) < address(usdg) ? reserveA : reserveB;
            uint256 usdcReserve = address(gcc) < address(usdg) ? reserveB : reserveA;
            totalReserves = gccReserve;
        }
        // console.log("amount = ", amount);
        // console.log("totalReserves = ", totalReserves);
        uint256 optimalAmount =
            swapper.findOptimalAmountToSwap(amount * GCC_MAGNIFICATION, totalReserves * GCC_MAGNIFICATION);
        optimalAmount /= GCC_MAGNIFICATION;
        uint256 success = amount >= optimalAmount ? 1 : 0;

        address[] memory path = new address[](2);
        path[0] = address(gcc);
        path[1] = gcc.USDC();

        address receiver = address(0xfffaaadeaadd);
        vm.startPrank(SIMON);
        gcc.mint(SIMON, amount);
        gcc.approve(address(uniswapRouter), amount);
        // uint256[] memory amounts =

        {
            (uint256 reserveA, uint256 reserveB,) =
                UnifapV2Pair(uniswapFactory.pairs(address(gcc), address(usdg))).getReserves();
            uint256 gccReserve = address(gcc) < address(usdg) ? reserveA : reserveB;
            uint256 usdcReserve = address(gcc) < address(usdg) ? reserveB : reserveA;

            console.log("gccReserve before swap= %s", gccReserve);
            console.log("usdcReserve  before swap= %s", usdcReserve);
            console.log("gcc swapping = %s", optimalAmount);
        }
        uniswapRouter.swapExactTokensForTokens(optimalAmount, 0, path, SIMON, block.timestamp);
        try uniswapRouter.swapExactTokensForTokens(optimalAmount, 0, path, SIMON, block.timestamp) returns (
            uint256[] memory amounts
        ) {
            // Success. Do something with `amounts` if needed.

            uint256 amountUSDGBeforeLiquidityEvent = usdg.balanceOf(SIMON);

            IERC20(gcc.USDC()).approve(address(uniswapRouter), amounts[1]);

            uint256 amountLiquidityToAdd = amount - optimalAmount;

            {
                (uint256 reserveA, uint256 reserveB,) =
                    UnifapV2Pair(uniswapFactory.pairs(address(gcc), address(usdg))).getReserves();
                uint256 gccReserve = address(gcc) < address(usdg) ? reserveA : reserveB;
                uint256 usdcReserve = address(gcc) < address(usdg) ? reserveB : reserveA;

                console.log("gccReserve after swap= %s", gccReserve);
                console.log("usdcReserve  after swap= %s", usdcReserve);
                console.log("gccLiquidityToAdd = %s", amountLiquidityToAdd);
                console.log("usdcLiquidityToAdd = %s", amounts[1]);
            }

            uniswapRouter.addLiquidity(
                address(gcc), gcc.USDC(), amountLiquidityToAdd, amounts[1], 0, 0, SIMON, block.timestamp
            );
            // This will catch failing revert() or require() with an error message.
            // Handle the error. Maybe emit a log or revert again with a custom message.
            uint256 leftoverGCC = gcc.balanceOf(SIMON);
            uint256 leftoverUSDC = usdg.balanceOf(SIMON);

            // console.log("amountUSDGBeforeLiquidityEvent = %s", amountUSDGBeforeLiquidityEvent);
            uint256 optimalAmountGreaterThanReserves = optimalAmount > totalReserves ? 1 : 0;

            //totalReserves,amount,optimalAmount,leftoverGCC,leftoverUSDC,success,optimalAmountGreaterThanReserves

            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(leftoverGCC),
                    ",",
                    Strings.toString(leftoverUSDC),
                    ",",
                    Strings.toString(success),
                    ",",
                    Strings.toString(optimalAmountGreaterThanReserves)
                )
            );

            // vm.writeLine("swap-succeses.csv", stringToWrite);
            console.log("SUCCESS");
            console.log("GCC DUST  = %s", leftoverGCC);
            console.log("USDC DUST = %s", leftoverUSDC);
        } catch Error(string memory reason) {
            // This will catch failing revert() or require() with an error message.
            // Handle the error. Maybe emit a log or revert again with a custom message.
            uint256 leftoverGCC = gcc.balanceOf(SIMON);
            uint256 leftoverUSDC = usdg.balanceOf(SIMON);
            uint256 optimalAmountGreaterThanReserves = optimalAmount > totalReserves ? 1 : 0;
            console.log("FAIL");

            /**
             * CSV Headers:
             *     totalReserves,amount,optimalAmount,,success,optimalAmountGreaterThanReserves,reason
             */
            string memory stringToWrite = string(
                abi.encodePacked(
                    Strings.toString(totalReserves),
                    ",",
                    Strings.toString(amount),
                    ",",
                    Strings.toString(optimalAmount),
                    ",",
                    Strings.toString(success),
                    ",",
                    Strings.toString(optimalAmountGreaterThanReserves),
                    ",",
                    reason
                )
            );

            if (saveLogs) {
                vm.writeLine("swap-errors.csv", stringToWrite);
            }
        }
    }

    function test_guarded_getStuff() public {
        uint256 a = 0.01 ether;
        uint256 b = 1_000_000_000_000 * 1e6 ether;
        ImpactCatalyst swapper = gcc.IMPACT_CATALYST();
        uint256 MAGNIFIER = 1e18;
        uint256 amount = a;
        uint256 totalReserves = b;
        // console.log("amount = ", amount);
        // console.log("totalReserves = ", totalReserves);
        uint256 optimalAmount =
            swapper.findOptimalAmountToSwap(amount * GCC_MAGNIFICATION, totalReserves * GCC_MAGNIFICATION);
        optimalAmount /= MAGNIFIER;

        uint256 success = amount >= optimalAmount ? 1 : 0;
        string memory stringToWrite = string(
            abi.encodePacked(
                Strings.toString(totalReserves),
                ",",
                Strings.toString(amount),
                ",",
                Strings.toString(optimalAmount),
                ",",
                Strings.toString(success)
            )
        );
        if (saveLogs) {
            vm.writeLine("gcc.csv", stringToWrite);
        }
        /*
        args=[1000000000000000000000000000000001 [1e33],
        569316204070399230977136833119242087930906411821164 [5.693e50]]]
        testFuzz_getStuff(uint256,uint256) (runs: 89, μ: 17220, ~: 17220)
        */

        console.log("amount = %s", amount);
        console.log("optimal amount = %s", optimalAmount);
        assertTrue(amount > optimalAmount, "amount is less than optimal amount");
    }

    // /// forge-config: default.invariant.depth = 1000
    // // We make sure that the bucketMintedBitmap is set correctly by creating
    // /// a stateful fuzz that tracks all used bucketIds
    // function invariant_setBucketMintedBitmapLogic() public {
    //     uint256[] memory allFuzzIds = handler.getAllFuzzIds();
    //     uint256[] memory allNotFuzzIds = handler.getAllNotFuzzIds();
    //     // assertEq(allFuzzIds.length > 0,true);
    //     for (uint256 i = 0; i < allFuzzIds.length; i++) {
    //         assertEq(handler.isBucketMinted(allFuzzIds[i]), true);
    //     }
    //     for (uint256 i = 0; i < allNotFuzzIds.length; i++) {
    //         assertEq(handler.isBucketMinted(allNotFuzzIds[i]), false);
    //     }
    // }

    modifier mintTo(address user) {
        gcc.mint(user, 1e20 ether);
        assertEq(gcc.balanceOf(user), 1e20 ether);
        _;
    }

    modifier prankAsGCA() {
        vm.startPrank(GCA_AND_MINER_POOL_CONTRACT);
        _;
        vm.stopPrank();
    }

    /**
     * This test ensures that the GCC contract
     * is correctly minting to the carbon credit auction contract.
     */
    function test_guarded_sendToCarbonCreditAuction() public {
        vm.startPrank(GCA_AND_MINER_POOL_CONTRACT);
        gcc.mintToCarbonCreditAuction(1, 1e20 ether);
        assertEq(gcc.balanceOf(address(auction)), 1e20 ether);
        assertEq(gcc.isBucketMinted(1), true);
        //Let's have a sanity check and make sure that bucketMinted(2) is false
        assertEq(gcc.isBucketMinted(2), false);
        vm.stopPrank();
    }

    /**
     * This test ensures that only the GCA and
     *     Miner Pool contract can use the ```mintToCarbonCredit``` function.
     */
    function test_guarded_sendToCarbonCreditAuction_callerNotGCA_shouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGCC.CallerNotGCAContract.selector);
        gcc.mintToCarbonCreditAuction(1, 1e20 ether);
        vm.stopPrank();
    }

    //This test ensures that we can only mint from a bucket once
    function test_guarded_sendToCarbonCreditAuctionSameBucketShouldRevert() public {
        test_guarded_sendToCarbonCreditAuction();
        vm.startPrank(GCA_AND_MINER_POOL_CONTRACT);
        vm.expectRevert(IGCC.BucketAlreadyMinted.selector);
        gcc.mintToCarbonCreditAuction(1, 1e20 ether);
    }

    function test_guarded_commitGCC_simon() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        gcc.commitGCC(100 ether, SIMON, 0);
        vm.stopPrank();
        // assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        // assertEq(gcc.totalCreditsCommitted(SIMON), 1e20 ether);
        // assertEq(gcc.balanceOf(address(gcc)), 1e20 ether);
    }

    function test_guarded_commitGCC_notEnoughNominationsShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 100 ether);
        //Should earn earned 74550935508537, so we add 1 and it should revert
        vm.expectRevert(ImpactCatalyst.NotEnoughImpactPowerFromCommitment.selector);
        gcc.commitGCC(100 ether, SIMON, 74550935508537 + 1);
    }

    function test_guarded_commitGCC_GiveRewardsToOthers() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        (, uint256 impactPower) = gcc.commitGCC(1 ether, other, 0);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalImpactPowerEarned(other), impactPower);
    }

    function test_guarded_commitGCC_ApprovalShouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        vm.stopPrank();

        vm.startPrank(other);
        /// spender,allowance,needed
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                other, //spender
                0, //allowance
                1e20 ether //needed
            )
        );
        gcc.commitGCCFor(SIMON, other, 1e20 ether, 0);
        vm.stopPrank();
    }

    function test_guarded_setRetiringAllowance_single() public {
        vm.startPrank(SIMON);
        gcc.increaseCommitAllowance(other, 500_000);

        assertEq(gcc.commitAllowance(SIMON, other), 500_000);

        gcc.decreaseCommitAllowance(other, 250_000);
        assertEq(gcc.commitAllowance(SIMON, other), 250_000);

        gcc.decreaseCommitAllowance(other, 250_000);
        assertEq(gcc.commitAllowance(SIMON, other), 0);

        vm.expectRevert(stdError.arithmeticError);
        gcc.decreaseCommitAllowance(other, 1);
    }

    function test_guarded_setRetiringAllowances_overflowShouldSetToUintMax() public {
        vm.startPrank(SIMON);
        gcc.increaseCommitAllowance(other, type(uint256).max);
        gcc.increaseCommitAllowance(other, 5 ether);
        assertEq(gcc.commitAllowance(SIMON, other), type(uint256).max);
    }

    function test_guarded_setAllowances() public {
        uint256 transferApproval = 500_000;
        uint256 retiringApproval = 900_000;
        vm.startPrank(SIMON);
        gcc.setAllowances(other, transferApproval, retiringApproval);
        assertEq(gcc.commitAllowance(SIMON, other), retiringApproval);
        assertEq(gcc.allowance(SIMON, other), transferApproval);
    }

    function test_guarded_setRetiringAllowances_underflowShouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(stdError.arithmeticError);
        gcc.decreaseCommitAllowance(other, 1 ether);
    }

    // Sets transfer allowance and retiring allowance in one
    function test_guarded_setRetiringAllowance_Double() public {
        vm.startPrank(SIMON);
        gcc.increaseAllowances(other, 500_000);

        assertEq(gcc.commitAllowance(SIMON, other), 500_000);
        assertEq(gcc.allowance(SIMON, other), 500_000);

        gcc.decreaseAllowances(other, 250_000);
        assertEq(gcc.commitAllowance(SIMON, other), 250_000);
        assertEq(gcc.allowance(SIMON, other), 250_000);

        gcc.decreaseAllowances(other, 250_000);
        assertEq(gcc.commitAllowance(SIMON, other), 0);
        assertEq(gcc.allowance(SIMON, other), 0);

        vm.expectRevert();
        gcc.decreaseAllowances(other, 1);
    }

    function test_guarded_commitGCC_onlyRetiringApproval_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        gcc.increaseCommitAllowance(other, 1e20 ether);
        vm.stopPrank();

        vm.startPrank(other);
        /// spender,allowance,needed
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                other, //spender
                0, //allowance
                1e20 ether //needed
            )
        );
        gcc.commitGCCFor(SIMON, other, 1e20 ether, 0);
        vm.stopPrank();
    }

    function test_guarded_commitGCC_onlyTransferApproval_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1e20 ether);
        gcc.increaseAllowance(other, 1e20 ether);
        vm.stopPrank();

        vm.startPrank(other);
        /// spender,allowance,needed
        vm.expectRevert(stdError.arithmeticError);
        gcc.commitGCCFor(SIMON, other, 1e20 ether, 0);
        vm.stopPrank();
    }

    function test_guarded_commitGCC_ApprovalShouldWork() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        gcc.increaseAllowances(other, 1 ether);
        assertEq(gcc.commitAllowance(SIMON, other), 1 ether);
        assertEq(gcc.allowance(SIMON, other), 1 ether);
        vm.stopPrank();

        vm.startPrank(other);
        gcc.commitGCCFor(SIMON, other, 1 ether, 0);
        vm.stopPrank();
    }

    function test_guarded_commitGCC_Signature() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        vm.stopPrank();
        bytes memory signature = _signPermit(
            SIMON, other, other, address(0), 1 ether, gcc.nextCommitNonce(SIMON), block.timestamp + 1000, SIMON_PK
        );

        vm.startPrank(other);
        (, uint256 impactPower) =
            gcc.commitGCCForAuthorized(SIMON, other, 1 ether, block.timestamp + 1000, signature, 0);

        assertEq(gcc.balanceOf(SIMON), 0);
        uint256 otherImpactPower = gcc.totalImpactPowerEarned(other);
        console.log("otherImpactPower = %s", otherImpactPower);
        assertEq(gcc.totalImpactPowerEarned(other), impactPower);
        assertEq(gcc.commitAllowance(SIMON, other), 0);
    }

    function test_guarded_commitGCC_Signature_referSelf_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        vm.stopPrank();
        bytes memory signature = _signPermit(
            SIMON, other, other, SIMON, 1 ether, gcc.nextCommitNonce(SIMON), block.timestamp + 1000, SIMON_PK
        );

        vm.startPrank(other);
        vm.expectRevert(IGCC.CannotReferSelf.selector);
        gcc.commitGCCForAuthorized(SIMON, other, 1 ether, block.timestamp + 1000, signature, SIMON, 0);
    }

    function test_guarded_commitGCC_Signature_expirationInPast_shouldRevert() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        bytes memory signature = _signPermit(
            SIMON, other, SIMON, address(0), 1 ether, gcc.nextCommitNonce(SIMON), block.timestamp + 1000, SIMON_PK
        );

        vm.startPrank(other);
        vm.warp(sigTimestamp + 1);

        vm.expectRevert(IGCC.CommitPermitSignatureExpired.selector);
        gcc.commitGCCForAuthorized(SIMON, other, 1 ether, sigTimestamp, signature, 0);
    }

    function test_guarded_commitGCC_Signature_badSignature_shouldFail() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        bytes memory signature = _signPermit(
            SIMON, other, SIMON, address(0), 1 ether, gcc.nextCommitNonce(SIMON), block.timestamp + 1000, SIMON_PK
        );

        vm.startPrank(other);
        vm.expectRevert(IGCC.CommitSignatureInvalid.selector);
        gcc.commitGCCForAuthorized(SIMON, other, 1 ether, sigTimestamp + 1, signature, 0);
    }

    function test_guarded_commitGCC_badSigner_shouldFail() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        (address badActor, uint256 badActorPk) = _createAccount(9998, 1 ether);
        bytes memory signature = _signPermit(
            badActor,
            other,
            badActor,
            address(0),
            1 ether,
            gcc.nextCommitNonce(SIMON),
            block.timestamp + 1000,
            badActorPk
        );

        vm.startPrank(other);
        vm.expectRevert(IGCC.CommitSignatureInvalid.selector);
        gcc.commitGCCForAuthorized(SIMON, other, 1e20 ether, sigTimestamp, signature, 0);
    }

    function test_guarded_cannotincreaseCommitAllowanceByZero() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGCC.MustIncreaseCommitAllowanceByAtLeastOne.selector);
        gcc.increaseCommitAllowance(other, 0);
        vm.stopPrank();
    }

    function test_guarded_commitGCC_signatureReplayShouldFail() public {
        vm.startPrank(SIMON);
        gcc.mint(SIMON, 1 ether);
        vm.stopPrank();
        uint256 currentTimestamp = block.timestamp;
        uint256 sigTimestamp = block.timestamp + 1000;
        bytes memory signature = _signPermit(
            SIMON, other, other, address(0), 1 ether, gcc.nextCommitNonce(SIMON), block.timestamp + 1000, SIMON_PK
        );

        vm.startPrank(other);
        gcc.commitGCCForAuthorized(SIMON, other, 1 ether, sigTimestamp, signature, 0);
        vm.expectRevert(IGCC.CommitSignatureInvalid.selector);
        gcc.commitGCCForAuthorized(SIMON, other, 1 ether, sigTimestamp, signature, 0);
    }

    function test_guarded_commitUSDC_referral() public {
        mintUSDG(SIMON, 1000 * 1e6);
        vm.startPrank(SIMON);
        // usdc.mint(SIMON, 1000 * 1e6);
        usdg.approve(address(gcc), 1000 * 1e6);
        uint256 impactPower = gcc.commitUSDC(1000 * 1e6, SIMON, address(0), 0);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalImpactPowerEarned(SIMON), impactPower);
        assertEq(gov.nominationsOf(SIMON), impactPower);
        vm.stopPrank();
    }

    function test_guarded_commitUSDC_referralAddressEqFrom_shouldRevert() public {
        mintUSDG(SIMON, 1000 * 1e6);
        vm.startPrank(SIMON);
        // usdc.mint(SIMON, 1000 * 1e6);
        usdg.approve(address(gcc), 1000 * 1e6);
        vm.expectRevert(IGCC.CannotReferSelf.selector);
        uint256 impactPower = gcc.commitUSDC(1000 * 1e6, SIMON, SIMON, 0);
        vm.stopPrank();
    }

    function test_guarded_commitUSDC() public {
        mintUSDG(SIMON, 1000 * 1e6);

        vm.startPrank(SIMON);
        usdg.approve(address(gcc), 1000 * 1e6);
        uint256 impactPower = gcc.commitUSDC(1000 * 1e6, SIMON, 0);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalImpactPowerEarned(SIMON), impactPower);
        assertEq(gov.nominationsOf(SIMON), impactPower);
        vm.stopPrank();
    }

    function test_guarded_commitUSDC_notEnoughImpactPowerShouldRevert() public {
        mintUSDG(SIMON, 1000 * 1e6);

        vm.startPrank(SIMON);
        usdg.approve(address(gcc), 1000 * 1e6);
        //Should give us 261693317327390 impact power
        //so we add 1 and it should revert
        vm.expectRevert(ImpactCatalyst.NotEnoughImpactPowerFromCommitment.selector);
        uint256 impactPower = gcc.commitUSDC(1000 * 1e6, SIMON, 261693317327390 + 1);
        vm.stopPrank();
    }

    function test_guarded_commitUSDC_rewardToOther() public {
        mintUSDG(SIMON, 1000 * 1e6);
        vm.startPrank(SIMON);
        usdg.approve(address(gcc), 1000 * 1e6);
        address rewardAddress = address(0xffffaa);
        uint256 impactPower = gcc.commitUSDC(1000 * 1e6, rewardAddress, 0);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalImpactPowerEarned(rewardAddress), impactPower);
        assertEq(gov.nominationsOf(rewardAddress), impactPower);
        vm.stopPrank();
    }

    function test_guarded_commitUSDC_permit() public {
        mintUSDG(SIMON, 1000 * 1e6);

        vm.startPrank(SIMON);
        usdg.approve(address(gcc), 1000 * 1e6);
        uint256 deadline = block.timestamp + 1000;
        (uint8 v, bytes32 r, bytes32 s) =
            _signUSDCPermit(SIMON, address(gcc), 1000 * 1e6, usdc.nonces(SIMON), deadline, SIMON_PK);

        uint256 impactPower = gcc.commitUSDCSignature(1000 * 1e6, SIMON, address(0), deadline, v, r, s, 0);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalImpactPowerEarned(SIMON), impactPower);
        assertEq(gov.nominationsOf(SIMON), impactPower);
        vm.stopPrank();
    }

    function test_guarded_commitUSDC_permit_rewardToOther() public {
        mintUSDG(SIMON, 1000 * 1e6);

        vm.startPrank(SIMON);
        usdg.approve(address(gcc), 1000 * 1e6);
        uint256 deadline = block.timestamp + 1000;
        (uint8 v, bytes32 r, bytes32 s) =
            _signUSDCPermit(SIMON, address(gcc), 1000 * 1e6, usdc.nonces(SIMON), deadline, SIMON_PK);
        address rewardAddress = address(0xffffaa);
        uint256 impactPower = gcc.commitUSDCSignature(1000 * 1e6, rewardAddress, address(0), deadline, v, r, s, 0);
        assertEq(gcc.balanceOf(SIMON), 0);
        //make sure i get neutrality
        assertEq(gcc.totalImpactPowerEarned(rewardAddress), impactPower);
        assertEq(gov.nominationsOf(rewardAddress), impactPower);
        vm.stopPrank();
    }

    /* -------------------------------------------------------------------------- */
    /*                                   helpers                                  */
    /* -------------------------------------------------------------------------- */
    function _createAccount(uint256 privateKey, uint256 amount) internal returns (address addr, uint256 priv) {
        addr = vm.addr(privateKey);
        vm.deal(addr, amount);
        priv = privateKey;

        return (addr, priv);
    }

    function _signPermit(
        address owner,
        address spender,
        address rewardAddress,
        address referralAddress,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 privateKey
    ) internal returns (bytes memory signature) {
        bytes32 structHash = keccak256(
            abi.encode(
                gcc.COMMIT_PERMIT_TYPEHASH(), owner, spender, rewardAddress, referralAddress, amount, nonce, deadline
            )
        );
        bytes32 messageHash = MessageHashUtils.toTypedDataHash(gcc.domainSeparatorV4(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        signature = abi.encodePacked(r, s, v);
    }

    function _signUSDCPermit(
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 privateKey
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonce, deadline));
        bytes32 messageHash = MessageHashUtils.toTypedDataHash(usdc.DOMAIN_SEPARATOR(), structHash);

        (v, r, s) = vm.sign(privateKey, messageHash);
    }

    function test_guarded_swap() public {
        vm.startPrank(accountWithLotsOfUSDC);
        //     vm.selectFork(mainnetFork);
        //     glwContract = new TestGLOW(earlyLiquidity,vestingContract);
        //     glw = address(glwContract);
        //     (SIMON, SIMON_PK) = _createAccount(9999, 1e20 ether);
        //     gov = new Governance();
        // gcc = new TestGCC(GCA_AND_MINER_POOL_CONTRACT, address(gov), glw,address(usdc),address(uniswapRouter));
        //     auction = CarbonCreditDutchAuction(address(gcc.CARBON_CREDIT_AUCTION()));
        //     handler = new Handler(address(gcc),GCA_AND_MINER_POOL_CONTRACT);
        //     gov.setContractAddresses(address(gcc), gca, vetoCouncil, grantsTreasury, glw);

        gcc.mint(accountWithLotsOfUSDC, 1e20 ether);
        usdc.mint(accountWithLotsOfUSDC, 2000 * 1e6);
        usdc.approve(address(uniswapRouter), 2000 * 1e6);
        gcc.approve(address(uniswapRouter), 1e20 ether);

        gcc.commitGCC(50 ether, SIMON, 0);
        vm.stopPrank();
        address swapper = address(gcc.IMPACT_CATALYST());
        console.log("swapper usdc balance after = ", IERC20(usdc).balanceOf(swapper));
        console.log("swapper gcc balance after = ", gcc.balanceOf(swapper));
    }

    // function test_guarded_swap2() public {
    //     vm.startPrank(accountWithLotsOfUSDC);
    //     vm.selectFork(mainnetFork);
    //     glwContract = new TestGLOW(earlyLiquidity,vestingContract);
    //     glw = address(glwContract);
    //     (SIMON, SIMON_PK) = _createAccount(9999, 1e20 ether);
    //     gov = new Governance();
    // gcc = new TestGCC(GCA_AND_MINER_POOL_CONTRACT, address(gov), glw,address(usdc),address(uniswapRouter));
    //     auction = CarbonCreditDutchAuction(address(gcc.CARBON_CREDIT_AUCTION()));
    //     handler = new Handler(address(gcc),GCA_AND_MINER_POOL_CONTRACT);
    //     gov.setContractAddresses(address(gcc), gca, vetoCouncil, grantsTreasury, glw);

    //     gcc.mint(accountWithLotsOfUSDC, 1e20 ether);
    //     address usdc = gcc.USDC();
    //     //Assume that 1 GCC = $20
    //     IUniswapRouterV2 router = gcc.UNISWAP_ROUTER();
    //     uint256 amountA = 100 ether; //100 gcc
    //     uint256 amountB = 2000 * 1e6; //2000 usdc
    //     gcc.approve(address(router), amountA);
    //     IERC20(usdc).approve(address(router), amountB);
    //     uint256 gccBalanceBefore = 1e20 ether;
    //     uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(accountWithLotsOfUSDC);
    //     router.addLiquidity(
    //         address(gcc), usdc, amountA, amountB, amountA, amountB, accountWithLotsOfUSDC, block.timestamp
    //     );
    //     uint256 gccBalanceAfter = gcc.balanceOf(accountWithLotsOfUSDC);
    //     uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(accountWithLotsOfUSDC);

    //     address pairAddress = UniswapV2Library.pairFor(UNISWAP_V2_FACTORY, address(gcc), usdc);
    //     uint256 balanceOfLPTokens = IERC20(pairAddress).balanceOf(accountWithLotsOfUSDC);
    //     // console.log("balance of LP tokens = %s", balanceOfLPTokens);
    //     // //log the diffs
    //     // console.log("Gcc diff = %s", gccBalanceBefore - gccBalanceAfter);
    //     // console.log("USDC diff = %s", usdcBalanceBefore - usdcBalanceAfter);

    //     //Perform a swap
    //     IERC20(usdc).approve(address(gcc), type(uint256).max);
    //     gcc.swapUSDC(500 * 1e6);
    //     address swapper = address(gcc.IMPACT_CATALYST());
    // }

    function seedLP(uint256 amountGCC, uint256 amountUSDG) public {
        vm.startPrank(usdgOwner);
        gcc.mint(usdgOwner, amountGCC);
        gcc.approve(address(uniswapRouter), amountGCC);
        usdc.mint(usdgOwner, amountUSDG);
        usdc.approve(address(usdg), amountUSDG);
        usdg.swap(usdgOwner, amountUSDG);
        usdg.approve(address(uniswapRouter), amountUSDG);
        uniswapRouter.addLiquidity(
            address(gcc), address(usdg), amountGCC, amountUSDG, amountGCC, amountUSDG, usdgOwner, block.timestamp
        );
        vm.stopPrank();
    }

    function mintUSDG(address user, uint256 amount) public {
        vm.startPrank(user);
        usdc.mint(user, amount);
        usdc.approve(address(usdg), amount);
        usdg.swap(user, amount);
        vm.stopPrank();
    }
}
