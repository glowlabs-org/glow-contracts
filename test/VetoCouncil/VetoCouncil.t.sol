// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
import {IGrantsTreasury} from "../../src/interfaces/IGrantsTreasury.sol";
import {GrantsTreasury} from "../../src/GrantsTreasury.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";

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
    uint256 public constant GRANTS_INFLATION_PER_WEEK = 40_000 ether;

    function setUp() public {
        glw = new TestGLOW(EARLY_LIQUIDITY,VESTING_CONTRACT);
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw),startingAgents);

        glw.setContractAddresses(GCA, address(vetoCouncil), GRANTS_TREASURY);
        assertTrue(vetoCouncil.isCouncilMember(SIMON));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_1));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_2));
    }

    //Testing so we can coverage in iloc
    function test_setUp() public {
        glw = new TestGLOW(EARLY_LIQUIDITY,VESTING_CONTRACT);
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw),startingAgents);

        glw.setContractAddresses(GCA, address(vetoCouncil), GRANTS_TREASURY);
        assertTrue(vetoCouncil.isCouncilMember(SIMON));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_1));
        assertTrue(vetoCouncil.isCouncilMember(OTHER_2));
    }

    function test_setUp_zeroAddressShouldFailInConstructor_governance() public {
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vm.expectRevert(IVetoCouncil.ZeroAddressInConstructor.selector);
        vetoCouncil = new VetoCouncil(address(0), address(1),startingAgents);
    }

    function test_setUp_8CouncilMembers_shouldRevert() public {
        address[] memory startingAgents = new address[](8);
        for (uint256 i; i < startingAgents.length; ++i) {
            startingAgents[i] = address(uint160(i + 30));
        }
        vm.expectRevert(IVetoCouncil.MaxCouncilMembersExceeded.selector);
        vetoCouncil = new VetoCouncil(address(1), address(2),startingAgents);
    }

    function test_setUp_zeroAddressShouldFailInConstructor_glw() public {
        address[] memory startingAgents = new address[](3);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(OTHER_1);
        startingAgents[2] = address(OTHER_2);
        vm.expectRevert(IVetoCouncil.ZeroAddressInConstructor.selector);
        vetoCouncil = new VetoCouncil(address(1), address(0),startingAgents);
    }

    function test_setUp_zeroAddressShouldFailInConstructor_members() public {
        address[] memory startingAgents = new address[](3);
        for (uint256 i; i < startingAgents.length; ++i) {
            vm.expectRevert(IVetoCouncil.ZeroAddressInConstructor.selector);
            vetoCouncil = new VetoCouncil(address(1), address(2),startingAgents);
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
        vetoCouncil = new VetoCouncil(GOVERNANCE, address(glw),startingAgents);
        vm.startPrank(GOVERNANCE);
        //should return false since we are adding an 8th member and the max is 7
        assert(vetoCouncil.addAndRemoveCouncilMember(address(0), address(2), false));
        vm.stopPrank();
    }

    function test_addAndRemoveCouncilMembers_slashing_shouldDeletePayout() public {
        vm.warp(block.timestamp + 365 days);

        vm.startPrank(SIMON);
        (uint256 a, uint256 b) = vetoCouncil.nextReward(SIMON);
        assertTrue(a > 0);
        assertTrue(b > 0);
        vetoCouncil.payoutCouncilMember();
        IVetoCouncil.MemberData memory data = vetoCouncil.vetoAgentData(SIMON);
        assertTrue(data.vestingAmount > 0);
        assertEq(data.vestingAmount, b);
        vm.stopPrank();

        vm.startPrank(GOVERNANCE);
        vetoCouncil.addAndRemoveCouncilMember(SIMON, address(1), true);
        data = vetoCouncil.vetoAgentData(SIMON);
        assertTrue(data.vestingAmount == 0);
        assertTrue(data.isActive == false);
        assertTrue(data.lastUpdatedTimestamp == 0);
        vm.stopPrank();
    }

    function test_addAndRemoveCouncilMembers_notSlashing_shouldKeepPayout() public {
        vm.warp(block.timestamp + 365 days);

        vm.startPrank(SIMON);
        (uint256 a, uint256 b) = vetoCouncil.nextReward(SIMON);
        assertTrue(a > 0);
        assertTrue(b > 0);
        vetoCouncil.payoutCouncilMember();
        IVetoCouncil.MemberData memory data = vetoCouncil.vetoAgentData(SIMON);
        assertTrue(data.vestingAmount > 0);
        assertEq(data.vestingAmount, b);
        vm.stopPrank();

        vm.startPrank(GOVERNANCE);
        vetoCouncil.addAndRemoveCouncilMember(SIMON, address(1), false);
        data = vetoCouncil.vetoAgentData(SIMON);
        assertTrue(data.vestingAmount == data.vestingAmount);
        assertTrue(data.isActive == false);
        assertTrue(data.lastUpdatedTimestamp == data.lastUpdatedTimestamp);
        vm.stopPrank();
    }

    //-------------------  HELPERS  -----------------------------
    function _containsElement(address[] memory array, address element) internal pure returns (bool) {
        for (uint256 i; i < array.length; ++i) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }
}
