// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGCC} from "./interfaces/IGCC.sol";
import {ICarbonCredit} from "./interfaces/ICarbonCredit.sol";

contract GCC is ERC20, IGCC {

    /// @notice The address of the CarbonCreditAuction contract
    ICarbonCredit public immutable CARBON_CREDIT_AUCTION;

    /// @notice The address of the GCAAndMinerPool contract
    address public immutable GCA_AND_MINER_POOL_CONTRACT;

    uint256 private constant _MAX_SHIFT = 255;

    mapping(uint => uint) private _mintedBucketsBitmap;

    //-------------  CONSTRUCTOR --------------------//
    /**
     * @notice GCC constructor
     * @param _carbonCreditAuction The address of the CarbonCreditAuction contract
     * @param _gcaAndMinerPoolContract The address of the GCAAndMinerPool contract
     */
    constructor(
        address _carbonCreditAuction,
        address _gcaAndMinerPoolContract
        )
         ERC20("Glow Carbon Credit", "GCC") {
        CARBON_CREDIT_AUCTION = ICarbonCredit(_carbonCreditAuction);
        GCA_AND_MINER_POOL_CONTRACT = _gcaAndMinerPoolContract;
    }

    /**
        * @inheritdoc IGCC
    */
    function mintToCarbonCreditAuction(uint bucketId,uint amount) external {
        if(msg.sender != GCA_AND_MINER_POOL_CONTRACT) _revert(IGCC.CallerNotGCAContract.selector);
        _setBucketMinted(bucketId);
        CARBON_CREDIT_AUCTION.receiveGCC(amount);
        _mint(address(CARBON_CREDIT_AUCTION), amount);
    }


    /**
        * @inheritdoc IGCC
    */
    function isBucketMinted(uint bucketId) external view returns (bool) {
        (uint key, uint shift) = _getKeyAndShiftFromBucketId(bucketId);
        return _mintedBucketsBitmap[key] & (1 << shift) != 0;
    }

    /**
        * @notice sets the bucket as minted
        * @param bucketId the id of the bucket to set as minted
        * @dev reverts if the bucket has already been minted
    */
    function _setBucketMinted(uint bucketId) private {
        (uint key, uint shift) = _getKeyAndShiftFromBucketId(bucketId);
        uint bitmap = _mintedBucketsBitmap[key];
        if(bitmap & (1 << shift) != 0) _revert(IGCC.BucketAlreadyMinted.selector);
        _mintedBucketsBitmap[key] = bitmap | (1 << shift);
    }


    //-------------  PRIVATE UTILS  --------------------//
    /**
        * @notice Returns the key and shift for a bucketId
        * @return key The key for the bucketId
        * @return shift The shift for the bucketId
    */
    function _getKeyAndShiftFromBucketId(uint bucketId) private pure returns (uint key, uint shift) {
        key = bucketId / _MAX_SHIFT;
        shift = bucketId % _MAX_SHIFT;
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
     function _revert(bytes4 selector) private pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }


}