// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGCC is IERC20 {
    error CallerNotGCAContract();
    error BucketAlreadyMinted();

    /**
        * @notice allows gca contract to mint GCC to the carbon credit auction
        * @dev must callback to the carbon credit auction contract so it can organize itself
        * @dev a bucket can only be minted from once
        * @param bucketId the id of the bucket to mint from
        * @param amount the amount of GCC to mint
    */
    function mintToCarbonCreditAuction(uint bucketId,uint amount) external;

    /**
        * @notice returns a boolean indicating if the bucket has been minted
        * @return if the bucket has been minted
    */
    function isBucketMinted(uint bucketId) external view returns (bool);

}