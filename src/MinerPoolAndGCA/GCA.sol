// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IGCA} from "@/interfaces/IGCA.sol";
import {IGlow} from "@/interfaces/IGlow.sol";
import "forge-std/console.sol";
import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
// TODO: note to self -- im brain fried rn, go back to the slashable vesting in your notebook

contract GCA is IGCA {
    /**
     * @notice the amount of shares required per agent when submitting a compensation plan
     * @dev this is not strictly enforced, but rather the
     *         the total shares in a comp plan but equal the SHARES_REQUIRED_PER_COMP_PLAN * gcaAgents.length
     */
    uint256 public constant SHARES_REQUIRED_PER_COMP_PLAN = 100_000;

    /// @notice the address of the glow token
    IGlow public immutable GLOW_TOKEN;

    /// @notice the address of the governance contract
    address public immutable GOVERNANCE;

    /// @notice the timestamp of the genesis block
    uint256 public immutable GENESIS_TIMESTAMP;

    /// @notice the shift to apply to the bitpacked compensation plans
    uint256 private constant _UINT24_SHIFT = 24;

    /// @notice the mask to apply to the bitpacked compensation plans
    uint256 private constant _UINT24_MASK = 0xFFFFFF;

    /// @dev 10_000 GLW Per Week available as rewards to all GCAs
    uint256 public constant REWARDS_PER_SECOND_FOR_ALL = 10_000 ether / uint256(7 days);

    /// @dev 1% of the rewards vest per week
    uint256 public constant VESTING_REWARDS_PER_SECOND_FOR_ALL = REWARDS_PER_SECOND_FOR_ALL / (100 * 86400 * 7);

    /// @notice the index of the last proposal that was updated
    uint256 public lastUpdatedProposalIndex;

    /// @notice the hashes of the proposals that have been submitted from {GOVERNANCE}
    bytes32[] public proposalHashes;

    /// @notice the addresses of the gca agents
    address[] public gcaAgents;

    /// @notice the requirements hash of GCA Agents
    bytes32 public requirementsHash;

    /// @notice the bitpacked compensation plans
    mapping(address => uint256) public _compensationPlans;

    /// @notice the gca payouts
    mapping(address => IGCA.GCAPayout) private _gcaPayouts;

    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents the contract starts with
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     * @param _requirementsHash the requirements hash of GCA Agents
     */
    constructor(address[] memory _gcaAgents, address _glowToken, address _governance, bytes32 _requirementsHash) {
        GLOW_TOKEN = IGlow(_glowToken);
        GOVERNANCE = _governance;
        _setGCAs(_gcaAgents);
        GENESIS_TIMESTAMP = GLOW_TOKEN.GENESIS_TIMESTAMP();
        for (uint256 i; i < _gcaAgents.length; ++i) {
            _gcaPayouts[_gcaAgents[i]].lastClaimedTimestamp = uint64(GENESIS_TIMESTAMP);
        }
        requirementsHash = _requirementsHash;
    }

    /// @inheritdoc IGCA
    function isGCA(address account) public view returns (bool) {
        return _compensationPlans[account] > 0;
    }

    /**
     * TODO: Make sure this pays out all active gcas as well
     */
    /// @inheritdoc IGCA
    function submitCompensationPlan(IGCA.ICompensation[] calldata plans) external {
        uint256 bitpackedPlans;
        if (plans.length == 0) {
            _revert(CompensationPlanLengthMustBeGreaterThanZero.selector);
        }
        uint256 gcaLength = gcaAgents.length;
        uint256 requiredShares = SHARES_REQUIRED_PER_COMP_PLAN;
        uint256 sumOfShares;
        if (!isGCA(msg.sender)) {
            _revert(NotGCA.selector);
        }

        for (uint256 i; i < gcaLength; ++i) {
            address agentInGca = gcaAgents[i];
            bool found;
            for (uint256 j; j < plans.length; ++j) {
                if (agentInGca == plans[j].agent) {
                    sumOfShares += plans[i].shares;
                    bitpackedPlans |= plans[j].shares << _calculateShift(i);
                    found = true;
                    break;
                }
            }

            if (!found) {
                _revert(NotGCA.selector);
            }
            _compensationPlans[agentInGca] = bitpackedPlans;
        }

        if (sumOfShares < requiredShares) {
            _revert(InsufficientShares.selector);
        }
        emit IGCA.CompensationPlanSubmitted(msg.sender, plans);
    }

    function setRequirementsHash(bytes32 _requirementsHash) external {
        if (msg.sender != GOVERNANCE) _revert(IGCA.CallerNotGovernance.selector);
        requirementsHash = _requirementsHash;
    }

    /// @inheritdoc IGCA
    function compensationPlan(address gca) public view returns (IGCA.ICompensation[] memory) {
        return _compensationPlan(gca, gcaAgents);
    }

    function _compensationPlan(address gca, address[] memory gcaAddresses)
        public
        view
        returns (IGCA.ICompensation[] memory)
    {
        if (!isGCA(gca)) {
            _revert(NotGCA.selector);
        }
        uint256 bitpackedPlans = _compensationPlans[gca];
        uint256 gcaLength = gcaAddresses.length;
        IGCA.ICompensation[] memory plans = new IGCA.ICompensation[](gcaLength);
        for (uint256 i; i < gcaLength; ++i) {
            plans[i].shares = uint80((bitpackedPlans >> _calculateShift(i)) & _UINT24_MASK);
            plans[i].agent = gcaAddresses[i];
        }

        return plans;
    }

    function claimGlowFromInflation() public virtual {
        GLOW_TOKEN.claimGLWFromGCAAndMinerPool();
    }

    /// @inheritdoc IGCA
    function allGcas() public view returns (address[] memory) {
        return gcaAgents;
    }

    /// @inheritdoc IGCA
    function gcaPayoutData(address gca) public view returns (IGCA.GCAPayout memory) {
        return _gcaPayouts[gca];
    }

    /**
     * @dev Find total owed now and slashable balance using the summation of an arithmetic series
     * @dev formula = n/2 * (2a + (n-1)d) or n/2 * (a + l)
     * @dev read more about this  https://github.com/glowlabs-org/glow-docs/issues/4
     * @dev SB stands for slashable balance
     * @param secondsSinceLastPayout - the  amount of seconds since the last payout
     * @param shares - the amount of shares the gca has
     * @param totalShares - the total amount of shares
     * @return amountNow - the amount of glow owed now
     * @return slashableBalance - the amount of glow that is added to the slashable balance
     */
    function getAmountNowAndSB(uint256 secondsSinceLastPayout, uint256 shares, uint256 totalShares)
        public
        pure
        returns (uint256 amountNow, uint256 slashableBalance)
    {
        (amountNow, slashableBalance) = VestingMathLib.getAmountNowAndSB(
            secondsSinceLastPayout, shares, totalShares, REWARDS_PER_SECOND_FOR_ALL, VESTING_REWARDS_PER_SECOND_FOR_ALL
        );
    }

    /**
     * @param agent - the address of the agent to payout
     * @param gcas - should always be allGcas in storage, but passed through memory for gas savings
     */
    function _payoutAgent(address agent, address[] memory gcas) internal {
        uint256 totalToPayNow;
        uint256 amountToAddToSlashable;
        uint256 totalShares = SHARES_REQUIRED_PER_COMP_PLAN * gcas.length;
        //If the agent is a gca, we need to pay everyone out?
        uint256 lastClaimTimestamp = _gcaPayouts[agent].lastClaimedTimestamp;
        uint256 timeElapsed = block.timestamp - lastClaimTimestamp;
        if (isGCA(agent)) {
            //Check how much they've worked
            //TODO: make sure that lastClaimTimestamp can never be zero
            (uint256 shares,) = _getShares(agent, gcas);
            (totalToPayNow, amountToAddToSlashable) = getAmountNowAndSB(timeElapsed, shares, totalShares);
        }

        //Now we need to calculate how uch
    }

    function getShares(address agent) external view returns (uint256 shares, uint256 totalShares) {
        return _getShares(agent, gcaAgents);
    }

    function _getShares(address agent, address[] memory gcas)
        internal
        view
        returns (uint256 shares, uint256 totalShares)
    {
        uint256 indexOfAgent;
        for (uint256 i; i < gcas.length; i++) {
            if (gcas[i] == agent) {
                indexOfAgent = i;
                break;
            }
        }
        for (uint256 i; i < gcas.length; i++) {
            uint256 bitpackedPlans = _compensationPlans[gcas[i]];
            shares += (bitpackedPlans >> _calculateShift(indexOfAgent)) & _UINT24_MASK;
        }
        totalShares = SHARES_REQUIRED_PER_COMP_PLAN * gcas.length;
    }

    //---------------------------- HELPERS ----------------------------------

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

    /**
     * @dev sets the gca agents and their compensation plans
     *         -  removes all previous gca agents
     *         -  remove all previous compensation plans
     *         -  sets the new gca agents
     *         -  sets the new compensation plans
     *     TODO: Make sure this pays out all GCA's and handles slashes
     */
    function _setGCAs(address[] memory gcaAddresses) internal {
        address[] memory oldGCAs = gcaAgents;
        for (uint256 i; i < oldGCAs.length; ++i) {
            _compensationPlans[oldGCAs[i]] = 0;
        }
        gcaAgents = gcaAddresses;
        for (uint256 i; i < gcaAddresses.length; ++i) {
            _compensationPlans[gcaAddresses[i]] = (SHARES_REQUIRED_PER_COMP_PLAN) << _calculateShift(i);
            //If they have any slashable balance that's unclaimed, we should clean that up here...
        }
    }

    /**
     * @dev calculates the shift to apply to the bitpacked compensation plans
     *     @param index - the index of the gca agent
     *     @return the shift to apply to the bitpacked compensation plans
     */
    function _calculateShift(uint256 index) private pure returns (uint256) {
        return index * _UINT24_SHIFT;
    }
}
