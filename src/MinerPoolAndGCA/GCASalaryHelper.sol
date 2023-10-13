// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "forge-std/console.sol";

/**
 */

contract GCASalaryHelper {
    error HashesNotUpdated();
    error CannotSetNonceToZero();
    error InvalidRelaySignature();
    error InvalidGCAHash();
    error InvalidUserIndex();
    error InvalidShares();
    error SlashedAgentCannotClaimReward();

    uint256 private constant ONE_WEEK = uint256(7 days);

    /// @dev 10_000 GLW Per Week available as rewards to all GCAs
    uint256 public constant REWARDS_PER_SECOND_FOR_ALL = 10_000 ether / uint256(7 days);

    /**
     * @notice the amount of shares required per agent when submitting a compensation plan
     * @dev this is not strictly enforced, but rather the
     *         the total shares in a comp plan but equal the SHARES_REQUIRED_PER_COMP_PLAN * gcaAgents.length
     */
    uint256 public constant SHARES_REQUIRED_PER_COMP_PLAN = 100_000;

    //payment nonce -> gca index -> comp plan
    mapping(uint256 => mapping(uint256 => uint32[5])) private _paymentNonceToCompensationPlan;
    //payment nonce -> shift start timestamp
    mapping(uint256 => uint256) private _paymentNonceToShiftStartTimestamp;

    // agent -> payment nonce -> amount already withdrawn
    mapping(address => mapping(uint256 => uint256)) public amountWithdrawnAtPaymentNonce;

    mapping(address => bool) public isSlashed;
    //  Private payment nonce.
    /// Private payment nonce only needs to be incremented when a gca submits a new overriding comp plan.
    /// The public paymentNonce() function is also incremented whenever there's a slash event
    /// The public paymentNonce() function should be the _privatePaymentNonce + proposalHashes.length;
    uint256 private _privatePaymentNonce;

    //keccak256(abi.encodePacked(address[]));
    mapping(uint256 => bytes32) private _payoutNonceToGCAs;

    mapping(address => uint256) public nextRelayNonce;

    bytes32 public constant CLAIM_PAYOUT_RELAY_PERMIT_TYPEHASH =
        keccak256("ClaimPayoutRelay(address relayer,uint256 paymentNonce)");

    constructor(address[] memory startingAgents) payable {
        if (startingAgents.length == 0) return;
        _payoutNonceToGCAs[0] = keccak256(abi.encodePacked(startingAgents));
        unchecked {
            for (uint256 i; i < startingAgents.length; ++i) {
                _paymentNonceToCompensationPlan[0][i] = defaultCompPlan(i);
            }
        }
    }

    /// @dev should only be used once in the constructor of GCA
    function setZeroPaymentStartTimestamp() internal {
        _paymentNonceToShiftStartTimestamp[0] = _genesisTimestamp();
    }

    //handlePayoutChangeFromGCAEvent(); ^^ TODO: work on this.....

    //TODO: In GCA external function, we need to make sure that the gca is the one in the index
    function handleCompensationPlanSubmission(uint32[5] calldata compPlan, uint256 indexOfGCA, uint256 totalGCAs)
        internal
    {
        uint256 totalShares;
        uint256 expectedShares = SHARES_REQUIRED_PER_COMP_PLAN;
        for (uint256 i; i < totalGCAs; ++i) {
            totalShares += compPlan[i];
        }
        if (totalShares != expectedShares) {
            _revert(InvalidShares.selector);
        }

        //Get the current payment nonce.
        uint256 _paymentNonce = paymentNonce();
        uint256 nextPaymentNonce = _paymentNonce + 1;

        uint256 currentShiftStartTimestamp = _paymentNonceToShiftStartTimestamp[_paymentNonce];
        uint256 nextShiftStartTimestamp = _paymentNonceToShiftStartTimestamp[nextPaymentNonce];

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
         *         and all comp. plans that are submitted will have an affect on comp period 2.
         *
         *         Once, block.timestamp is greater than {currentShiftStartTimestamp}, that means that
         *         comp period 2 has started, and all comp plans submitted will have an affect on comp period 3.
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
            bytes32 gcaHash = _payoutNonceToGCAs[_paymentNonce];
            _payoutNonceToGCAs[nextPaymentNonce] = gcaHash;
            _paymentNonceToCompensationPlan[nextPaymentNonce][indexOfGCA] = compPlan;
            //The gca proposing the comp plan is the one in the index and also is responsible for
            //porting over the past hash of the gca's as well as the payment plans.
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

    function callbackInElectionEvent(address[] memory gcaAgents) internal {
        //Make sure to check proposalHashes.length mistmatchs
        uint256 _paymentNonce = paymentNonce();
        uint256 currentShiftStartTimestamp = _paymentNonceToShiftStartTimestamp[_paymentNonce];

        //If the current bucket has started, we override the next bucket
        if (block.timestamp > currentShiftStartTimestamp) {
            ++_paymentNonce;
            _privatePaymentNonce = _paymentNonce;
        }

        //Set the gca agents hash
        _payoutNonceToGCAs[_paymentNonce] = keccak256(abi.encodePacked(gcaAgents));
        _paymentNonceToShiftStartTimestamp[_paymentNonce] = block.timestamp;
        //All the reports in here need to be set to a identity matrix
        unchecked {
            for (uint256 i; i < gcaAgents.length; ++i) {
                _paymentNonceToCompensationPlan[_paymentNonce][i] = defaultCompPlan(i);
            }
        }
    }

    function createRelayDigest(address relayer, uint256 paymentNonce, uint256 relayNonce)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeperatorV4Main(),
                keccak256(abi.encode(CLAIM_PAYOUT_RELAY_PERMIT_TYPEHASH, relayer, paymentNonce, relayNonce))
            )
        );
    }

    /**
     * @dev we don't need a deadline on the sig since the relayer cant make the funds go anywhere else,
     *             except for the user's address.
     *             AND - the relayer is restricted to a certian nonce.
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

    function getPayoutData(
        address user,
        uint256 paymentNonce,
        address[] calldata activeGCAsAtPaymentNonce,
        uint256 userIndex
    ) public view returns (uint256 withdrawableAmount, uint256 slashableAmount, uint256 amountAlreadyWithdrawn) {
        if (keccak256(abi.encodePacked(activeGCAsAtPaymentNonce)) != _payoutNonceToGCAs[paymentNonce]) {
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

    function defaultCompPlan(uint256 gcaIndex) internal pure returns (uint32[5] memory shares) {
        shares[gcaIndex] = uint32(SHARES_REQUIRED_PER_COMP_PLAN);
        return shares;
    }

    function paymentNonceToShiftStartTimestamp(uint256 nonce) external view returns (uint256) {
        return _paymentNonceToShiftStartTimestamp[nonce];
    }

    function paymentNonceToCompensationPlan(uint256 nonce, uint256 index) external view returns (uint32[5] memory) {
        return _paymentNonceToCompensationPlan[nonce][index];
    }

    function paymentNonce() public view returns (uint256) {
        return _privatePaymentNonce;
    }

    function _genesisTimestamp() internal view virtual returns (uint256) {
        revert();
    }

    function _currentWeek() internal view virtual returns (uint256) {
        revert();
    }

    function payoutNonceToGCAHash(uint256 nonce) external view returns (bytes32) {
        return _payoutNonceToGCAs[nonce];
    }

    function _weekEndTimestamp(uint256 week) internal view virtual returns (uint256) {
        return _genesisTimestamp() + (week * ONE_WEEK);
    }

    function _domainSeperatorV4Main() internal view virtual returns (bytes32) {
        revert();
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _transferGlow(address to, uint256 amount) internal virtual {
        revert();
    }

    function _claimGlowFromInflation() internal virtual {
        revert();
    }

    function _slash(address user) internal {
        isSlashed[user] = true;
    }

    /**
     * @notice More efficiently reverts with a bytes4 selector
     * @param selector The selector to revert with
     */

    function _revert(bytes4 selector) internal pure {
        assembly {
            mstore(0x0, selector)
            revert(0x0, 0x04)
        }
    }
}
