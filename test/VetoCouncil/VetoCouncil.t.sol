// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
import {IGrantsTreasury} from "../../src/interfaces/IGrantsTreasury.sol";
import {GrantsTreasury} from "../../src/GrantsTreasury.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VetoCouncil} from "@glow/VetoCouncil/VetoCouncil.sol";
import {IVetoCouncil} from "@glow/interfaces/IVetoCouncil.sol";
import {VetoCouncilSalaryHelper, Status} from "@glow/VetoCouncil/VetoCouncilSalaryHelper.sol";
import {NULL_ADDRESS} from "@glow/VetoCouncil/VetoCouncilSalaryHelper.sol";

contract VetoCouncilTest is Test {
    TestGLOW public glw;
    address public constant GRANTS_TREASURY = address(0x11111111);
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    VetoCouncil public vetoCouncil;
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);
    address public constant GOVERNANCE = address(0x6);
    address public constant NOT_GOVERNANCE = address(0x7);
    address public constant OTHER_1 = address(0x8);
    address public constant OTHER_2 = address(0x9);
    address public constant VETO_COUNCIL_ADDRESS = address(0x11);
    uint256 public constant GRANTS_INFLATION_PER_WEEK = 40_000 ether;

    address deployer = tx.origin;

    function setUp() public {
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        //current nonce used to deploy glow,
        //the one after that is used to deploy veto council
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 1);
        //make sure block.timestamp does not start at 0
        vm.warp(1);
        glw = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, precomputedVetoCouncilAddress, GRANTS_TREASURY);
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw), startingAgents);

        assertTrue(vetoCouncil.isCouncilMember(SIMON));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_1));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_2));
        vm.stopPrank();
    }

    //Testing so we can coverage in iloc
    function test_setUp() public {
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        //current nonce used to deploy glow,
        //the one after that is used to deploy veto council
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 1);
        glw = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, precomputedVetoCouncilAddress, GRANTS_TREASURY);
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw), startingAgents);

        //TODO: precompute
        // glw.setContractAddresses(GCA, address(vetoCouncil), GRANTS_TREASURY);
        assertTrue(vetoCouncil.isCouncilMember(SIMON));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_1));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_2));
        vm.stopPrank();
    }

    function test_newAgentIsAlreadyActive_shouldReturnFalseZellic() public {
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        //current nonce used to deploy glow,
        //the one after that is used to deploy veto council
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 1);
        glw = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, precomputedVetoCouncilAddress, GRANTS_TREASURY);
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(0x33333);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw), startingAgents);
        vm.stopPrank();
        vm.startPrank(GOVERNANCE);
        address oldAgent = address(0x33333);
        bool slashOldAgent = false;
        //Remove simon
        assert(vetoCouncil.addAndRemoveCouncilMember(SIMON, address(0), slashOldAgent));
        //Try re-adding the already active `oldAgent`
        assert(vetoCouncil.addAndRemoveCouncilMember(address(0), address(0x1234512345), slashOldAgent));
        Status memory oldAgentStatus = vetoCouncil.memberStatus(address(0x1234512345));
        //The old agent, aka the agent we added,
        //Should now be active
        assert(oldAgentStatus.isActive);
        vm.stopPrank();
    }

    //Testing so we can coverage in iloc
    function test_removingAnAgent_whenThereAreZeroAgent_shouldReturnFalse() public {
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        //current nonce used to deploy glow,
        //the one after that is used to deploy veto council
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 1);
        glw = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, precomputedVetoCouncilAddress, GRANTS_TREASURY);
        address[] memory startingAgents = new address[](1);
        startingAgents[0] = address(SIMON);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw), startingAgents);
        vm.stopPrank();
        vm.startPrank(GOVERNANCE);
        address oldAgent = address(SIMON);
        address newAgent = address(0);
        bool slashOldAgent = false;
        assert(vetoCouncil.addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent));
        oldAgent = address(0x1);
        newAgent = address(0x0);
        slashOldAgent = false;
        assert(vetoCouncil.addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent) == false);
        vm.stopPrank();
    }

    function test_newAgentIsAlreadySlashed_shouldReturnFalse() public {
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        //current nonce used to deploy glow,
        //the one after that is used to deploy veto council
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 1);
        glw = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, precomputedVetoCouncilAddress, GRANTS_TREASURY);
        address[] memory startingAgents = new address[](1);
        startingAgents[0] = address(SIMON);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw), startingAgents);
        vm.stopPrank();
        vm.startPrank(GOVERNANCE);
        address oldAgent = address(SIMON);
        address newAgent = address(0);
        bool slashOldAgent = true;
        assert(vetoCouncil.addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent));
        oldAgent = address(0);
        newAgent = SIMON;
        slashOldAgent = false;
        assert(vetoCouncil.addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent) == false);
        Status memory simonStatus = vetoCouncil.memberStatus(SIMON);
        assert(simonStatus.isActive == false);
        assert(simonStatus.indexInArray == type(uint8).max); //this is the null index
        assert(simonStatus.isSlashed);
        vm.stopPrank();
    }

    function test_newAgentIsAlreadyActive_shouldReturnFalse_simple() public {
        vm.startPrank(deployer);
        uint256 deployerNonce = vm.getNonce(deployer);
        //current nonce used to deploy glow,
        //the one after that is used to deploy veto council
        address precomputedVetoCouncilAddress = computeCreateAddress(deployer, deployerNonce + 1);
        glw = new TestGLOW(EARLY_LIQUIDITY, VESTING_CONTRACT, GCA, precomputedVetoCouncilAddress, GRANTS_TREASURY);
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(0x33333);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw), startingAgents);
        vm.stopPrank();
        vm.startPrank(GOVERNANCE);
        address oldAgent = address(0x33333);
        bool slashOldAgent = false;
        //Remove simon
        assert(vetoCouncil.addAndRemoveCouncilMember(SIMON, address(0), slashOldAgent));
        //Try re-adding the already active `oldAgent`
        assert(!vetoCouncil.addAndRemoveCouncilMember(address(0), oldAgent, slashOldAgent));
        Status memory oldAgentStatus = vetoCouncil.memberStatus(oldAgent);
        //None of the old agent status should have changed
        assert(oldAgentStatus.isActive);
        assert(oldAgentStatus.indexInArray == 1);
        assert(!oldAgentStatus.isSlashed);
        vm.stopPrank();
    }

    function test_vetoCouncil_claimFromInflation() public {
        vm.warp(block.timestamp + 1 weeks);
        vetoCouncil.pullGlowFromInflation();
        uint256 balance = glw.balanceOf(address(vetoCouncil));
        assert(4999.95 ether <= balance && balance <= 5_000 ether);
    }

    function test_setUp_zeroAddressShouldFailInConstructor_governance() public {
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vm.expectRevert(IVetoCouncil.ZeroAddressInConstructor.selector);
        vetoCouncil = new VetoCouncil(address(0), address(1), startingAgents);
    }

    function test_setUp_8CouncilMembers_shouldRevert() public {
        address[] memory startingAgents = new address[](8);
        for (uint256 i; i < startingAgents.length; ++i) {
            startingAgents[i] = address(uint160(i + 30));
        }
        vm.expectRevert(IVetoCouncil.MaxCouncilMembersExceeded.selector);
        vetoCouncil = new VetoCouncil(address(1), address(2), startingAgents);
    }

    function test_setUp_zeroAddressShouldFailInConstructor_glw() public {
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vm.expectRevert(IVetoCouncil.ZeroAddressInConstructor.selector);
        vetoCouncil = new VetoCouncil(address(1), address(0), startingAgents);
    }

    function test_setUp_zeroAddressShouldFailInConstructor_members() public {
        address[] memory startingAgents = new address[](3);
        for (uint256 i; i < startingAgents.length; ++i) {
            vm.expectRevert(IVetoCouncil.ZeroAddressInConstructor.selector);
            vetoCouncil = new VetoCouncil(address(1), address(2), startingAgents);
            startingAgents[i] = address(uint160(i + 30));
        }
    }

    function test_addAndRemoveCouncilMembers_notGovernance_shouldRevert() public {
        vm.expectRevert(IVetoCouncil.CallerNotGovernance.selector);
        vetoCouncil.addAndRemoveCouncilMember(address(1), address(2), false);
    }

    function test_addAndRemoveCouncilMembers_shouldWork() public {
        vm.startPrank(GOVERNANCE);
        vetoCouncil.addAndRemoveCouncilMember(address(1), address(2), false);
    }

    function test_addAndRemoveCouncilMembers_matchingAddresses_shouldReturnFalse() public {
        vm.startPrank(GOVERNANCE);
        assertFalse(vetoCouncil.addAndRemoveCouncilMember(address(1), address(1), false));
    }

    function test_addAndRemoveCouncilMembers_oldAgentAMember_shouldReturnFalse() public {
        vm.startPrank(GOVERNANCE);
        vetoCouncil.addAndRemoveCouncilMember(address(1), address(2), false);
        assertFalse(vetoCouncil.addAndRemoveCouncilMember(address(1), address(2), false));
    }

    function test_addAndRemoveCouncilMembers_agentAlreadyMember_shouldReturnFalse() public {
        vm.startPrank(GOVERNANCE);
        assertFalse(vetoCouncil.addAndRemoveCouncilMember(address(1), SIMON, false));
    }

    function test_addAndRemoveCouncilMembers_greaterThan7_addingAgent_shouldReturnFalse() public {
        //Recreate veto council contract with 7 members
        address[] memory startingAgents = new address[](7);
        for (uint256 i; i < startingAgents.length; ++i) {
            startingAgents[i] = address(uint160(i + 30));
        }
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw), startingAgents);
        vm.startPrank(GOVERNANCE);
        //should return false since we are adding an 8th member and the max is 7
        assert(vetoCouncil.addAndRemoveCouncilMember(address(0), address(2), false) == false);
        vm.stopPrank();
    }

    function test_initialize() public {
        assert(vetoCouncil.numberOfCouncilMembers() == 3);
        assert(vetoCouncil.isCouncilMember(SIMON));
        assert(vetoCouncil.isCouncilMember(OTHER_1));
        assert(vetoCouncil.isCouncilMember(OTHER_2));
        assert(_containsElement(vetoCouncil.vetoCouncilMembers(), SIMON));
        assert(_containsElement(vetoCouncil.vetoCouncilMembers(), OTHER_1));
        assert(_containsElement(vetoCouncil.vetoCouncilMembers(), OTHER_2));
        uint256 shiftOneStartTimesatmp = vetoCouncil.paymentNonceToShiftStartTimestamp(1);
        // //All other addresss should be the null address
        assert(vetoCouncil.vetoCouncilMembers().length == 3);
        //We create the protocol at timestamp = 1 in the `setUp` function
        assert(shiftOneStartTimesatmp == 1);
        //Shift two should not be setup.
        uint256 shiftTwoTimestamp = vetoCouncil.paymentNonceToShiftStartTimestamp(2);
        assert(shiftTwoTimestamp == 0);
    }

    function test_addAndRemoveCouncilMembers_slashing_shouldDeletePayout() public {
        vm.warp(block.timestamp + 365 days);
        address[] memory agents = vetoCouncil.vetoCouncilMembers();

        vm.startPrank(SIMON);
        (uint256 a, uint256 b) = vetoCouncil.payoutData(SIMON, 1, agents);
        assertTrue(a > 0);
        assertTrue(b > 0);

        // vetoCouncil.claimPayout({agent: SIMON, nonce: 1, sync: true, agents: agents});

        (uint256 withdrawableAmount, uint256 slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        assertTrue(withdrawableAmount > 0);
        assertEq(slashableAmount, b);
        vm.stopPrank();
        vm.startPrank(GOVERNANCE);
        uint256 timestamp = block.timestamp;
        vetoCouncil.addAndRemoveCouncilMember(SIMON, address(1), true);
        bool isCouncilMember = vetoCouncil.isCouncilMember(SIMON);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        assertTrue(withdrawableAmount == 0);
        assertTrue(slashableAmount == 0);
        assertTrue(isCouncilMember == false);
        assert(vetoCouncil.paymentNonceToShiftStartTimestamp(2) == timestamp);
        vm.stopPrank();
    }

    function test_addAndRemoveCouncilMembers_notSlashing_shouldKeepPayout() public {
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(SIMON);
        address[] memory agents = vetoCouncil.vetoCouncilMembers();
        (uint256 a, uint256 b) = vetoCouncil.payoutData(SIMON, 1, agents);
        assertTrue(a > 0);
        assertTrue(b > 0);

        (uint256 withdrawableAmount, uint256 slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        assertTrue(withdrawableAmount > 0);
        assertEq(slashableAmount, b);
        vm.stopPrank();

        vm.startPrank(GOVERNANCE);
        uint256 timestamp = block.timestamp;
        vetoCouncil.addAndRemoveCouncilMember(SIMON, address(1), false);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        assertTrue(withdrawableAmount > 0);
        assertEq(slashableAmount, b);
        assertFalse(vetoCouncil.isCouncilMember(SIMON));

        vm.stopPrank();
    }

    function test_fullBalanceShouldVest() public {
        uint256 startingAgentsLength = 3;
        //Warp one day
        vm.warp(block.timestamp + 1 weeks);
        address[] memory agents = vetoCouncil.vetoCouncilMembers();
        (uint256 withdrawableAmount, uint256 slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        uint256 totalBalance = withdrawableAmount + slashableAmount;

        //remove but dont slash
        vm.startPrank(GOVERNANCE);
        vetoCouncil.addAndRemoveCouncilMember(SIMON, address(1), false);
        vm.stopPrank();

        //Fast forward 99 weeks
        vm.warp(block.timestamp + 99 weeks);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        totalBalance = withdrawableAmount + slashableAmount;

        //warp 1 week
        vm.warp(block.timestamp + 1 weeks);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        totalBalance = withdrawableAmount + slashableAmount;
        //after 100 weeks, there should be 0 slashable amount
        assertEq(slashableAmount, 0);
        //Since we have never claimed;
        assert(withdrawableAmount == totalBalance);

        vm.startPrank(SIMON);
        vetoCouncil.claimPayout({member: SIMON, nonce: 1, sync: true, members: agents});
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(SIMON, 1, agents);
        // PayoutHelper memory payoutHelper = vetoCouncil.payoutHelper(SIMON, 1);
        // assert(payoutHelper.amountAlreadyWithdrawn == totalBalance);
        assert(withdrawableAmount == 0);
        vm.stopPrank();
    }

    function test_rewardsPerSecondShouldChange_whenDecreasingNumberOfAgents() public {
        uint256 startingAgentsLength = 3;
        //Warp one day
        vm.warp(block.timestamp + 1 weeks);
        address[] memory agents = vetoCouncil.vetoCouncilMembers();
        (uint256 withdrawableAmount, uint256 slashableAmount) = vetoCouncil.payoutData(OTHER_1, 1, agents);
        uint256 totalBalance = withdrawableAmount + slashableAmount;

        //remove but dont slash
        vm.startPrank(GOVERNANCE);
        //add 1 and remove 1 so we dont change the rewards per second
        vetoCouncil.addAndRemoveCouncilMember(SIMON, address(0), false);
        assert(vetoCouncil.numberOfCouncilMembers() == 2);
        vm.stopPrank();

        //Fast forward 99 weeks
        vm.warp(block.timestamp + 99 weeks);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(OTHER_1, 1, agents);
        totalBalance = withdrawableAmount + slashableAmount;

        //warp 1 week
        vm.warp(block.timestamp + 1 weeks);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(OTHER_1, 1, agents);
        totalBalance = withdrawableAmount + slashableAmount;
        // console.log("withdrawableAmount", withdrawableAmount);
        // console.log("slashableAmount", slashableAmount);
        // console.log("totalBalance", totalBalance);
        //since the # of agents changed,
        //the rate changed and slashable balance should get to zero
        //100 weeks after the change.
        assert(slashableAmount == 0);
        //Since we have never claimed;
    }

    function test_rewardsPerSecondShouldChange_whenIncreasingNumberOfAgents() public {
        uint256 startingAgentsLength = 3;
        //Warp one day
        vm.warp(block.timestamp + 1 weeks);
        address[] memory agents = vetoCouncil.vetoCouncilMembers();
        address newRandomAgentToAdd = address(0x22222aaaaaddddd);
        (uint256 withdrawableAmount, uint256 slashableAmount) = vetoCouncil.payoutData(OTHER_1, 1, agents);
        uint256 totalBalance = withdrawableAmount + slashableAmount;

        //remove but dont slash
        vm.startPrank(GOVERNANCE);
        //add 1 and remove 1 so we dont change the rewards per second
        vetoCouncil.addAndRemoveCouncilMember(address(0), newRandomAgentToAdd, false);
        assert(vetoCouncil.numberOfCouncilMembers() == 4);
        vm.stopPrank();

        //Fast forward 99 weeks
        vm.warp(block.timestamp + 99 weeks);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(OTHER_1, 1, agents);
        totalBalance = withdrawableAmount + slashableAmount;

        //warp 1 week
        vm.warp(block.timestamp + 1 weeks);
        (withdrawableAmount, slashableAmount) = vetoCouncil.payoutData(OTHER_1, 1, agents);
        totalBalance = withdrawableAmount + slashableAmount;
        // console.log("withdrawableAmount", withdrawableAmount);
        // console.log("slashableAmount", slashableAmount);
        // console.log("totalBalance", totalBalance);
        //since the # of agents changed,
        //the rate changed and slashable balance should get to zero
        //100 weeks after the change.
        assert(slashableAmount == 0);
        //Since we have never claimed;
    }

    function test_claimPayoutInputArrayDoesNotMatchActualArray_shouldRevert() public {
        vm.startPrank(SIMON);
        address[] memory agents = vetoCouncil.vetoCouncilMembers();
        agents[0] = address(0xdeadddadadadadada);
        vm.expectRevert(VetoCouncilSalaryHelper.HashMismatch.selector);
        vetoCouncil.claimPayout({member: SIMON, nonce: 1, sync: true, members: agents});
    }

    function test_claimPayout_recipientNotInArray_shouldRevert() public {
        vm.startPrank(SIMON);
        address[] memory agents = vetoCouncil.vetoCouncilMembers();
        address notInArray = address(0xdeadddadadadadada);
        vm.expectRevert(VetoCouncilSalaryHelper.MemberNotFound.selector);
        vetoCouncil.claimPayout({member: notInArray, nonce: 1, sync: true, members: agents});
    }

    // function test_claimPayout_futureNonce_shouldRevert() public {
    //     vm.startPrank(address(0));
    //     address[] memory agents = vetoCouncil.vetoCouncilMembers();
    //     // vm.expectRevert(VetoCouncilSalaryHelper.ShiftHasNotStarted.selector);
    //     vetoCouncil.claimPayout({agent: address(0), nonce: 2, sync: true, agents: new address[](0)});
    // }

    // //-------------------  HELPERS  -----------------------------
    function _containsElement(address[] memory array, address element) internal pure returns (bool) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }

    // //-------------------  HELPERS  -----------------------------
    function _containsElement(address[7] memory array, address element) internal pure returns (bool) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }
}
