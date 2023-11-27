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
import {ImpactCatalyst} from "@/ImpactCatalyst.sol";
import {IERC20Permit} from "@/interfaces/IERC20Permit.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
/**
 * @title GCC (Glow Carbon Credit)
 * @author DavidVorick
 * @author 0xSimon(twitter) - 0xSimbo(github)
 * @notice This contract is the ERC20 token for Glow Carbon Credits (GCC).
 *         - 1 GCC or (1e18 wei of GCC) represents 1 metric ton of CO2 offsets
 *         - GCC is minted by the Glow protocol as farms produce clean solar
 *         - GCC can be committed for nominations and permanent impact power
 *         - Nominations are used to vote on proposals in governance and are in 12 decimals
 *         - Impact power is an on-chain record of the sum of total impact power earned by a user
 *         - It currently has no use, but can be used to integrate with other protocols
 *         - Once GCC is committed, it can't be uncommitted
 *         - GCC is sold in the carbon credit auction
 *          - The amount of nominations earned is equal to the sqrt(amountGCCAddedToUniV2LP * amountUSDCAddedToUniV2LP)
 *              - earned from a swap in the commitGCC or commitUSDC functions in the `impactCatalyst`
 *              - When committing USDC, the amount of nominations earned is equal to the amount of USDC committed
 */

