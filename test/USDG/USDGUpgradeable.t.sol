// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {MockGovernance} from "@/testing/MockGovernance.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {TestGCC} from "@/testing/TestGCC.sol";
import {HalfLife} from "@/libraries/HalfLife.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";
import {USDGUpgradeable} from "@/USDGUpgradeable.sol";
import {USDGUpgradeableV2} from "~test/USDG/USDGUpgradeableV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockUSDCTax} from "@/testing/MockUSDCTax.sol";

struct AccountWithPK {
    uint256 privateKey;
    address account;
}

contract USDGUpgradeableTest is Test {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOW glow;
    MockUSDC usdc;
    MockUSDCTax usdcTax;
    USDGUpgradeable usdg;
    MockUSDC grc2;
    MockGovernance governance;
    TestGCC gcc;
    GrantsTreasury grantsTreasury;
    SafetyDelay holdingContract;
    AccountWithPK[10] accounts;

    address mockImpactCatalyst = address(0x1233918293819389128);

    uint256 constant NOMINATION_DECIMALS = 12;

    //--------  ADDRESSES ---------//
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON;
    uint256 SIMON_PRIVATE_KEY;
    address OTHER_VETO_1 = address(0x991);
    address OTHER_VETO_2 = address(0x992);
    address OTHER_VETO_3 = address(0x993);
    address OTHER_VETO_4 = address(0x994);
    address OTHER_VETO_5 = address(0x995);
    address grantsRecipient = address(0x4123141);

    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw = address(0x555);
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);

    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);

    address[] startingAgents;

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);
    uint256 ONE_YEAR = 365 * uint256(1 days);

    address deployer = tx.origin;

    function setUp() public {
        usdc = new MockUSDC();
        _deployFixture(address(usdc));
    }

    function _deployFixture(address _usdc) public {
        vm.startPrank(deployer);
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        //Make sure we don't start at 0
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        for (uint256 i = 0; i < 10; i++) {
            (address account, uint256 privateKey) = _createAccount(0x44444 + i, type(uint256).max);
            accounts[i] = AccountWithPK(privateKey, account);
        }
        vm.warp(10);

        address _usdgImplementation = address(new USDGUpgradeable());
        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce);

        address precomputedGrantsAddress = computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedHoldingContractAddress = computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedMinerPoolAndGCAAddress = computeCreateAddress(deployer, deployerNonce + 7);
        address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 3);
        glow = new TestGLOW(
            earlyLiquidity,
            vestingContract,
            precomputedMinerPoolAndGCAAddress,
            precomputedVetoCouncilAddress,
            precomputedGrantsAddress
        ); //deployerNonce

        gcc = new TestGCC(
            address(minerPoolAndGCA),
            address(precomputedGovernance),
            address(glow),
            address(precomputedUSDG),
            address(uniswapRouter)
        ); //deployerNonce + 1

        address precomputedImpactCatalyst = computeCreateAddress(address(gcc), 1); //since gcc deploys impact catalyst after carbon credit auction

        governance = new MockGovernance({
            gcc: address(gcc),
            gca: precomputedMinerPoolAndGCAAddress,
            vetoCouncil: precomputedVetoCouncilAddress,
            grantsTreasury: precomputedGrantsAddress,
            glw: address(glow)
        }); //deployerNonce + 2
        usdg = USDGUpgradeable(
            address(
                new ERC1967Proxy(
                    address(_usdgImplementation),
                    abi.encodeCall(USDGUpgradeable.initialize, (address(_usdc), address(precomputedGovernance)))
                )
            )
        ); //deplpoyer nonce + 3
        address[] memory temp = new address[](0);
        startingAgents.push(address(SIMON));
        startingAgents.push(OTHER_VETO_1);
        startingAgents.push(OTHER_VETO_2);
        startingAgents.push(OTHER_VETO_3);
        startingAgents.push(OTHER_VETO_4);
        startingAgents.push(OTHER_VETO_5);
        grantsTreasury = new GrantsTreasury(address(glow), address(governance)); //deployerNonce + 4
        grantsTreasuryAddress = address(grantsTreasury);
        vetoCouncil = new VetoCouncil(address(governance), address(glow), startingAgents); //deployerNonce + 5
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedMinerPoolAndGCAAddress); //deployerNonce + 6

        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployerNonce + 7
            temp,
            address(glow),
            address(governance),
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(usdg),
            vetoCouncilAddress,
            address(holdingContract),
            address(gcc)
        );

        grc2 = new MockUSDC(); //deployerNonce + 8

        vm.stopPrank();

        vm.startPrank(usdgOwner);
        // // usdg.setAllowlistedContracts({
        // //     _glow: address(glow),
        // //     _gcc: address(gcc),
        // //     _holdingContract: address(holdingContract),
        // //     _vetoCouncilContract: vetoCouncilAddress,
        // //     _impactCatalyst: mockImpactCatalyst
        // // });
        /*MockUSDC(_usdc).mint(usdgOwner, 100000000 * 1e6);
        MockUSDC(usdc).approve(address(usdg), 100000000 * 1e6);
        usdg.mint(usdgOwner, 100000000 * 1e6);*/
        vm.stopPrank();

        delete startingAgents;
    }

    function test_swapForUSDC_shouldMatchOneToOne() public {
        address me = address(usdgOwner);
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.mint(me, 100000000 * 1e6);
        assertEq(usdg.balanceOf(me), 100000000 * 1e6);
    }

    function test_swapForUSDCTax_shouldMatchOneToOne() public {
        usdcTax = new MockUSDCTax();
        _deployFixture(address(usdcTax));
    }

    function test_swapZeroAmountShouldRevert() public {
        address me = address(usdgOwner); // a non-allowlisted contract
        address other = address(0x123);
        vm.startPrank(me);
        usdc.mint(me, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        vm.expectRevert(USDGUpgradeable.ErrMustMintPositiveAmount.selector);
        usdg.mint(me, 0);
    }

    function test_upgrade_fromGovernance_shouldWork() public {
        vm.startPrank(address(governance));
        USDGUpgradeableV2 newUSDG = new USDGUpgradeableV2();
        usdg.upgradeToAndCall(address(newUSDG), "");
        //Calling functions should work
        USDGUpgradeableV2 _usdgV2 = USDGUpgradeableV2(address(usdg));
        _usdgV2.newSetter(1212312);
        assertEq(_usdgV2.newVar(), 1212312);
        vm.stopPrank();
    }

    function test_upgrade_notFromGovernance_shouldRevert() public {
        vm.startPrank(usdgOwner);
        vm.expectRevert(USDGUpgradeable.ErrCallerNotGovernance.selector);
        usdg.upgradeToAndCall(address(0xffff), "");
        vm.stopPrank();
    }

    //-------------------------------------------------------------------------
    // Test Helpers
    //-------------------------------------------------------------------------

    function _createAccount(uint256 privateKey, uint256 amount)
        internal
        returns (address addr, uint256 signerPrivateKey)
    {
        addr = vm.addr(privateKey);
        vm.deal(addr, amount);
        signerPrivateKey = privateKey;
        return (addr, signerPrivateKey);
    }

    function seedLP() public {
        vm.startPrank(usdgOwner);
        uint256 amountGCC = gcc.balanceOf(usdgOwner);
        uint256 amountUSDG = usdg.balanceOf(usdgOwner);
        gcc.mint(usdgOwner, amountGCC);
        gcc.approve(address(uniswapRouter), amountGCC);
        usdg.approve(address(uniswapRouter), amountUSDG);
        uniswapRouter.addLiquidity(address(gcc), address(usdg), amountGCC, amountUSDG, 0, 0, usdgOwner, block.timestamp);
        vm.stopPrank();
    }
}
