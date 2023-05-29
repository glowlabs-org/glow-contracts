// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

error NotAnAgent();
error AlreadyAnAgent();
error TooFewAgents();
error TooManyAgents();

contract GCA {
    address public immutable governanceContract;
    mapping(address => uint256) public agentLastRewardTimestamp;
    uint256 public numActiveAgents;
    uint256 private constant MIN_AGENTS = 2;
    uint256 private constant MAX_AGENTS = 7;
    uint256 private constant DAYS_BEFORE_REWARD_CLEARANCE = 90 days;

    mapping(uint256 => Report) public reports;

    struct Report {
        address agent;
        bytes32 farmId;
        uint192 amount;
        uint64 timestamp;
    }

    event AgentAdded(address agent);
    event AgentRemoved(address agent);
    event ReportIssued(address indexed agent, bytes32 indexed farmId, uint256 amount);

    constructor(address _governanceContract) {
        governanceContract = _governanceContract;
    }

    function _onlyGovernance() internal view {
        require(msg.sender == governanceContract, "Only governance contract can call this function");
    }

    /// @dev is used to add or remove agents
    /// @dev todo: Should payout for time spent as an agent
    function _removeAgent(address agent) internal {
        if (agentLastRewardTimestamp[agent] == 0) revert NotAnAgent();
        delete agentLastRewardTimestamp[agent];
        emit AgentRemoved(agent);
    }

    function _addAgent(address agent) internal {
        if (agentLastRewardTimestamp[agent] > 0) revert AlreadyAnAgent();
        agentLastRewardTimestamp[agent] = block.timestamp;
        emit AgentAdded(agent);
    }

    function editSeats(address[] calldata agentsToRemove, address[] calldata agentsToAdd) external {
        _onlyGovernance();
        uint256 numAgents = numActiveAgents - agentsToRemove.length;
        if (numAgents < MIN_AGENTS) revert TooFewAgents();
        numAgents += agentsToAdd.length;
        if (numAgents > MAX_AGENTS) revert TooManyAgents();

        for (uint256 i; i < agentsToRemove.length;) {
            _removeAgent(agentsToRemove[i]);
            unchecked {
                ++i;
            }
        }
        for (uint256 i; i < agentsToAdd.length;) {
            _addAgent(agentsToAdd[i]);
            unchecked {
                ++i;
            }
        }
        numActiveAgents = numAgents;
    }

    function issueReport(bytes32 farmId, uint256 amount) external {
        if (agentLastRewardTimestamp[msg.sender] == 0) revert NotAnAgent();
        if (amount == 0) revert("Amount cannot be zero");
        reports[block.timestamp] = Report(msg.sender, farmId, uint192(amount), uint64(block.timestamp));
        emit ReportIssued(msg.sender, farmId, amount);
    }

    function getReport(uint256 reportId)
        external
        view
        returns (address agent, bytes32 farmId, uint256 amount, uint256 timestamp_)
    {
        Report memory report = reports[reportId];
        return (report.agent, report.farmId, report.amount, report.timestamp);
    }

    /// @param reportId is the ID of the report
    /// @dev this function is called by a valid GCA to restore a slashed report
    function revalidateSlashedReport(uint256 reportId) public {}

    function revalidateSlashedReports(uint256[] calldata reportIds) external {
        for (uint256 i; i < reportIds.length;) {
            revalidateSlashedReport(reportIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @param reportId is the ID of the rport
    /// @dev this function is called by the governance contract to execute a report
    /// @dev execution means that the reports mints GCC and sends it to the Carbon Credit Auction
    function executeReport(uint256 reportId) external {}

    /// @dev this function is called by a GCA to claim their payout
    /// @dev if there is not enough GLW in the contract, it will claim from the governance contract
    function claimPayout() external {}

    /// @dev this function is called by a GCA to propose a compensation plan
    /// @dev the compensation plan is a list of addresses and the amount of GLW they should receive
    /// @dev the comp is the average of all proposed compensation plans
    function proposeCompensationPlan(uint256[] calldata shares, address[] calldata recipients) external {}

    /// @dev used in compensation if not enough GLW is in the contract to pay out the compensation plan
    function _claimGLWFromInflation() internal {}
}
