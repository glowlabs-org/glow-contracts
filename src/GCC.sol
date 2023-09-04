// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGCC} from "@/interfaces/IGCC.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ABDKMath64x64} from "./libraries/ABDKMath64x64.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import "forge-std/console.sol";
// import {IERC20Errors} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

contract GCC is ERC20, IGCC, EIP712 {
    /// @notice The address of the CarbonCreditAuction contract
    ICarbonCreditAuction public immutable CARBON_CREDIT_AUCTION;

    /// @notice The address of the GCAAndMinerPool contract
    address public immutable GCA_AND_MINER_POOL_CONTRACT;

    /// @notice the address of the governance contract
    IGovernance public immutable GOVERNANCE;

    /// @notice The maximum shift for a bucketId
    uint256 private constant _MAX_SHIFT = 255;

    bytes32 public constant RETIRING_PERMIT_TYPEHASH =
        keccak256("RetiringPermit(address owner,address spender,uint256 amount,uint256 nonce,uint256 deadline)");

    /**
     * @notice The bitmap of minted buckets
     * @dev key 0 contains the first 256 buckets, key 1 contains the next 256 buckets, etc.
     */
    mapping(uint256 => uint256) private _mintedBucketsBitmap;

    /**
     * @notice The total credits retired by a user
     */
    mapping(address => uint256) public totalCreditsRetired;

    /**
     * @notice The allowances for retiring GCC
     * @dev similar to ERC20
     */
    mapping(address => mapping(address => uint256)) private _retireGCCAllowances;

    /**
     * @notice The next retiring nonce for a user
     * @dev similar to ERC20
     */
    mapping(address => uint256) public nextRetiringNonce;

    //-------------  CONSTRUCTOR --------------------//

    /**
     * @notice GCC constructor
     * @param _carbonCreditAuction The address of the CarbonCreditAuction contract
     * @param _gcaAndMinerPoolContract The address of the GCAAndMinerPool contract
     * @param _governance The address of the governance contract
     */
    constructor(address _carbonCreditAuction, address _gcaAndMinerPoolContract, address _governance)
        ERC20("Glow Carbon Credit", "GCC")
        EIP712("Glow Carbon Credit", "1")
    {
        CARBON_CREDIT_AUCTION = ICarbonCreditAuction(_carbonCreditAuction);
        GCA_AND_MINER_POOL_CONTRACT = _gcaAndMinerPoolContract;
        GOVERNANCE = IGovernance(_governance);
    }

    /**
     * @inheritdoc IGCC
     */
    function mintToCarbonCreditAuction(uint256 bucketId, uint256 amount) external {
        if (msg.sender != GCA_AND_MINER_POOL_CONTRACT) _revert(IGCC.CallerNotGCAContract.selector);
        _setBucketMinted(bucketId);
        CARBON_CREDIT_AUCTION.receiveGCC(amount);
        _mint(address(CARBON_CREDIT_AUCTION), amount);
    }

    /**
     * @inheritdoc IGCC
     */
    function isBucketMinted(uint256 bucketId) external view returns (bool) {
        (uint256 key, uint256 shift) = _getKeyAndShiftFromBucketId(bucketId);
        return _mintedBucketsBitmap[key] & (1 << shift) != 0;
    }

    /**
     * @notice sets the bucket as minted
     * @param bucketId the id of the bucket to set as minted
     * @dev reverts if the bucket has already been minted
     */
    function _setBucketMinted(uint256 bucketId) private {
        (uint256 key, uint256 shift) = _getKeyAndShiftFromBucketId(bucketId);
        //Can't overflow because _MAX_SHIFT is 255
        uint256 bitmap = _mintedBucketsBitmap[key];
        if (bitmap & (1 << shift) != 0) _revert(IGCC.BucketAlreadyMinted.selector);
        _mintedBucketsBitmap[key] = bitmap | (1 << shift);
    }

    //-----------------  RETIRING AND NOMINATIONS -----------------//

    /**
     * @inheritdoc IGCC
     */
    function retireGCC(uint256 amount, address rewardAddress) external {
        _transfer(msg.sender, address(this), amount);
        _handleRetirement(msg.sender, rewardAddress, amount);
    }

    function retireGCCFor(address from, address rewardAddress, uint256 amount) public {
        transferFrom(from, address(this), amount);
        if (msg.sender != from) {
            _decreaseRetiringAllowance(from, msg.sender, amount, false);
        }
        _handleRetirement(from, rewardAddress, amount);
    }

    /// @inheritdoc IGCC
    function retireGCCForAuthorized(
        address from,
        address rewardAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) {
            _revert(IGCC.RetiringPermitSignatureExpired.selector);
        }
        bytes32 message = _constructRetiringPermitDigest(from, msg.sender, amount, nextRetiringNonce[from]++, deadline);
        if (!_checkRetiringPermitSignature(from, message, signature)) {
            _revert(IGCC.RetiringSignatureInvalid.selector);
        }
        _increaseRetiringAllowance(from, msg.sender, amount, false);
        uint256 transferAllowance = allowance(from, msg.sender);
        if (transferAllowance < amount) {
            _approve(from, msg.sender, amount, false);
        }
        retireGCCFor(from, rewardAddress, amount);
    }
    

    function increaseAllowances(address spender, uint256 addedValue) public {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        _increaseRetiringAllowance(msg.sender, spender, addedValue, true);
    }

    function decreaseAllowances(address spender, uint256 requestedDecrease) public {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance < requestedDecrease) {
            revert ERC20.ERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
        }
        unchecked {
            _approve(msg.sender, spender, currentAllowance - requestedDecrease);
        }
        _decreaseRetiringAllowance(msg.sender, spender, requestedDecrease, true);
    }

    //-----------------  RETIRING ALLOWANCES -----------------//

    /**
     * @inheritdoc IGCC
     */
    function increaseRetiringAllowance(address spender, uint256 amount) external override {
        _increaseRetiringAllowance(msg.sender, spender, amount, true);
    }

    /**
     * @inheritdoc IGCC
     */
    function decreaseRetiringAllowance(address spender, uint256 amount) external override {
        _decreaseRetiringAllowance(msg.sender, spender, amount, true);
    }

    /**
     * @inheritdoc IGCC
     */
    function retiringAllowance(address account, address spender) public view override returns (uint256) {
        return _retireGCCAllowances[account][spender];
    }

    /**
        * @notice Returns the domain separator used in the permit signature
        * @dev Should be deterministic
        * @return result The domain separator
    */
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    //-----------------  PRIVATE -----------------//

    /// @notice handles the storage writes and event emissions relating to retiring carbon credits.
    /// @dev should only be used internally and by function that require a transfer of {amount} to address(this)
    function _handleRetirement(address from, address rewardAddress, uint256 amount) private {
        totalCreditsRetired[rewardAddress] += amount;
        GOVERNANCE.grantNominations(rewardAddress, amount);
        emit IGCC.GCCRetired(from, rewardAddress, amount);
    }

    /**
     * @dev internal function to increase the retiring allowance
     * @param from the address of the account to increase the allowance from
     * @param spender the address of the spender to increase the allowance for
     * @param amount the amount to increase the allowance by
     * @param emitEvent whether or not to emit the event
     * @dev overflow auto-reverts due to built in safemath
     */
    function _increaseRetiringAllowance(address from, address spender, uint256 amount, bool emitEvent) private {
        uint256 currentAllowance = _retireGCCAllowances[from][spender];
        uint256 newAllowance = currentAllowance + amount;
        _retireGCCAllowances[from][spender] = newAllowance;
        if (emitEvent) {
            emit IGCC.RetireGCCAllowance(from, spender, newAllowance);
        }
    }

    /**
     * @dev internal function to decrease the retiring allowance
     * @param from the address of the account to decrease the allowance from
     * @param spender the address of the spender to decrease the allowance for
     * @param amount the amount to decrease the allowance by
     * @param emitEvent whether or not to emit the event
     * @dev underflow auto-reverts due to built in safemath
     */
    function _decreaseRetiringAllowance(address from, address spender, uint256 amount, bool emitEvent) private {
        uint256 currentAllowance = _retireGCCAllowances[from][spender];

        uint256 newAllowance = currentAllowance - amount;
        _retireGCCAllowances[from][spender] = newAllowance;
        if (emitEvent) {
            emit IGCC.RetireGCCAllowance(from, spender, newAllowance);
        }
    }

    //-------------  PRIVATE UTILS  --------------------//
    /**
     * @notice Returns the key and shift for a bucketId
     * @return key The key for the bucketId
     * @return shift The shift for the bucketId
     * @dev cant overflow because _MAX_SHIFT is 255
     * @dev no division by zero because _MAX_SHIFT is 255
     */
    function _getKeyAndShiftFromBucketId(uint256 bucketId) private pure returns (uint256 key, uint256 shift) {
        key = bucketId / _MAX_SHIFT;
        shift = bucketId % _MAX_SHIFT;
    }

    /**
        * @dev Constructs a retiring permit EIP712 message hash to be signed
        * @param owner The owner of the funds
        * @param spender The spender
        * @param amount The amount of funds
        * @param nonce The next nonce
        * @param deadline The deadline for the signature to be valid
        * @return digest The EIP712 digest
    */
    function _constructRetiringPermitDigest(
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) private view returns (bytes32) {
        return
            _hashTypedDataV4(keccak256(abi.encode(RETIRING_PERMIT_TYPEHASH, owner, spender, amount, nonce, deadline)));
    }

    /**
        * @dev Checks if the signature provided is valid for the provided data, hash.
        * @param signer The address of the signer.
        * @param message The EIP-712 digest.
        * @param signature The signature, in bytes.
        * @return bool indicating if the signature was valid (true) or not (false).
        * @dev accounts for EIP-1271 magic values as well
    */
    function _checkRetiringPermitSignature(address signer, bytes32 message, bytes memory signature)
        private
        view
        returns (bool)
    {
        return SignatureChecker.isValidSignatureNow(signer, message, signature);
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
