// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IEarlyLiquidity} from "@/interfaces/IEarlyLiquidity.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {NULL_ADDRESS} from "@/generic/VetoCouncilSalaryHelper.sol";

contract Handler is Test {
    VetoCouncil public vetoCouncil;
    address governance;

    constructor(VetoCouncil _council, address _governance) public {
        vetoCouncil = _council;
        governance = _governance;
    }

    function addAndRemoveCouncilMember(uint256 oldAgentIndex, address newAgent, bool slashOldAgent) public {
        address[] memory councilMembers = vetoCouncil.vetoCouncilMembers();
        if (newAgent == NULL_ADDRESS) {
            newAgent = address(0x1);
        }
        address oldAgent;
        if (oldAgentIndex == 0) {
            oldAgent = councilMembers[0];
        } else {
            oldAgent = councilMembers[oldAgentIndex % councilMembers.length];
        }

        vm.startPrank(governance);
        vetoCouncil.addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent);
        vm.stopPrank();
    }

    function addAndRemoveCouncilMemberOldAgentAlwaysZeroAddress(address newAgent, bool slashOldAgent) public {
        if (newAgent == NULL_ADDRESS) {
            newAgent = address(0x1);
        }
        address oldAgent = address(0);
        //Old agent and new agent cannot both be zero address
        if (newAgent == address(0)) return;
        vm.startPrank(governance);
        vetoCouncil.addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent);
        vm.stopPrank();
    }

    function addAndRemoveCouncilMemberNewAgentAlwaysZeroAddress(uint256 oldAgentIndex, bool slashOldAgent) public {
        address[] memory councilMembers = vetoCouncil.vetoCouncilMembers();
        address oldAgent;
        //Old agent and new agent cannot both be zero address
        if (oldAgentIndex == 0) {
            return;
        } else {
            oldAgent = councilMembers[oldAgentIndex % councilMembers.length];
        }
        address newAgent = address(0);
        vm.startPrank(governance);
        vetoCouncil.addAndRemoveCouncilMember(oldAgent, newAgent, slashOldAgent);
        vm.stopPrank();
    }
}
