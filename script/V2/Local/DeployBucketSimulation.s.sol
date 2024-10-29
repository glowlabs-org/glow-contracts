// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "@/testing/GuardedLaunch/TestGCC.GuardedLaunch.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import "forge-std/StdUtils.sol";
import {TestGLOWGuardedLaunch} from "@/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCAV2 as MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCAV2.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPoolV2 as IMinerPool} from "@/interfaces/IMinerPoolV2.sol";
import {BucketSubmissionV2 as BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmissionV2.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";
import {USDG} from "@/USDG.sol";

contract DeployBucketSimulation is Script {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOWGuardedLaunch glow;
    MockUSDC usdc;
    MockUSDC grc2;

    SafetyDelay holdingContract;
    TestGCCGuardedLaunch gcc;

    uint256 internal VESTING_PERIODS;

    //TODO: add usdg to testing
    TestUSDG usdg;

    //--------  ADDRESSES ---------//
    address governance = address(0x1);
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw;
    uint256 defaultAddressPrivateKey;
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);

    // uint256 mainnetFork;
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);

    function run() public {
        vm.startBroadcast();
        address deployer = tx.origin;
        if (deployer != SIMON) revert("Deployer must be simon");
        vm.deal(deployer, 100000000 ether);
        //Make sure we don't start at 0
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();

        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedVetoCouncilContract = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedGCA = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 6);

        gcc = new TestGCCGuardedLaunch({
            _gcaAndMinerPoolContract: address(precomputedGCA),
            _governance: address(governance),
            _glowToken: address(precomputedGlow),
            _usdg: address(precomputedUSDG),
            _vetoCouncilAddress: address(precomputedVetoCouncilContract),
            _uniswapRouter: address(uniswapRouter),
            _uniswapFactory: address(uniswapFactory)
        }); //deployerNonce
        gcc.allowlistPostConstructionContracts();

        glow = new TestGLOWGuardedLaunch({
            _earlyLiquidityAddress: earlyLiquidity,
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: precomputedGCA,
            _vetoCouncilAddress: precomputedVetoCouncilContract,
            _grantsTreasuryAddress: grantsTreasuryAddress,
            _owner: SIMON,
            _usdg: address(precomputedUSDG),
            _uniswapV2Factory: address(uniswapFactory),
            _gccContract: address(gcc)
        }); //deployerNonce + 1
        address[] memory temp = new address[](1);
        address[] memory startingAgents = new address[](1);
        temp[0] = SIMON;
        startingAgents[0] = address(SIMON);
        vetoCouncil = new VetoCouncil(governance, address(glow), startingAgents); //deployer nonce + 3
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedGCA); //deployer nonce + 4
        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployer nonce + 5
            temp,
            address(glow),
            governance,
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(precomputedUSDG),
            vetoCouncilAddress,
            address(holdingContract),
            address(gcc)
        );

        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _glow: address(glow),
            _gcc: address(gcc),
            _holdingContract: address(holdingContract),
            _vetoCouncilContract: vetoCouncilAddress,
            _impactCatalyst: address(gcc.IMPACT_CATALYST())
        }); //deployerNonce + 6

        vm.stopBroadcast();
    }
}
