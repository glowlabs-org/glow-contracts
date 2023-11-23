// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

abstract contract GCASalaryHelper {
    error HashesNotUpdated();
    error CannotSetNonceToZero();
    error InvalidRelaySignature();
    error InvalidGCAHash();
    error InvalidUserIndex();
    error InvalidShares();
    error SlashedAgentCannotClaimReward();

    /// @dev one week in seconds
    uint256 private constant ONE_WEEK = uint256(7 days);

    /// @dev 10_000 GLW Per Week available as rewards to all GCAs
    uint256 public constant REWARDS_PER_SECOND_FOR_ALL = 10_000 ether / uint256(7 days);

    /**
     * @notice the amount of shares required per agent when submitting a compensation plan
     * @dev this is not strictly enforced, but rather the
     *         the total shares in a comp plan must equal the SHARES_REQUIRED_PER_COMP_PLAN
     */
    uint256 public constant SHARES_REQUIRED_PER_COMP_PLAN = 100_000;

    /// @dev the type hash for a claim payout relay permit
    bytes32 public constant CLAIM_PAYOUT_RELAY_PERMIT_TYPEHASH =
        keccak256("ClaimPayoutRelay(address relayer,uint256 paymentNonce)");

    //payment nonce -> gca index -> comp plan
    mapping(uint256 => mapping(uint256 => uint32[5])) private _paymentNonceToCompensationPlan;
    //payment nonce -> shift start timestamp
    mapping(uint256 => uint256) private _paymentNonceToShiftStartTimestamp;

    // agent -> payment nonce -> amount already withdrawn
    mapping(address => mapping(uint256 => uint256)) public amountWithdrawnAtPaymentNonce;

    /// @dev slashed agents cannot claim rewards
    mapping(address => bool) public isSlashed;
    //  Private payment nonce.
    /// Private payment nonce only needs to be incremented when a gca submits a new overriding comp plan.
    /// The public paymentNonce() function is also incremented whenever there's a slash event
    /// The public paymentNonce() function should be the _privatePaymentNonce + proposalHashes.length;
    uint256 private _privatePaymentNonce;

    // paymentNonce -> keccak256(abi.encodePacked(address[]));
    mapping(uint256 => bytes32) private _paymentNonceToGCAs;

    /// @notice the next nonce to use in the relay signature
    mapping(address => uint256) public nextRelayNonce;

    /**
     * @param startingAgents the starting gca agents
     */
    constructor(address[] memory startingAgents) payable {
        if (startingAgents.length == 0) return;
        _paymentNonceToGCAs[0] = keccak256(abi.encodePacked(startingAgents));
        unchecked {
            for (uint256 i; i < startingAgents.length; ++i) {
                //starting payment nonce is 0
                //so we set the comp plan for all the agents to the identity matrix
                //for the first payment nonce
                _paymentNonceToCompensationPlan[0][i] = defaultCompPlan(i);
            }
        }
    }
    /**
     * @dev we don't need a deadline on the sig since the relayer cant make the funds go anywhere else,
     *             except for the user's address.
     *             AND - the relayer is restricted to a certian nonce.
     * @param user the user to claim the payout for
     * @param paymentNonce the payment nonce to claim the payout for
     * @param activeGCAsAtPaymentNonce the active gca agents at the payment nonce
     * @param userIndex the index of the user in the active gca agents array
     * @param claimFromInflation whether or not to claim glow from inflation
     * @param sig the relay signature
     */

    function claimPayout(
        address user,
        uint256 paymentNonce,
        address[] calldata activeGCAsAtPaymentNonce,
        uint256 userIndex,
        bool claimFromInflation,
        bytes memory sig
    ) external {
        if (isSlashed[user]) {
            _revert(SlashedAgentCannotClaimReward.selector);
        }
        if (msg.sender != user) {
            bytes32 digest = createRelayDigest(msg.sender, paymentNonce, nextRelayNonce[user]++);
            if (!SignatureChecker.isValidSignatureNow(user, digest, sig)) {
                _revert(InvalidRelaySignature.selector);
            }
        }
        if (claimFromInflation) {
            _claimGlowFromInflation();
        }
        (uint256 withdrawableAmount,, uint256 amountAlreadyWithdrawn) =
            getPayoutData(user, paymentNonce, activeGCAsAtPaymentNonce, userIndex);
        amountWithdrawnAtPaymentNonce[user][paymentNonce] = amountAlreadyWithdrawn + withdrawableAmount;
        _transferGlow(user, withdrawableAmount);
    }

    /**
     * @notice returns the bytes32 digest used for the relay signature
     * @param relayer the relayer that is being granted permission
     * @param paymentNonce the payment nonce that the relayer is being granted permission for
     * @param relayNonce the relay nonce that the relayer is being granted permission for
     * @return digest - the bytes32 digest
     */
    function createRelayDigest(address relayer, uint256 paymentNonce, uint256 relayNonce)
        public
        view
        returns (bytes32)
    {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeperatorV4Main(),
                keccak256(abi.encode(CLAIM_PAYOUT_RELAY_PERMIT_TYPEHASH, relayer, paymentNonce, relayNonce))
            )
        );
        return digest;
    }

    /**
     * @notice gets the payout data for an agent
     * @param user the user to get the payout data for
     * @param paymentNonce the payment nonce to get the payout data for
     * @param activeGCAsAtPaymentNonce the active gca agents at the payment nonce
     * @param userIndex the index of the user in the active gca agents array
     * @dev the function must take in the activeGCAsAtPaymentNonce array to prevent
     *         -   a user from submitting a different array of gca agents
     *         -   and receiving false payout data
     */
    function getPayoutData(
        address user,
        uint256 paymentNonce,
        address[] calldata activeGCAsAtPaymentNonce,
        uint256 userIndex
    ) public view returns (uint256 withdrawableAmount, uint256 slashableAmount, uint256 amountAlreadyWithdrawn) {
        if (keccak256(abi.encodePacked(activeGCAsAtPaymentNonce)) != _paymentNonceToGCAs[paymentNonce]) {
            _revert(InvalidGCAHash.selector);
        }
        if (user != activeGCAsAtPaymentNonce[userIndex]) {
            _revert(InvalidUserIndex.selector);
        }
        uint256 userShares;
        uint256 len = activeGCAsAtPaymentNonce.length;
        unchecked {
            for (uint256 i; i < len; ++i) {
                userShares += _paymentNonceToCompensationPlan[paymentNonce][i][userIndex];
            }
        }
        amountAlreadyWithdrawn = amountWithdrawnAtPaymentNonce[user][paymentNonce];

        uint256 shiftStartTimestamp = _paymentNonceToShiftStartTimestamp[paymentNonce];
        uint256 shiftEndTimestamp = _paymentNonceToShiftStartTimestamp[paymentNonce + 1];
        if (shiftEndTimestamp == 0) {
            shiftEndTimestamp = block.timestamp;
        } else {
            shiftEndTimestamp = _min(shiftEndTimestamp, block.timestamp);
        }
        uint256 secondsWorked = shiftEndTimestamp - shiftStartTimestamp;
        uint256 secondsStopped;
        if (block.timestamp > shiftEndTimestamp) {
            secondsStopped = block.timestamp - shiftEndTimestamp;
        }
        uint256 totalShares = len * SHARES_REQUIRED_PER_COMP_PLAN;

        uint256 rewardPerSecond = userShares * REWARDS_PER_SECOND_FOR_ALL / totalShares;

        (withdrawableAmount, slashableAmount) = VestingMathLib.calculateWithdrawableAmountAndSlashableAmount(
            rewardPerSecond, secondsWorked, secondsStopped, amountAlreadyWithdrawn
        );

        return (withdrawableAmount, slashableAmount, amountAlreadyWithdrawn);
    }

    /**
     * @notice returns the shift start timestamp for a payment nonce
     * @param nonce the payment nonce to get the shift start timestamp for
     * @return shiftStartTimestamp - the shift start timestamp for the payment nonce or 0 if it does not exist
     */
    function paymentNonceToShiftStartTimestamp(uint256 nonce) external view returns (uint256) {
        return _paymentNonceToShiftStartTimestamp[nonce];
    }

    /**
     * @notice returns the gca agents hash for a payment nonce
     * @param nonce the payment nonce to get the gca agents hash for
     * @return gcaHash - the gca agents hash for the payment nonce
     */
    function payoutNonceToGCAHash(uint256 nonce) external view returns (bytes32) {
        return _paymentNonceToGCAs[nonce];
    }

    /**
     * @notice returns the comp plan for a payment nonce and gca index
     * @param nonce the payment nonce to get the comp plan for
     * @param index the gca index to get the comp plan for
     * @return shares - the comp plan for the payment nonce and gca index
     */
    function paymentNonceToCompensationPlan(uint256 nonce, uint256 index) external view returns (uint32[5] memory) {
        return _paymentNonceToCompensationPlan[nonce][index];
    }

    /**
     * @notice returns the current payment nonce in storage
     * @return paymentNonce - the current payment nonce
     */
    function paymentNonce() public view returns (uint256) {
        return _privatePaymentNonce;
    }

    /// @dev should only be used once in the constructor of GCA
    function setZeroPaymentStartTimestamp() internal {
        _paymentNonceToShiftStartTimestamp[0] = _genesisTimestamp();
    }
    /**
     * @notice slashes an agent
     * @param user the user to slash
     */

    function _slash(address user) internal {
        isSlashed[user] = true;
    }

    /**
     * @param compPlan the comp plans to submit
     * @param indexOfGCA the index of the gca submitting the comp plan
     * @param totalGCAs the total number of gca agents
     */
    function handleCompensationPlanSubmission(uint32[5] calldata compPlan, uint256 indexOfGCA, uint256 totalGCAs)
        internal
    {
        uint256 totalShares;
        for (uint256 i; i < totalGCAs; ++i) {
            totalShares += compPlan[i];
        }
        if (totalShares != SHARES_REQUIRED_PER_COMP_PLAN) {
            _revert(InvalidShares.selector);
        }

        //Get the current payment nonce.
        uint256 _paymentNonce = paymentNonce();
        uint256 nextPaymentNonce = _paymentNonce + 1;

        uint256 currentShiftStartTimestamp = _paymentNonceToShiftStartTimestamp[_paymentNonce];

        /**
         * When we create a new comp plan, we increment the payment nonce by 1.
         *         We only increment the nonce when the comp. period has actually begun.
         *
         *         For example, if we're in comp period 1, and we submit a new comp plan for comp period 2,
         *         we initialize comp period 2 to start at block.timestamp + ONE_WEEK,
         *         Therefore, there is a 1 week period where the comp plan is not active and comp plan 1
         *         is still being acted upon, BUT, the nonce has already been incremented.
         *
         *         Therefore, that means that {currentShiftStartTimestamp} is the start of period 2,
         *         and if block.timestamp is LESS than that, that means that comp period 2 has not started
         *         and all comp. plans that are submitted will have an effect on comp period 2.
         *
         *         Once block.timestamp is greater than {currentShiftStartTimestamp}, that means that
         *         comp period 2 has started, and all comp plans submitted will have an effect on comp period 3.
         *
         *         This keeps going on and on and on.
         */

        /**
         * This evaluates as the initializer for the comp plan being proposed.
         */
        if (block.timestamp > currentShiftStartTimestamp) {
            //We need to increment the nonce
            _paymentNonceToShiftStartTimestamp[nextPaymentNonce] = block.timestamp + ONE_WEEK;

            //Make sure that all the hashes are updated
            bytes32 gcaHash = _paymentNonceToGCAs[_paymentNonce];
            _paymentNonceToGCAs[nextPaymentNonce] = gcaHash;
            for (uint256 i; i < totalGCAs; ++i) {
                if (i == indexOfGCA) {
                    _paymentNonceToCompensationPlan[nextPaymentNonce][i] = compPlan;
                } else {
                    _paymentNonceToCompensationPlan[nextPaymentNonce][i] =
                        _paymentNonceToCompensationPlan[_paymentNonce][i];
                }
            }
            _privatePaymentNonce = nextPaymentNonce;
            return;
        }

        //If we are still in the current week, we need to put the comp plan
        //in the current payment nonce (which is the next upcoming plan).

        _paymentNonceToCompensationPlan[_paymentNonce][indexOfGCA] = compPlan;
    }

    /**
     * @param gcaAgents the gca agents
     * @dev handles incrementing payment nonce,
     *             - setting the gca agents hash
     *             - setting the shift start timestamp
     *             - setting the comp plans to the identity matrix
     *                 - (i.e. each gca agent gets 100_000 shares)
     */
    function callbackInElectionEvent(address[] memory gcaAgents) internal {
        //TODO: come back to this comment and decipher - Make sure to check proposalHashes.length mistmatchs
        uint256 _paymentNonce = paymentNonce();
        uint256 currentShiftStartTimestamp = _paymentNonceToShiftStartTimestamp[_paymentNonce];

        //If the current bucket has started, we move to the next bucket
        if (block.timestamp > currentShiftStartTimestamp) {
            ++_paymentNonce;
            _privatePaymentNonce = _paymentNonce;
        }

        //Set the gca agents hash
        _paymentNonceToGCAs[_paymentNonce] = keccak256(abi.encodePacked(gcaAgents));
        _paymentNonceToShiftStartTimestamp[_paymentNonce] = block.timestamp;
        //All the reports in here need to be set to a identity matrix
        unchecked {
            for (uint256 i; i < gcaAgents.length; ++i) {
                _paymentNonceToCompensationPlan[_paymentNonce][i] = defaultCompPlan(i);
            }
        }
    }

    /**
     * @notice returns the default comp plan for a gca agent
     * @param gcaIndex the index of the gca agent
     * @dev the default comp plan is the identity matrix
     * @return shares - the default comp plan for a gca agent at index {gcaIndex}
     */
    function defaultCompPlan(uint256 gcaIndex) internal pure returns (uint32[5] memory shares) {
        shares[gcaIndex] = uint32(SHARES_REQUIRED_PER_COMP_PLAN);
        return shares;
    }

    /**
     * @dev returns the min of (a,b)
     * @param a the first number
     * @param b the second number
     * @return min - the min of (a,b)
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice claims glow from inflation
     * @dev the function must be overriden by the parent contract
     */
    function _claimGlowFromInflation() internal virtual;

    /**
     * @notice returns the domain seperator for the relay signature
     * @dev the function must be overriden by the parent contract
     * @return domainSeperator - the domain seperator for the relay signature
     */
    function _domainSeperatorV4Main() internal view virtual returns (bytes32);
    /**
     * @notice returns the genesis timestamp of the glow protocol
     * @return genesisTimestamp - the genesis timestamp of the glow protocol
     * @dev the function must be overriden by the parent contract
     */
    function _genesisTimestamp() internal view virtual returns (uint256);
    /**
     * @notice returns the current week
     * @return week - the current week
     * @dev the function must be overriden by the parent contract
     */
    function _currentWeek() internal view virtual returns (uint256);

    /**
     * @notice transfers glow to an address
     * @param to the address to transfer glow to
     * @param amount the amount of glow to transfer
     * @dev the function must be overriden by the parent contract
     */
    function _transferGlow(address to, uint256 amount) internal virtual;

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */
    function _revert(bytes4 selector) internal pure {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}
