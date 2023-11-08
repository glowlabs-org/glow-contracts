// SPDX-License-Identifier: MIT
import {Glow} from "../../src/GLOW.sol";
import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
import "forge-std/Test.sol";

contract SymetricHandler is Test {
    Glow public glow;
    bool boundVars = true;
    uint256 amountToStake = 1 ether;

    constructor(address _glow) public {
        glow = Glow(_glow);
        deal(address(this), 1e18 ether);
    }

    function warp5Years() public {
        vm.warp(block.timestamp + 365 days * 5);
    }

    function stake(uint256 timesToStake) public {
        timesToStake = bound(timesToStake, 1, 10);

        for (uint256 i = 0; i < timesToStake; i++) {
            uint256 amount = amountToStake;
            //log sender
            // console.log("SENDER = " , msg.sender);
            glow.stake(amount);
        }
    }

    function unstake(uint256 timesToUnstake) public {
        timesToUnstake = bound(timesToUnstake, 0, 10);

        for (uint256 i = 0; i < timesToUnstake; i++) {
            uint256 numStaked = glow.numStaked(address(this));
            if (numStaked == 0) break;
            uint256 amount = amountToStake;
            glow.unstake(amount);
        }
    }

    function claimUnstakedTokens() public {
        warp5Years(); //warp 5 years so we can claim everything
        glow.claimUnstakedTokens(amountToStake);
    }

    function getUnstakedBalance() public view returns (uint256) {
        IGlow.UnstakedPosition[] memory unstakedPositions = glow.unstakedPositionsOf(address(this));
        uint256 counter;
        unchecked {
            for (uint256 i; i < unstakedPositions.length; i++) {
                counter += unstakedPositions[i].amount;
            }
        }
        return counter;
    }
}
