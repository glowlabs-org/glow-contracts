// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGCCV2 is IERC20 {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                  */
    /* -------------------------------------------------------------------------- */
    error CallerNotGCAContract();
    error BucketAlreadyMinted();
    error CommitPermitSignatureExpired();
    error CommitSignatureInvalid();
    error CommitAllowanceUnderflow();
    error MustIncreaseCommitAllowanceByAtLeastOne();
    error CannotReferSelf();
    /* -------------------------------------------------------------------------- */
    /*                                   structs                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @param lastUpdatedTimestamp - the last timestamp a user earned or used nominations
     * @ param amount - the amount of nominations a user has
     */
    struct Nominations {
        uint64 lastUpdatedTimestamp;
        uint192 amount;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   events                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice is emitted when a user commits credits
     * @param account the account that committed credits
     * @param rewardAddress the address that earned the credits and nominations
     * @param gccAmount the amount of credits committed
     * @param usdcEffect the amount of USDC effect
     * @param impactPower - sqrt(amount gcc used in lp * amountc usdc used in lp) aka nominations granted
     * @param referralAddress the address that referred the account
     *             - zero address if no referral
     */
    event GCCCommitted(
        address indexed account,
        address indexed rewardAddress,
        uint256 gccAmount,
        uint256 usdcEffect,
        uint256 impactPower,
        address referralAddress
    );

    /**
     * @notice is emitted when a user commits USDC
     * @param account the account that commit the USDC
     * @param rewardAddress the address that earns nominations
     * @param amount the amount of USDC commit
     * @param impactPower - sqrt(amount gcc used in lp * amountc usdc used in lp) aka nominations granted
     * @param referralAddress the address that referred the account
     *             - zero address if no referral
     */
    event USDCCommitted(
        address indexed account,
        address indexed rewardAddress,
        uint256 amount,
        uint256 impactPower,
        address referralAddress
    );

    /* -------------------------------------------------------------------------- */
    /*                                   commits                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice allows a user to commit credits
     * @param amount the amount of credits to commit
     * @param rewardAddress the address to commit the credits to
     *     -   Rewards Address earns:
     *     -       1.  Carbon Neutrality
     *     -       2.  Nominations
     * @param minImpactPower - the minimum amount of impact power to receive from the commitment
     * @return usdcEffect the amount of USDC used in the LP position
     * @return impactPower - sqrt(amount gcc used in lp * amountc usdc used in lp) aka nominations granted
     */
    function commitGCC(uint256 amount, address rewardAddress, uint256 minImpactPower)
        external
        returns (uint256 usdcEffect, uint256 impactPower);

    /**
     * @notice allows a user to commit credits
     * @param amount the amount of credits to commit
     * @param rewardAddress the address to commit the credits to
     *     -   Rewards Address earns:
     *     -       1.  Carbon Neutrality
     *     -       2.  Nominations
     * @param referralAddress the address that referred the account
     * @param minImpactPower - the minimum amount of impact power to receive from the commitment
     *
     * @return usdcEffect the amount of USDC used in the LP position
     * @return impactPower - sqrt(amount gcc used in lp * amountc usdc used in lp) aka nominations granted
     */
    function commitGCC(uint256 amount, address rewardAddress, address referralAddress, uint256 minImpactPower)
        external
        returns (uint256 usdcEffect, uint256 impactPower);

    /**
     * @notice Allows a user to commit USDC
     * @param amount the amount of USDC to commit
     * @param rewardAddress the address to commit the USDC to
     * @param referralAddress the address that referred the account
     * @param minImpactPower - the minimum amount of impact power to receive from the commitment
     *
     * @return impactPower - sqrt(amount gcc used in lp * amountc usdc used in lp) aka nominations granted
     */
    function commitUSDC(uint256 amount, address rewardAddress, address referralAddress, uint256 minImpactPower)
        external
        returns (uint256 impactPower);

    /**
     * @notice Allows a user to commit USDC
     * @param amount the amount of USDC to commit
     * @param rewardAddress the address to commit the USDC to
     * @param minImpactPower - the minimum amount of impact power to receive from the commitment
     *
     * @return impactPower - sqrt(amount gcc used in lp * amountc usdc used in lp) aka nominations granted
     */
    function commitUSDC(uint256 amount, address rewardAddress, uint256 minImpactPower)
        external
        returns (uint256 impactPower);

    /* -------------------------------------------------------------------------- */
    /*                                   minting                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice allows gca contract to mint GCC to the carbon credit auction
     * @dev must callback to the carbon credit auction contract so it can organize itself
     * @dev a bucket can only be minted from once
     * @param bucketId the id of the bucket to mint from
     * @param amount the amount of GCC to mint
     */
    function mintToCarbonCreditAuction(uint256 bucketId, uint256 amount) external;

    /* -------------------------------------------------------------------------- */
    /*                                   view functions                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice returns a boolean indicating if the bucket has been minted
     * @return if the bucket has been minted
     */
    function isBucketMinted(uint256 bucketId) external view returns (bool);
}
