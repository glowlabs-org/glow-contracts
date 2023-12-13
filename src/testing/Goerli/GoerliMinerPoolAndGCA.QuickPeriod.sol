// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {QUICK_BUCKET_DURATION} from "@/testing/Goerli/Constants.QuickPeriod.sol";

contract GoerliMinerPoolAndGCAQuickPeriod is MinerPoolAndGCA {
    constructor(
        address[] memory startingAgents,
        address glowAddress,
        address governance,
        bytes32 gcaRequirementsHash,
        address earlyLiquidity,
        address usdcToken,
        address vetoCouncilContract,
        address holdingContract
    )
        MinerPoolAndGCA(
            startingAgents,
            glowAddress,
            governance,
            gcaRequirementsHash,
            earlyLiquidity,
            usdcToken,
            vetoCouncilContract,
            holdingContract
        )
    {}

    function bucketDuration() internal pure override(MinerPoolAndGCA) returns (uint256) {
        return QUICK_BUCKET_DURATION;
    }
}
