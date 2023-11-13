// SPDX-License-Identifier: MIT
import {Glow} from "../../src/GLOW.sol";
import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";

contract Handler is Test {
    Glow public glow;
    bool boundVars = true;
    uint256 FIVE_YEARS = 5 * 365 days;

    constructor(address _glow) public {
        glow = Glow(_glow);
        deal(address(this), 1e18 ether);
    }

    function stake(uint256 amount) public {
        if (boundVars) {
            amount = bound(amount, 0, glow.balanceOf(address(this)));
        }
        //log sender
        // console.log("SENDER = " , msg.sender);
        glow.stake(amount);
    }

    function unstake(uint256 amount) public {
        if (boundVars) {
            amount = bound(amount, 0, glow.numStaked(address(this)));
        }
        console.log("SENDER = ", msg.sender);

        glow.unstake(amount);
    }

    function claimUnstakedTokens(uint256 amount) public {
        if (boundVars) {
            amount = bound(amount, 0, getUnstakedBalance());
        }
        if (amount == 0) return;
        vm.warp(block.timestamp + FIVE_YEARS);
        glow.claimUnstakedTokens(amount);
    }

    function getUnstakedBalance() public view returns (uint256) {
        IGlow.UnstakedPosition[] memory unstakedPositions = glow.unstakedPositionsOf(address(this));
        uint256 counter;
        // its ok if this overflows because that means
        // we are still within our bounds for unstaked balance
        unchecked {
            for (uint256 i; i < unstakedPositions.length; i++) {
                counter += unstakedPositions[i].amount;
            }
        }
        return counter;
    }
}