contract GCC is ERC20, ERC20Burnable, IGCC, EIP712 {
    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    /// @notice The EIP712 typehash for the CommitPermit struct used by the permit
    bytes32 public constant COMMIT_PERMIT_TYPEHASH = keccak256(
        "CommitPermit(address owner,address spender,address rewardAddress,address referralAddress,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    /// @notice The maximum shift for a bucketId
    uint256 private constant _BITS_IN_UINT = 256;

    /* -------------------------------------------------------------------------- */
    /*                                  immutables                                */
    /* -------------------------------------------------------------------------- */
    /// @notice The address of the CarbonCreditAuction contract
    ICarbonCreditAuction public immutable CARBON_CREDIT_AUCTION;

    /// @notice The address of the GCAAndMinerPool contract
    address public immutable GCA_AND_MINER_POOL_CONTRACT;

    /// @notice the address of the governance contract
    IGovernance public immutable GOVERNANCE;

    /// @notice the address of the GLOW token
    address public immutable GLOW;

    /// @notice the address of the ImpactCatalyst contract
    /// @dev the impact catalyst is responsible for handling the commitments of GCC and USDC
    ImpactCatalyst public immutable IMPACT_CATALYST;

    /// @notice The Uniswap router
    /// @dev used to swap USDC for GCC and vice versa
    IUniswapRouterV2 public immutable UNISWAP_ROUTER;

    /// @notice The address of the USDC token
    address public immutable USDC;

    /* -------------------------------------------------------------------------- */
    /*                                   mappings                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The bitmap of minted buckets
     * @dev key 0 contains the first 256 buckets, key 1 contains the next 256 buckets, etc.
     */
    mapping(uint256 => uint256) private _mintedBucketsBitmap;

    /**
     * @notice The total impact power earned by a user from their USDC or GCC commitments
     */
    mapping(address => uint256) public totalImpactPowerEarned;

    /**
     * @notice The allowances for committing GCC
     * @dev similar to ERC20
     */
    mapping(address => mapping(address => uint256)) private _commitGCCAllowances;

    /**
     * @notice The next commit nonce for a user
     */
    mapping(address => uint256) public nextCommitNonce;

    /* -------------------------------------------------------------------------- */
    /*                                 constructor                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice GCC constructor
     * @param _gcaAndMinerPoolContract The address of the GCAAndMinerPool contract
     * @param _governance The address of the governance contract
     * @param _glowToken The address of the GLOW token
     * @param _usdc The address of the USDC token
     * @param _uniswapRouter The address of the Uniswap V2 router
     */
    constructor(
        address _gcaAndMinerPoolContract,
        address _governance,
        address _glowToken,
        address _usdc,
        address _uniswapRouter
    ) payable ERC20("Glow Carbon Certificate", "GCC") EIP712("Glow Carbon Certificate", "1") {
        //Set the immutable variables
        USDC = _usdc;
        GCA_AND_MINER_POOL_CONTRACT = _gcaAndMinerPoolContract;
        UNISWAP_ROUTER = IUniswapRouterV2(_uniswapRouter);
        GOVERNANCE = IGovernance(_governance);
        GLOW = _glowToken;
        //Create the carbon credit auction directly in the constructor
        CarbonCreditDutchAuction cccAuction = new CarbonCreditDutchAuction({
                            glow: IERC20(_glowToken),
                            gcc: IERC20(address(this)),
                            startingPrice: 1e5 //Carbon Credit Auction sells increments of 1e6 GCC,
                            //Setting the price to 1e5 per unit means that 1 GCC = .1 GLOW
                        });

        CARBON_CREDIT_AUCTION = ICarbonCreditAuction(address(cccAuction));
        //Create the impact catalyst
        address factory = UNISWAP_ROUTER.factory();
        address pair = getPair(factory, _usdc);
        //Mint 1 to set the LP with USDC
        if (block.chainid == 1) {
            _mint(tx.origin, 1 ether);
        }
        //The impact catalyst is responsible for handling the commitments of GCC and USDC
        IMPACT_CATALYST = new ImpactCatalyst(_usdc,_uniswapRouter,factory,pair);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   minting                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @inheritdoc IGCC
     */
    function mintToCarbonCreditAuction(uint256 bucketId, uint256 amount) external {
        if (_msgSender() != GCA_AND_MINER_POOL_CONTRACT) _revert(IGCC.CallerNotGCAContract.selector);
        _setBucketMinted(bucketId);
        CARBON_CREDIT_AUCTION.receiveGCC(amount);
        _mint(address(CARBON_CREDIT_AUCTION), amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   commits                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IGCC
     */
    function commitGCC(uint256 amount, address rewardAddress, address referralAddress, uint256 minImpactPower)
        public
        returns (uint256 usdcEffect, uint256 impactPower)
    {
        //Transfer GCC from the msg.sender to the impact catalyst
        _transfer(_msgSender(), address(IMPACT_CATALYST), amount);
        //get back the amount of USDC that was used in the LP and the impact power earned
        (usdcEffect, impactPower) = IMPACT_CATALYST.commitGCC(amount, minImpactPower);
        //handle the commitment
        _handleCommitment(_msgSender(), rewardAddress, amount, usdcEffect, impactPower, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function commitGCC(uint256 amount, address rewardAddress, uint256 minImpactPower)
        external
        returns (uint256, uint256)
    {
        //Same as above, but with no referrer
        return (commitGCC(amount, rewardAddress, address(0), minImpactPower));
    }

    /**
     * @inheritdoc IGCC
     */
    function commitGCCFor(
        address from,
        address rewardAddress,
        uint256 amount,
        address referralAddress,
        uint256 minImpactPower
    ) public returns (uint256 usdcEffect, uint256 impactPower) {
        //Transfer GCC `from` to the impact catalyst
        transferFrom(from, address(IMPACT_CATALYST), amount);
        //If the msg.sender is not `from`, then check and decrease the allowance
        if (_msgSender() != from) {
            _decreaseCommitAllowance(from, _msgSender(), amount, false);
        }
        //get back the amount of USDC that was used in the LP and the impact power earned
        (usdcEffect, impactPower) = IMPACT_CATALYST.commitGCC(amount, minImpactPower);
        //handle the commitment
        _handleCommitment(from, rewardAddress, amount, usdcEffect, impactPower, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function commitGCCFor(address from, address rewardAddress, uint256 amount, uint256 minImpactPower)
        public
        returns (uint256, uint256)
    {
        //Same as above, but with no referrer
        return (commitGCCFor(from, rewardAddress, amount, address(0), minImpactPower));
    }

    /**
     * @inheritdoc IGCC
     */
    function commitGCCForAuthorized(
        address from,
        address rewardAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature,
        address referralAddress,
        uint256 minImpactPower
    ) public returns (uint256, uint256) {
        //Check the deadline
        if (block.timestamp > deadline) {
            _revert(IGCC.CommitPermitSignatureExpired.selector);
        }

        //Load the next nonce
        uint256 _nextCommitNonce = nextCommitNonce[from]++;
        //Construct the message to be signed
        bytes32 message = _constructCommitPermitDigest(
            from, _msgSender(), rewardAddress, referralAddress, amount, _nextCommitNonce, deadline
        );
        //Check the signature
        if (!_checkCommitPermitSignature(from, message, signature)) {
            _revert(IGCC.CommitSignatureInvalid.selector);
        }
        //Increase the allowance for the msg.sender on the `from` account
        _increaseCommitAllowance(from, _msgSender(), amount, false);
        uint256 transferAllowance = allowance(from, _msgSender());
        if (transferAllowance < amount) {
            _approve(from, _msgSender(), amount, false);
        }
        //Commit the GCC
        return (commitGCCFor(from, rewardAddress, amount, referralAddress, minImpactPower));
    }

    /**
     * @inheritdoc IGCC
     */
    function commitGCCForAuthorized(
        address from,
        address rewardAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature,
        uint256 minImpactPower
    ) external returns (uint256 usdcEffect, uint256 impactPower) {
        //Same as above, but with no referrer
        return (commitGCCForAuthorized(from, rewardAddress, amount, deadline, signature, address(0), minImpactPower));
    }

    /**
     * @inheritdoc IGCC
     */
    function commitUSDC(uint256 amount, address rewardAddress, address referralAddress, uint256 minImpactPower)
        public
        returns (uint256 impactPower)
    {
        //Read in the balance of the impact catalyst before the transfer
        uint256 impactCatalystBalBefore = IERC20(USDC).balanceOf(address(IMPACT_CATALYST));
        //Transfer USDC from the msg.sender to the impact catalyst
        IERC20(USDC).transferFrom(msg.sender, address(IMPACT_CATALYST), amount);
        //Read in the balance of the impact catalyst after the transfer
        uint256 impactCatalystBalAfter = IERC20(USDC).balanceOf(address(IMPACT_CATALYST));
        //Calculate the actual amount of USDC available from the transfer (in case of fees since USDC is upgradable)
        uint256 usdcUsing = impactCatalystBalAfter - impactCatalystBalBefore;
        //get back the impaoct power earned
        impactPower = IMPACT_CATALYST.commitUSDC(usdcUsing, minImpactPower);
        //handle the commitment
        _handleUSDCcommitment(_msgSender(), rewardAddress, amount, impactPower, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function commitUSDC(uint256 amount, address rewardAddress, uint256 minImpactPower) external returns (uint256) {
        //Same as above, but with no referrer
        return (commitUSDC(amount, rewardAddress, address(0), minImpactPower));
    }

    /**
     * @inheritdoc IGCC
     */
    function commitUSDCSignature(
        uint256 amount,
        address rewardAddress,
        address referralAddress,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 minImpactPower
    ) external returns (uint256 impactPower) {
        // Execute the transfer with a signed authorization
        IERC20Permit paymentToken = IERC20Permit(USDC);
        uint256 allowance = paymentToken.allowance(msg.sender, address(this));
        //Check allowance to avoid front-running issues
        if (allowance < amount) {
            paymentToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        }
        return (commitUSDC(amount, rewardAddress, referralAddress, minImpactPower));
    }

    /* -------------------------------------------------------------------------- */
    /*                        commit allowance  & allowances                      */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc IGCC
    function setAllowances(address spender, uint256 transferAllowance, uint256 committingAllowance) external {
        _approve(_msgSender(), spender, transferAllowance);
        _commitGCCAllowances[_msgSender()][spender] = committingAllowance;
        emit IGCC.CommitGCCAllowance(_msgSender(), spender, committingAllowance);
    }

    /// @inheritdoc IGCC
    function increaseAllowances(address spender, uint256 addedValue) public {
        _approve(_msgSender(), spender, allowance(_msgSender(), spender) + addedValue);
        _increaseCommitAllowance(_msgSender(), spender, addedValue, true);
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
        _decreaseCommitAllowance(_msgSender(), spender, requestedDecrease, true);
    }

    /**
     * @inheritdoc IGCC
     */
    function increaseCommitAllowance(address spender, uint256 amount) external override {
        _increaseCommitAllowance(_msgSender(), spender, amount, true);
    }

    /**
     * @inheritdoc IGCC
     */
    function decreaseCommitAllowance(address spender, uint256 amount) external override {
        _decreaseCommitAllowance(_msgSender(), spender, amount, true);
    }

    /* -------------------------------------------------------------------------- */
    /*                              view functions                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IGCC
     */
    function commitAllowance(address account, address spender) public view override returns (uint256) {
        return _commitGCCAllowances[account][spender];
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

    /* -------------------------------------------------------------------------- */
    /*                              private functions                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice sets the bucket as minted
     * @param bucketId the id of the bucket to set as minted
     * @dev reverts if the bucket has already been minted
     */
    function _setBucketMinted(uint256 bucketId) private {
        (uint256 key, uint256 shift) = _getKeyAndShiftFromBucketId(bucketId);
        //Can't overflow because _BITS_IN_UINT is 256
        uint256 bitmap = _mintedBucketsBitmap[key];
        if (bitmap & (1 << shift) != 0) _revert(IGCC.BucketAlreadyMinted.selector);
        _mintedBucketsBitmap[key] = bitmap | (1 << shift);
    }

    /**
     * @notice handles the storage writes and event emissions relating to committing gcc.
     * @param from the address of the account committing the credits
     * @param rewardAddress the address to receive the benefits of committing
     * @param usdcEffect - the amount of USDC added into the uniswap v2 lp position
     * @param gccCommitted the amount of GCC committed
     * @param impactPower the effect of committing on the USDC balance
     * @param referralAddress the address of the referrer (zero for no referrer)
     */
    function _handleCommitment(
        address from,
        address rewardAddress,
        uint256 gccCommitted,
        uint256 usdcEffect,
        uint256 impactPower,
        address referralAddress
    ) private {
        if (from == referralAddress) _revert(IGCC.CannotReferSelf.selector);
        //committing USDC calls syncProposals in governance to ensure that the proposals are up to date
        //This design is meant to ensure that the proposals are as up to date as possible
        GOVERNANCE.syncProposals();
        //Increase the total impact power earned by the reward address
        totalImpactPowerEarned[rewardAddress] += impactPower;
        //Grant the nominations to the reward address
        GOVERNANCE.grantNominations(rewardAddress, impactPower);
        //Emit a GCCCommitted event
        emit IGCC.GCCCommitted(from, rewardAddress, gccCommitted, usdcEffect, impactPower, referralAddress);
    }

    /**
     * @notice handles the storage writes and event emissions relating to committing USDC
     * @dev should only be used internally and by function that require a transfer of {amount} to address(this)
     * @param from the address of the account committing the credits
     * @param rewardAddress the address to receive the benefits of committing
     * @param amount the amount of USDC TO commit
     * @param referralAddress the address of the referrer (zero for no referrer)
     */
    function _handleUSDCcommitment(
        address from,
        address rewardAddress,
        uint256 amount,
        uint256 impactPower,
        address referralAddress
    ) private {
        if (from == referralAddress) _revert(IGCC.CannotReferSelf.selector);
        //committing USDC calls syncProposals in governance to ensure that the proposals are up to date
        //This design is meant to ensure that the proposals are as up to date as possible
        GOVERNANCE.syncProposals();
        //Increase the total impact power earned by the reward address
        totalImpactPowerEarned[rewardAddress] += impactPower;
        //Grant the nominations to the reward address
        GOVERNANCE.grantNominations(rewardAddress, impactPower);
        //Emit a USDCCommitted event
        emit IGCC.USDCCommitted(from, rewardAddress, amount, impactPower, referralAddress);
    }

    /**
     * @dev internal function to increase the committing allowance
     * @param from the address of the account to increase the allowance from
     * @param spender the address of the spender to increase the allowance for
     * @param amount the amount to increase the allowance by
     * @param emitEvent whether or not to emit the event
     */
    function _increaseCommitAllowance(address from, address spender, uint256 amount, bool emitEvent) private {
        if (amount == 0) {
            _revert(IGCC.MustIncreaseCommitAllowanceByAtLeastOne.selector);
        }
        uint256 currentAllowance = _commitGCCAllowances[from][spender];
        uint256 newAllowance;
        unchecked {
            newAllowance = currentAllowance + amount;
        }
        //If there was an overflow, then we set the new allowance to type(uint).max
        //Since that is where the allowance will be capped anyway
        if (newAllowance <= currentAllowance) {
            newAllowance = type(uint256).max;
        }
        _commitGCCAllowances[from][spender] = newAllowance;
        if (emitEvent) {
            emit IGCC.CommitGCCAllowance(from, spender, newAllowance);
        }
    }

    /**
     * @dev internal function to decrease the committing allowance
     * @param from the address of the account to decrease the allowance from
     * @param spender the address of the spender to decrease the allowance for
     * @param amount the amount to decrease the allowance by
     * @param emitEvent whether or not to emit the event
     * @dev underflow auto-reverts due to built in safemath
     */
    function _decreaseCommitAllowance(address from, address spender, uint256 amount, bool emitEvent) private {
        uint256 currentAllowance = _commitGCCAllowances[from][spender];

        uint256 newAllowance = currentAllowance - amount;
        _commitGCCAllowances[from][spender] = newAllowance;
        if (emitEvent) {
            emit IGCC.CommitGCCAllowance(from, spender, newAllowance);
        }
    }

    //-------------  PRIVATE UTILS  --------------------//
    /**
     * @notice Returns the key and shift for a bucketId
     * @return key The key for the bucketId
     * @return shift The shift for the bucketId
     * @dev cant overflow because _BITS_IN_UINT is 256
     * @dev no division by zero because _BITS_IN_UINT is 256
     */
    function _getKeyAndShiftFromBucketId(uint256 bucketId) private pure returns (uint256 key, uint256 shift) {
        key = bucketId / _BITS_IN_UINT;
        shift = bucketId % _BITS_IN_UINT;
    }

    /**
     * @dev Constructs a committing permit EIP712 message hash to be signed
     * @param owner The owner of the funds
     * @param spender The spender
     * @param rewardAddress - the address to receive the benefits of committing
     * @param referralAddress - the address of the referrer
     * @param amount The amount of funds
     * @param nonce The next nonce
     * @param deadline The deadline for the signature to be valid
     * @return digest The EIP712 digest
     */
    function _constructCommitPermitDigest(
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
                    COMMIT_PERMIT_TYPEHASH, owner, spender, rewardAddress, referralAddress, amount, nonce, deadline
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
    function _checkCommitPermitSignature(address signer, bytes32 message, bytes memory signature)
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
