// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGCCV2 as IGCC} from "@/interfaces/IGCCV2.sol";
import {ICarbonCreditAuction} from "@/interfaces/ICarbonCreditAuction.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IGovernance} from "@/interfaces/IGovernance.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {ImpactCatalyst} from "@/ImpactCatalyst.sol";
import {IERC20Permit} from "@/interfaces/IERC20Permit.sol";
import {UniswapV2Library} from "@/libraries/UniswapV2Library.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {LibBitmap} from "@solady/utils/LibBitmap.sol";
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

contract GCCV2 is ERC20, ERC20Burnable, IGCC {
    using LibBitmap for LibBitmap.Bitmap;
    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */

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

    // /**
    //  * @notice The bitmap of minted buckets
    //  * @dev key 0 contains the first 256 buckets, key 1 contains the next 256 buckets, etc.
    //  */
    // mapping(uint256 => uint256) private _mintedBucketsBitmap;

    LibBitmap.Bitmap private _mintedBucketsBitmap;

    /**
     * @notice The total impact power earned by a user from their USDC or GCC commitments
     */
    mapping(address => uint256) public totalImpactPowerEarned;

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
    ) payable ERC20("Glow Carbon Certificate", "GCC-BETA-V2") {
        // Set the immutable variables
        USDC = _usdc;
        GCA_AND_MINER_POOL_CONTRACT = _gcaAndMinerPoolContract;
        UNISWAP_ROUTER = IUniswapRouterV2(_uniswapRouter);
        GOVERNANCE = IGovernance(_governance);
        GLOW = _glowToken;
        //Create the carbon credit auction directly in the constructor
        CarbonCreditDescendingPriceAuction cccAuction = new CarbonCreditDescendingPriceAuction({
            glow: IERC20(_glowToken),
            gcc: IERC20(address(this)),
            startingPrice: 1e5 // Carbon Credit Auction sells increments of 1e6 GCC,
                // Setting the price to 1e5 per unit means that 1 GCC = .1 GLOW
        });

        CARBON_CREDIT_AUCTION = ICarbonCreditAuction(address(cccAuction));
        //Create the impact catalyst
        address factory = UNISWAP_ROUTER.factory();
        address pair = getPair(factory, _usdc);

        //The impact catalyst is responsible for handling the commitments of GCC and USDC
        IMPACT_CATALYST = new ImpactCatalyst(_usdc, _uniswapRouter, factory, pair);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   minting                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @inheritdoc IGCC
     */
    function mintToCarbonCreditAuction(uint256 bucketId, uint256 amount) external {
        if (msg.sender != GCA_AND_MINER_POOL_CONTRACT) _revert(IGCC.CallerNotGCAContract.selector);
        _setBucketMintedAndRevertIfAlreadyMinted(bucketId);
        if (amount > 0) {
            CARBON_CREDIT_AUCTION.receiveGCC(amount);
            _mint(address(CARBON_CREDIT_AUCTION), amount);
        }
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
        _transfer(msg.sender, address(IMPACT_CATALYST), amount);
        //get back the amount of USDC that was used in the LP and the impact power earned
        (usdcEffect, impactPower) = IMPACT_CATALYST.commitGCC(amount, minImpactPower);
        //handle the commitment
        _handleCommitment(msg.sender, rewardAddress, amount, usdcEffect, impactPower, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function commitGCC(uint256 amount, address rewardAddress, uint256 minImpactPower)
        external
        returns (uint256, uint256)
    {
        // Same as above, but with no referrer
        return commitGCC(amount, rewardAddress, address(0), minImpactPower);
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
        _handleUSDCcommitment(msg.sender, rewardAddress, amount, impactPower, referralAddress);
    }

    /**
     * @inheritdoc IGCC
     */
    function commitUSDC(uint256 amount, address rewardAddress, uint256 minImpactPower) external returns (uint256) {
        // Same as above, but with no referrer
        return (commitUSDC(amount, rewardAddress, address(0), minImpactPower));
    }

    /* -------------------------------------------------------------------------- */
    /*                                 view funcs                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IGCC
     */
    function isBucketMinted(uint256 bucketId) external view returns (bool) {
        return _mintedBucketsBitmap.get(bucketId);
    }

    /* -------------------------------------------------------------------------- */
    /*                              private functions                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice sets the bucket as minted
     * @param bucketId the id of the bucket to set as minted
     * @dev reverts if the bucket has already been minted
     */
    function _setBucketMintedAndRevertIfAlreadyMinted(uint256 bucketId) private {
        if (_mintedBucketsBitmap.get(bucketId)) _revert(IGCC.BucketAlreadyMinted.selector);
        _mintedBucketsBitmap.set(bucketId);
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
     * @notice Returns the univ2 pair for a given factory and token
     * @param factory The address of the univ2 factory
     * @param _usdc The address of the USDC token
     * @return pair The address of the univ2 pair of the factory and token with this contract
     */
    function getPair(address factory, address _usdc) internal view virtual returns (address) {
        return UniswapV2Library.pairFor(factory, _usdc, address(this));
    }
    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */

    function _revert(bytes4 selector) internal pure {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}
