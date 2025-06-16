// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.19;

// import "forge-std/Test.sol";
// import "@glow/testing/TestGCC.sol";
// import "forge-std/console.sol";
// import {IGCA} from "@glow/interfaces/IGCA.sol";
// import {MockGCA} from "@glow/MinerPoolAndGCA/mock/MockGCA.sol";
// // import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
// import {CarbonCreditDutchAuction} from "@glow/CarbonCreditDutchAuction.sol";
// import "forge-std/StdUtils.sol";
// import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// import {TestGLOW} from "@glow/testing/TestGLOW.sol";
// import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
// import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
// import {MockMinerPoolAndGCA} from "@glow/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
// import {MockUSDC} from "@glow/testing/MockUSDC.sol";
// import {IMinerPool} from "@glow/interfaces/IMinerPool.sol";
// import {BucketSubmission} from "@glow/MinerPoolAndGCA/BucketSubmission.sol";
// import {VetoCouncil} from "@glow/VetoCouncil.sol";
// import {MockGovernance} from "@glow/testing/MockGovernance.sol";
// import {IGovernance} from "@glow/interfaces/IGovernance.sol";
// import {TestGCC} from "@glow/testing/TestGCC.sol";
// import {HalfLife} from "@glow/libraries/HalfLife.sol";
// import {GrantsTreasury} from "@glow/GrantsTreasury.sol";
// import {Holding, ClaimHoldingArgs, IHoldingContract, HoldingContract} from "@glow/HoldingContract.sol";
// import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
// import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
// import {WETH9} from "@glow/UniswapV2/contracts/test/WETH9.sol";
// import {TestUSDG} from "@glow/testing/TestUSDG.sol";
// import {USDG} from "@glow/USDG.sol";

// struct AccountWithPK {
//     uint256 privateKey;
//     address account;
// }

// // struct AnvilFixture = {

// // }
// contract DeployAnvilFixture is Test {
//     //--------  CONTRACTS ---------//
//     UnifapV2Factory public uniswapFactory;
//     WETH9 public weth;
//     UnifapV2Router public uniswapRouter;
//     MockMinerPoolAndGCA public minerPoolAndGCA;
//     TestGLOW public glow;
//     MockUSDC public usdc;
//     TestUSDG public usdg;
//     MockUSDC public grc2;
//     MockGovernance public governance;
//     TestGCC public gcc;
//     GrantsTreasury public grantsTreasury;
//     HoldingContract public holdingContract;
//     VetoCouncil public vetoCouncil;

//     address public deployer;

//     AccountWithPK[10] accounts;

//     address mockImpactCatalyst = address(0x1233918293819389128);

//     uint256 constant NOMINATION_DECIMALS = 12;

//     //--------  ADDRESSES ---------//
//     address public earlyLiquidity = address(0x2);
//     address public vestingContract = address(0x3);
//     address public vetoCouncilAddress;
//     address public grantsTreasuryAddress = address(0x5);
//     address public SIMON;
//     uint256 public SIMON_PRIVATE_KEY;
//     address public OTHER_VETO_1 = address(0x991);
//     address public OTHER_VETO_2 = address(0x992);
//     address public OTHER_VETO_3 = address(0x993);
//     address public OTHER_VETO_4 = address(0x994);
//     address public OTHER_VETO_5 = address(0x995);
//     address public grantsRecipient = address(0x4123141);

//     address public OTHER_GCA = address(0x7);
//     address public OTHER_GCA_2 = address(0x8);
//     address public OTHER_GCA_3 = address(0x9);
//     address public OTHER_GCA_4 = address(0x10);
//     address public carbonCreditAuction = address(0x11);
//     address public defaultAddressInWithdraw = address(0x555);
//     address public bidder1 = address(0x12);
//     address public bidder2 = address(0x13);

//     address public usdgOwner = address(0xaaa112);
//     address public usdcReceiver = address(0xaaa113);

//     address[] startingAgents;

//     //--------  CONSTANTS ---------//
//     uint256 constant ONE_WEEK = 7 * uint256(1 days);
//     uint256 ONE_YEAR = 365 * uint256(1 days);

//     // function setUp() public {
//     //     vm.startPrank(deployer);
//     //     uniswapFactory = new UnifapV2Factory();
//     //     weth = new WETH9();
//     //     uniswapRouter = new UnifapV2Router(address(uniswapFactory));
//     //     //Make sure we don't start at 0
//     //     governance = new MockGovernance();
//     //     (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
//     //     for (uint256 i = 0; i < 10; i++) {
//     //         (address account, uint256 privateKey) = _createAccount(0x44444 + i, type(uint256).max);
//     //         accounts[i] = AccountWithPK(privateKey, account);
//     //     }
//     //     vm.warp(10);
//     //     usdc = new MockUSDC();
//     //     usdg = new TestUSDG({
//     //         _usdc: address(usdc),
//     //         _usdcReceiver: usdcReceiver,
//     //         _owner: usdgOwner,
//     //         _univ2Factory: address(uniswapFactory)
//     //     });

//     //     glow = new TestGLOW(earlyLiquidity, vestingContract);
//     //     address[] memory temp = new address[](0);
//     //     startingAgents.push(address(SIMON));
//     //     startingAgents.push(OTHER_VETO_1);
//     //     startingAgents.push(OTHER_VETO_2);
//     //     startingAgents.push(OTHER_VETO_3);
//     //     startingAgents.push(OTHER_VETO_4);
//     //     startingAgents.push(OTHER_VETO_5);
//     //     grantsTreasury = new GrantsTreasury(address(glow), address(governance));
//     //     grantsTreasuryAddress = address(grantsTreasury);
//     //     vetoCouncil = new VetoCouncil(address(governance), address(glow), startingAgents);
//     //     vetoCouncilAddress = address(vetoCouncil);
//     //     holdingContract = new HoldingContract(vetoCouncilAddress);

//     //     minerPoolAndGCA = new MockMinerPoolAndGCA(
//     //         temp,
//     //         address(glow),
//     //         address(governance),
//     //         keccak256("requirementsHash"),
//     //         earlyLiquidity,
//     //         address(usdg),
//     //         vetoCouncilAddress,
//     //         address(holdingContract)
//     //     );

//     //     //TODO: precompute
//     //     // glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
//     //     grc2 = new MockUSDC();
//     //     gcc = new TestGCC(
//     //         address(minerPoolAndGCA), address(governance), address(glow), address(usdg), address(uniswapRouter)
//     //     );
//     //     // governance.setContractAddresses(gcc, gca, vetoCouncil, grantsTreasury, glw);
//     //     governance.setContractAddresses(
//     //         address(gcc), address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress, address(glow)
//     //     );

//     //     vm.stopPrank();

//     //     vm.startPrank(usdgOwner);
//     //     usdg.setAllowlistedContracts({
//     //         _glow: address(glow),
//     //         _gcc: address(gcc),
//     //         _holdingContract: address(holdingContract),
//     //         _vetoCouncilContract: vetoCouncilAddress,
//     //         _impactCatalyst: mockImpactCatalyst
//     //     });
//     //     usdc.mint(usdgOwner, 100000000 * 1e6);
//     //     usdc.approve(address(usdg), 100000000 * 1e6);
//     //     usdg.swap(usdgOwner, 100000000 * 1e6);
//     //     vm.stopPrank();
//     //     seedLP(500 ether, 100000000 * 1e6);
//     // }

//     function deployFixture() public {
//         if (deployer == address(0)) {
//             revert("Deployer not set");
//         }
//     }

//     function setDeployer(address _deployer) public {
//         deployer = _deployer;
//     }
// }
