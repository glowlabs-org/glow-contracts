// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Governance} from "@/Governance.sol";
import {QUICK_BUCKET_DURATION} from "@/testing/Goerli/Constants.QuickPeriod.sol";

contract GoerliGovernanceQuickPeriod is Governance {
    constructor() Governance() {}

    function bucketDuration() internal pure override returns (uint256) {
        return QUICK_BUCKET_DURATION;
    }
}
