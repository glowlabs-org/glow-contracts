// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@glow/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {QUICK_BUCKET_DURATION} from "@glow/testing/Goerli/Constants.QuickPeriod.sol";

contract GoerliMinerPoolAndGCAQuickPeriod is MinerPoolAndGCA {
    constructor(
        address[] memory startingAgents,
        address glowAddress,
        address governance,
        bytes32 gcaRequirementsHash,
        address earlyLiquidity,
        address usdcToken,
        address vetoCouncilContract,
        address holdingContract,
        address gcc
    )
        MinerPoolAndGCA(
            startingAgents,
            glowAddress,
            governance,
            gcaRequirementsHash,
            earlyLiquidity,
            usdcToken,
            vetoCouncilContract,
            holdingContract,
            gcc
        )
    {}

    function bucketDuration() internal pure override(MinerPoolAndGCA) returns (uint256) {
        return QUICK_BUCKET_DURATION;
    }
}
