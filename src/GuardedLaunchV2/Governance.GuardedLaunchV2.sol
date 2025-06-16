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
     * @param migrationContract - the migration contract that will call the contract to migrate nominations
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
        lastExecutedWeek = currentWeek() - 1;
    }

    /**
     * @notice Migrates a users nominations from V1 to V2
     * @param to - the address to migrate the nominations to
     * @param amount - the amount of nominations to migrate
     */
    function migrateNominations(address to, uint256 amount) external {
        if (msg.sender != MIGRATION_CONTRACT) {
            revert NotMigrationContract();
        }
        _grantNominations(to, amount);
    }
}
