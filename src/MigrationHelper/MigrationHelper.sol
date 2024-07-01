// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {GovernanceGuardedLaunchV2} from "@/GuardedLaunchV2/Governance.GuardedLaunchV2.sol";
import {GCCGuardedLaunchV2} from "@/GuardedLaunchV2/GCC.GuardedLaunchV2.sol";
/**
 * @title MigrationHelper
 * @notice A contract for migrating GLOW, GCC, and USDG tokens using a merkle tree
 */

contract MigrationHelper {
    error AlreadyMigrated();
    error ArrayLengthMismatch();
    error InvalidProof();

    address public immutable GLOW;
    GCCGuardedLaunchV2 public immutable GCC;
    address public immutable USDG;
    GovernanceGuardedLaunchV2 public immutable GOVERNANCE;
    bytes32 public immutable MERKLE_ROOT;

    mapping(address => bool) public migrated;

    event MigrationComplete(
        address indexed account,
        uint256 glowAmount,
        uint256 gccAmount,
        uint256 usdgAmount,
        uint256 nominations,
        uint256 impactPower
    );

    constructor(address _GLOW, address _GCC, address _USDG, address _GOVERNANCE, bytes32 _MERKLE_ROOT) {
        GLOW = _GLOW;
        GCC = GCCGuardedLaunchV2(_GCC);
        GOVERNANCE = GovernanceGuardedLaunchV2(_GOVERNANCE);
        USDG = _USDG;
        MERKLE_ROOT = _MERKLE_ROOT;
    }

    /**
     * @notice Claims for an array of accounts using a merkle multi-proof
     * @param accounts The accounts to claim for
     * @param glowAmounts The amount of GLOW to claim for each account
     * @param gccAmounts The amount of GCC to claim for each account
     * @param usdgAmounts The amount of USDG to claim for each account
     * @param proof The merkle multi proof
     * @param flags The flags for the merkle multi proof
     */
    function claim(
        address[] memory accounts,
        uint256[] memory glowAmounts,
        uint256[] memory gccAmounts,
        uint256[] memory usdgAmounts,
        uint256[] memory nominations,
        uint256[] memory impactPowers,
        bytes32[] calldata proof,
        bool[] calldata flags
    ) external {
        bytes32[] memory leaves = new bytes32[](accounts.length);
        unchecked {
            for (uint256 i; i < accounts.length; ++i) {
                leaves[i] = keccak256(abi.encodePacked(accounts[i], glowAmounts[i], gccAmounts[i], usdgAmounts[i]));
                //Optimistically transfer
                if (migrated[accounts[i]]) {
                    revert AlreadyMigrated();
                }
                migrated[accounts[i]] = true;
                IERC20(GLOW).transfer(accounts[i], glowAmounts[i]);
                IERC20(GCC).transfer(accounts[i], gccAmounts[i]);
                IERC20(USDG).transfer(accounts[i], usdgAmounts[i]);
                GOVERNANCE.migrateNominations(accounts[i], nominations[i]);
                GCC.migrateImpactPower(accounts[i], impactPowers[i]);
                emit MigrationComplete(
                    accounts[i], glowAmounts[i], gccAmounts[i], usdgAmounts[i], nominations[i], impactPowers[i]
                );
            }
        }

        if (!MerkleProofLib.verifyMultiProof(proof, MERKLE_ROOT, leaves, flags)) {
            revert InvalidProof();
        }
    }
}
