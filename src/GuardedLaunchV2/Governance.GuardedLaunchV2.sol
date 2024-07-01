// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Governance} from "@/Governance.sol";

contract GovernanceGuardedLaunchV2 is Governance {
    error NotMigrationContract();

    address public immutable MIGRATION_CONTRACT;
    /**
     * @param gcc - the GCC contract
     * @param gca - the GCA contract
     * @param vetoCouncil - the Veto Council contract
     * @param grantsTreasury - the Grants Treasury contract
     * @param glw - the GLW contract
     */

    constructor(
        address gcc,
        address gca,
        address vetoCouncil,
        address grantsTreasury,
        address glw,
        address migrationContract
    ) payable Governance(gcc, gca, vetoCouncil, grantsTreasury, glw) {
        MIGRATION_CONTRACT = migrationContract;
    }

    function migrateNominations(address to, uint256 amount) external {
        if (msg.sender != MIGRATION_CONTRACT) {
            revert NotMigrationContract();
        }
        _grantNominations(to, amount);
    }
}
