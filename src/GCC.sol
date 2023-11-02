// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGCC} from "@/interfaces/IGCC.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {Swapper} from "@/Swapper.sol";
import {IERC20Permit} from "@/interfaces/IERC20Permit.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
import {IUnifapV2Factory} from "@unifapv2/interfaces/IUnifapV2Factory.sol";
/**
 * @title GCC (Glow Carbon Credit)
 * @author DavidVorick
 * @author 0xSimon
 * @notice This contract is the ERC20 token for Glow Carbon Credits (GCC).
 *         - 1e18 GCC represents 1 metric ton of CO2 offsets
 *         - GCC is minted by the Glow protocol as farms produce clean solar
 *         - GCC can be retired for nominations and karma
 *         - Once GCC is retired, it can't be unretired
 *         - GCC is sold in the carbon credit auction
 *          - The amount of nominations earned is equal to two times the USDC earned from a swap in the retireGCC event as called in the `Swapper`
 *              - When retiring USDC, the amount of nominations earned is equal to the amount of USDC retired
 */

contract GCC is ERC20, IGCC, EIP712 {
    /// @notice The address of the CarbonCreditAuction contract
    ICarbonCreditAuction public immutable CARBON_CREDIT_AUCTION;

    /// @notice The address of the GCAAndMinerPool contract
    address public immutable GCA_AND_MINER_POOL_CONTRACT;

    /// @notice the address of the governance contract
    IGovernance public immutable GOVERNANCE;

    address public immutable GLOW;

    Swapper public immutable SWAPPER;
    /// @notice The maximum shift for a bucketId
    uint256 private constant _BITS_IN_UINT = 256;

    IUniswapRouterV2 public immutable UNISWAP_ROUTER = IUniswapRouterV2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public immutable USDC;

    /// @notice The EIP712 typehash for the RetiringPermit struct used by the permit
    bytes32 public constant RETIRING_PERMIT_TYPEHASH = keccak256(
        "RetiringPermit(address owner,address spender,address rewardAddress,address referralAddress,uint256 amount,uint256 nonce,uint256 deadline)"
    );

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

    //************************************************************* */
    //*********************  CONSTRUCTOR    ********************** */
    //************************************************************* */

    /**
     * @notice GCC constructor
     * @param _gcaAndMinerPoolContract The address of the GCAAndMinerPool contract
     * @param _governance The address of the governance contract
     */
    constructor(
        address _gcaAndMinerPoolContract,
        address _governance,
        address _glowToken,
        address _usdc,
        address _uniswapRouter
    ) payable ERC20("Glow Carbon Credit", "GCC") EIP712("Glow Carbon Credit", "1") {
        USDC = _usdc;
        UNISWAP_ROUTER = IUniswapRouterV2(_uniswapRouter);
        // CARBON_CREDIT_AUCTION = ICarbonCreditAuction(_carbonCreditAuction);
        GCA_AND_MINER_POOL_CONTRACT = _gcaAndMinerPoolContract;
        GOVERNANCE = IGovernance(_governance);
        GLOW = _glowToken;
        CarbonCreditDutchAuction cccAuction =
            new CarbonCreditDutchAuction(IERC20(_glowToken), IERC20(address(this)), 1e6);
        CARBON_CREDIT_AUCTION = ICarbonCreditAuction(address(cccAuction));
        address factory = UNISWAP_ROUTER.factory();
        address pair = getPair(factory, _usdc);
        SWAPPER = new Swapper(_usdc,_uniswapRouter,factory,pair);
    }

    //************************************************************* */
    //*************  EXTERNAL STATE CHANGING FUNCS    ************ */
    //************************************************************* */

    //-----------------  MINTING -----------------//

    /**
     * @inheritdoc IGCC
     */
    function mintToCarbonCreditAuction(uint256 bucketId, uint256 amount) external {
        if (_msgSender() != GCA_AND_MINER_POOL_CONTRACT) _revert(IGCC.CallerNotGCAContract.selector);
        _setBucketMinted(bucketId);
        CARBON_CREDIT_AUCTION.receiveGCC(amount);
        _mint(address(CARBON_CREDIT_AUCTION), amount);
    }

    //-----------------  RETIRING -----------------//

    /**
     * @inheritdoc IGCC
     */
    function retireGCC(uint256 amount, address rewardAddress, address referralAddress) public {
        _transfer(_msgSender(), address(SWAPPER), amount);
        uint256 usdcEffect = SWAPPER.retireGCC(amount);
        _handleRetirement(_msgSender(), rewardAddress, amount, usdcEffect, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function retireUSDC(uint256 amount, address rewardAddress, address referralAddress) public {
        uint256 swapperBalBefore = IERC20(USDC).balanceOf(address(SWAPPER));
        IERC20(USDC).transferFrom(msg.sender, address(SWAPPER), amount);
        uint256 swapperBalAfter = IERC20(USDC).balanceOf(address(SWAPPER));
        uint256 usdcUsing = swapperBalAfter - swapperBalBefore;
        SWAPPER.retireUSDC(usdcUsing);
        _handleUSDCRetirement(_msgSender(), rewardAddress, usdcUsing, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function retireUSDC(uint256 amount, address rewardAddress) external {
        retireUSDC(amount, rewardAddress, address(0));
    }

    /**
     * @inheritdoc IGCC
     */
    function retireUSDCSignature(
        uint256 amount,
        address rewardAddress,
        address referralAddress,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Execute the transfer with a signed authorization
        IERC20Permit paymentToken = IERC20Permit(USDC);
        uint256 allowance = paymentToken.allowance(msg.sender, address(this));
        if (allowance < amount) {
            paymentToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        }
        retireUSDC(amount, rewardAddress, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function retireGCC(uint256 amount, address rewardAddress) external {
        retireGCC(amount, rewardAddress, address(0));
    }

    /**
     * @inheritdoc IGCC
     */
    function retireGCCFor(address from, address rewardAddress, uint256 amount, address referralAddress) public {
        transferFrom(from, address(SWAPPER), amount);
        if (_msgSender() != from) {
            _decreaseRetiringAllowance(from, _msgSender(), amount, false);
        }
        uint256 usdcEffect = SWAPPER.retireGCC(amount);
        _handleRetirement(from, rewardAddress, amount, usdcEffect, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function retireGCCFor(address from, address rewardAddress, uint256 amount) public {
        retireGCCFor(from, rewardAddress, amount, address(0));
    }

    /**
     * @inheritdoc IGCC
     */
    function retireGCCForAuthorized(
        address from,
        address rewardAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature,
        address referralAddress
    ) public {
        if (block.timestamp > deadline) {
            _revert(IGCC.RetiringPermitSignatureExpired.selector);
        }
        bytes32 message = _constructRetiringPermitDigest(
            from, _msgSender(), rewardAddress, referralAddress, amount, nextRetiringNonce[from]++, deadline
        );
        if (!_checkRetiringPermitSignature(from, message, signature)) {
            _revert(IGCC.RetiringSignatureInvalid.selector);
        }
        _increaseRetiringAllowance(from, _msgSender(), amount, false);
        uint256 transferAllowance = allowance(from, _msgSender());
        if (transferAllowance < amount) {
            _approve(from, _msgSender(), amount, false);
        }
        retireGCCFor(from, rewardAddress, amount, referralAddress);
    }

    /// @inheritdoc IGCC
    function retireGCCForAuthorized(
        address from,
        address rewardAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external {
        retireGCCForAuthorized(from, rewardAddress, amount, deadline, signature, address(0));
    }

    //-----------------  ALLOWANCES -----------------//

    /// @inheritdoc IGCC
    function setAllowances(address spender, uint256 transferAllowance, uint256 retiringAllowance) external {
        _approve(_msgSender(), spender, transferAllowance);
        _retireGCCAllowances[_msgSender()][spender] = retiringAllowance;
        emit IGCC.RetireGCCAllowance(_msgSender(), spender, retiringAllowance);
    }

    /// @inheritdoc IGCC
    function increaseAllowances(address spender, uint256 addedValue) public {
        _approve(_msgSender(), spender, allowance(_msgSender(), spender) + addedValue);
        _increaseRetiringAllowance(_msgSender(), spender, addedValue, true);
    }

    /// @inheritdoc IGCC
    function decreaseAllowances(address spender, uint256 requestedDecrease) public {
        uint256 currentAllowance = allowance(_msgSender(), spender);
        if (currentAllowance < requestedDecrease) {
            revert ERC20.ERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
        }
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - requestedDecrease);
        }
        _decreaseRetiringAllowance(_msgSender(), spender, requestedDecrease, true);
    }

    /**
     * @inheritdoc IGCC
     */
    function increaseRetiringAllowance(address spender, uint256 amount) external override {
        _increaseRetiringAllowance(_msgSender(), spender, amount, true);
    }

    /**
     * @inheritdoc IGCC
     */
    function decreaseRetiringAllowance(address spender, uint256 amount) external override {
        _decreaseRetiringAllowance(_msgSender(), spender, amount, true);
    }

    //************************************************************* */
    //******************  EXTERNAL VIEW FUNCS    ***************** */
    //************************************************************* */

    /**
     * @inheritdoc IGCC
     */
    function retiringAllowance(address account, address spender) public view override returns (uint256) {
        return _retireGCCAllowances[account][spender];
    }

    /**
     * @inheritdoc IGCC
     */
    function isBucketMinted(uint256 bucketId) external view returns (bool) {
        (uint256 key, uint256 shift) = _getKeyAndShiftFromBucketId(bucketId);
        return _mintedBucketsBitmap[key] & (1 << shift) != 0;
    }

    /**
     * @notice Returns the domain separator used in the permit signature
     * @dev Should be deterministic
     * @return result The domain separator
     */
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    //************************************************************* */
    //***************  PRIVATE STATE CHANGING FUNCS   ************** */
    //************************************************************* */

    /**
     * @notice sets the bucket as minted
     * @param bucketId the id of the bucket to set as minted
     * @dev reverts if the bucket has already been minted
     */
    function _setBucketMinted(uint256 bucketId) private {
        (uint256 key, uint256 shift) = _getKeyAndShiftFromBucketId(bucketId);
        //Can't overflow because _BITS_IN_UINT is 255
        uint256 bitmap = _mintedBucketsBitmap[key];
        if (bitmap & (1 << shift) != 0) _revert(IGCC.BucketAlreadyMinted.selector);
        _mintedBucketsBitmap[key] = bitmap | (1 << shift);
    }

    /**
     * @notice handles the storage writes and event emissions relating to retiring carbon credits.
     * @dev should only be used internally and by function that require a transfer of {amount} to address(this)
     * @param from the address of the account retiring the credits
     * @param rewardAddress the address to receive the benefits of retiring
     * @param gccRetired the amount of GCC retired
     * @param usdcEffect the effect of retiring on the USDC balance
     * @param referralAddress the address of the referrer (zero for no referrer)
     */
    function _handleRetirement(
        address from,
        address rewardAddress,
        uint256 gccRetired,
        uint256 usdcEffect,
        address referralAddress
    ) private {
        if (from == referralAddress) _revert(IGCC.CannotReferSelf.selector);
        //Retiring GCC is also responsible for syncing proposals in governance.
        GOVERNANCE.syncProposals();
        totalCreditsRetired[rewardAddress] += gccRetired;
        GOVERNANCE.grantNominations(rewardAddress, usdcEffect);
        emit IGCC.GCCRetired(from, rewardAddress, gccRetired, usdcEffect, referralAddress);
    }

    /**
     * @notice handles the storage writes and event emissions relating to retiring USDC
     * @dev should only be used internally and by function that require a transfer of {amount} to address(this)
     * @param from the address of the account retiring the credits
     * @param rewardAddress the address to receive the benefits of retiring
     * @param amount the amount of USDC TO RETIRE
     * @param referralAddress the address of the referrer (zero for no referrer)
     */
    function _handleUSDCRetirement(address from, address rewardAddress, uint256 amount, address referralAddress)
        private
    {
        if (from == referralAddress) _revert(IGCC.CannotReferSelf.selector);
        //Retiring GCC is also responsible for syncing proposals in governance.
        GOVERNANCE.syncProposals();
        totalCreditsRetired[rewardAddress] += amount;
        GOVERNANCE.grantNominations(rewardAddress, amount);
        emit IGCC.USDCRetired(from, rewardAddress, amount, referralAddress);
    }

    /**
     * @dev internal function to increase the retiring allowance
     * @param from the address of the account to increase the allowance from
     * @param spender the address of the spender to increase the allowance for
     * @param amount the amount to increase the allowance by
     * @param emitEvent whether or not to emit the event
     */
    function _increaseRetiringAllowance(address from, address spender, uint256 amount, bool emitEvent) private {
        if (amount == 0) {
            _revert(IGCC.MustIncreaseRetiringAllowanceByAtLeastOne.selector);
        }
        uint256 currentAllowance = _retireGCCAllowances[from][spender];
        uint256 newAllowance;
        unchecked {
            newAllowance = currentAllowance + amount;
        }
        //If there was an overflow, then we set the new allowance to type(uint).max
        if (newAllowance <= currentAllowance) {
            newAllowance = type(uint256).max;
        }
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
     * @dev cant overflow because _BITS_IN_UINT is 255
     * @dev no division by zero because _BITS_IN_UINT is 255
     */
    function _getKeyAndShiftFromBucketId(uint256 bucketId) private pure returns (uint256 key, uint256 shift) {
        key = bucketId / _BITS_IN_UINT;
        shift = bucketId % _BITS_IN_UINT;
    }

    /**
     * @dev Constructs a retiring permit EIP712 message hash to be signed
     * @param owner The owner of the funds
     * @param spender The spender
     * @param rewardAddress - the address to receive the benefits of retiring
     * @param referralAddress - the address of the referrer
     * @param amount The amount of funds
     * @param nonce The next nonce
     * @param deadline The deadline for the signature to be valid
     * @return digest The EIP712 digest
     */
    function _constructRetiringPermitDigest(
        address owner,
        address spender,
        address rewardAddress,
        address referralAddress,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) private view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    RETIRING_PERMIT_TYPEHASH, owner, spender, rewardAddress, referralAddress, amount, nonce, deadline
                )
            )
        );
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

    function getPair(address factory, address _usdc) internal view virtual returns (address) {
        return UniswapV2Library.pairFor(factory, _usdc, address(this));
    }
    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */

    function _revert(bytes4 selector) private pure {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}
