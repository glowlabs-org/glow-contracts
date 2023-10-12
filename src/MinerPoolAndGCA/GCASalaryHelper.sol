// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

//1 slot
struct PayoutHelper {
    uint64 shiftStartTimestamp;
    uint64 shiftEndTimestamp;
    uint128 amountAlreadyWithdrawn;
}

struct CompenstionPlan {
    // 1 slot
    uint32[7] bitpackedPlans;
}
//amount already withdrawn can be packed into 128 bits
//2**128-1 / 1e18 = 3.4e20. It would take 1307692307692307.8 years to overflow at 5000 glow per week

struct PaymentPeriod {
    uint64 startTimestamp;
    uint64 endTimestamp;
}

contract GCASalaryHelper {
    error HashesNotUpdated();
    error CannotSetNonceToZero();

    uint256 private constant ONE_WEEK = uint256(7 days);
    uint256 private constant _UINT17_MASK = (1 << 17) - 1;

    /**
     * @notice the amount of shares required per agent when submitting a compensation plan
     * @dev this is not strictly enforced, but rather the
     *         the total shares in a comp plan but equal the SHARES_REQUIRED_PER_COMP_PLAN * gcaAgents.length
     */
    uint256 public constant SHARES_REQUIRED_PER_COMP_PLAN = 100_000;
    mapping(uint256 => PaymentPeriod) public paymentNonceToPeriod;

    //payment nonce -> bitpacked comp plans
    /**
     * In First UINT
     *     [0...16] weight for gca 0 that gca 0 submitted
     *     [17...33] weight for gca 1 that gca 0 submitted
     *     [34...50] weight for gca 2 that gca 0 submitted
     *     .....
     *     [238...254] weight for gca 4 that gca 2 submitted
     *     ........
     * In Second UINT
     *     [0...16] weight for gca 0 that gca 3 submitted
     *     [17...33] weight for gca 1 that gca 3 submitted
     *     .....
     *     [136...152] weight for gca 3 that gca 4 submitted
     *     [153...169] weight for gca 4 that gca 4 submitted
     */
    mapping(uint256 => uint256[2]) public paymentNonceToCompensationPlan;

    uint256 private _privatePaymentNonce;

    constructor() {}

    //TODO: In GCA external function, we need to make sure that the gca is the one in the index
    function _submitCompensationPlan(uint bitpackedCompensationPlan, uint256 indexOfGCA, uint256 totalGCAs)
        internal
    {
        {
            uint256 totalSharesSubmitted;
            uint256 expectedShares = SHARES_REQUIRED_PER_COMP_PLAN * totalGCAs;
            unchecked {
                for (uint256 i; i < totalGCAs.length; ++i) {
                    totalSharesSubmitted += (bitpackedCompensationPlan >> (17 * i)) & _UINT17_MASK;
                }
            }
            if(totalSharesSubmitted != expectedShares) {
                revert("Invalid shares submitted");
            }
        }   
        //each gca takes 17*5 bits = 85 bits for their plan
        //First plan [0...84] in First UINT
        //Second plan [85...169] in second UINT
        //Third plan [170...254] in third UINT
        //Fourth plan [
        //[0,1,2] fit into the first slot
        //[3,4] fit into the second slot.
        uint bitpackIndex = indexOfGCA / 2;

        uint256 _paymentNonce = paymentNonce();
        uint256 nextPaymentNonce = _paymentNonce + 1;
        uint256 weekEndTimestamp = _weekEndTimestamp(_currentWeek());

        PaymentPeriod memory currentPaymentPeriod = paymentNonceToPeriod[_paymentNonce];
        if (block.timestamp < currentPaymentPeriod.startTimestamp) {
            paymentNonceToCompensationPlan[_paymentNonce][indexOfGCA] = bitpackedCompensationPlan;
            return;
        }

        PaymentPeriod memory nextPaymentPeriod = paymentNonceToPeriod[nextPaymentNonce];
        if (nextPaymentPeriod.startTimestamp == 0) {
            //set the payment period start timestamp to the end of the current payment period
            paymentNonceToPeriod[nextPaymentNonce] = PaymentPeriod({startTimestamp: weekEndTimestamp, endTimestamp: 0});
            //We also need to make sure the end the last payment period is set
            paymentNonceToPeriod[_paymentNonce].endTimestamp = weekEndTimestamp;
            paymentNonceToCompensationPlan[nextPaymentNonce][indexOfGCA] = bitpackedCompensationPlan;

            _privatePaymentNonce = nextPaymentNonce;
            return;
        }
    }

    //Compensation plans

    //Must be overrided
    function paymentNonce() internal view virtual returns (uint256) {
        revert();
    }

    function _genesisTimestamp() internal view virtual returns (uint256) {
        revert();
    }

    function _currentWeek() internal view virtual returns (uint256) {
        revert();
    }

    function _weekEndTimestamp(uint256 week) internal view virtual returns (uint256) {
        revert();
    }
}
