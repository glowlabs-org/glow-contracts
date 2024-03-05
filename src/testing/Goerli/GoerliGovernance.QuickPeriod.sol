// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Governance} from "@/Governance.sol";
import {QUICK_BUCKET_DURATION} from "@/testing/Goerli/Constants.QuickPeriod.sol";

contract GoerliGovernanceQuickPeriod is Governance {
    /**
     * @param gcc - the GCC contract
     * @param gca - the GCA contract
     * @param vetoCouncil - the Veto Council contract
     * @param grantsTreasury - the Grants Treasury contract
     * @param glw - the GLW contract
     */
    constructor(address gcc, address gca, address vetoCouncil, address grantsTreasury, address glw)
        payable
        Governance(gcc, gca, vetoCouncil, grantsTreasury, glw)
    {}

    function bucketDuration() internal pure override returns (uint256) {
        return QUICK_BUCKET_DURATION;
    }
}
