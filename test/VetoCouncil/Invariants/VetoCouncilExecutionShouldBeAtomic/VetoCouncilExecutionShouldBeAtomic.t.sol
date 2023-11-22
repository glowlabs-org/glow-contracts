// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import {IGrantsTreasury} from "@/interfaces/IGrantsTreasury.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {IVetoCouncil} from "@/interfaces/IVetoCouncil.sol";
import {VetoCouncilSalaryHelper, Status} from "@/generic/VetoCouncilSalaryHelper.sol";
import {NULL_ADDRESS} from "@/generic/VetoCouncilSalaryHelper.sol";
import {Handler} from "./Handler.t.sol";

contract VetoCouncilExecutionShouldBeAtomic is Test {
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
    Handler public handler;

    function setUp() public {
        //make sure block.timestamp does not start at 0
        vm.warp(1);
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

        handler = new Handler(vetoCouncil, GOVERNANCE);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.addAndRemoveCouncilMember.selector;
        selectors[1] = Handler.addAndRemoveCouncilMemberOldAgentAlwaysZeroAddress.selector;
        selectors[2] = Handler.addAndRemoveCouncilMemberNewAgentAlwaysZeroAddress.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetSelector(fs);
        targetContract(address(handler));
    }

    /**
     * forge-config: default.invariant.runs = 10
     * forge-config: default.invariant.depth = 1000
     * forge-config: default.fail-on-revert = true
     */
    function invariant_numberOfCouncilMembersInStorage_shouldEqualLengthOfVetoCouncilMembersArray() public {
        uint256 numberOfCouncilMembersInStorage = vetoCouncil.numberOfCouncilMembers();
        uint256 lengthOfVetoCouncilMembersArray = vetoCouncil.vetoCouncilMembers().length;
        assertTrue(numberOfCouncilMembersInStorage == lengthOfVetoCouncilMembersArray);
    }
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
