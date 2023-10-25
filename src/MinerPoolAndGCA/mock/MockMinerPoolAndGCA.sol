// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "../MinerPoolAndGCA.sol";

contract MockMinerPoolAndGCA is MinerPoolAndGCA {
    constructor(
        address[] memory _gcaAgents,
        address _glowToken,
        address _governance,
        bytes32 _requirementsHash,
        address _earlyLiquidity,
        address _grcToken,
        address _vetoCouncil,
        address _holdingContract
    )
        MinerPoolAndGCA(
            _gcaAgents,
            _glowToken,
            _governance,
            _requirementsHash,
            _earlyLiquidity,
            _grcToken,
            _vetoCouncil,
            _holdingContract
        )
    {}

    function setGCAs(address[] calldata newGcas) external {
        _setGCAs(newGcas);
    }

    function incrementSlashNonce() public {
        slashNonceToSlashTimestamp[slashNonce] = block.timestamp;
        ++slashNonce;
    }

    /**
     * @notice returns the WCEIL for the given slash nonce
     * @param _slashNonce the slash nonce
     * @return the WCEIL
     */
    function WCEIL(uint256 _slashNonce) public view returns (uint256) {
        return _WCEIL(_slashNonce);
    }

    function pushRequirementsHashMock(bytes32 hash) external {
        proposalHashes.push(hash);
    }

    function getUserBitmapForBucket(uint256 bucketId, address user, address token) public view returns (uint256) {
        return _getUserBitmapForBucket(bucketId, user, token);
    }

    function setGRCToken(address grcToken, bool adding, uint256 currentBucket) public {
        _setGRCToken(grcToken, adding, currentBucket);
    }

    /**
     * @dev checks to make sure the weights in the report
     *         - dont overflow the total weights that have been set for the bucket
     *         - Without this check, a malicious weight could be used to overflow the total weights
     *         - and grab rewards from other buckets
     * @param bucketId - the id of the bucket
     * @param totalGlwWeight - the total amount of glw weight for the bucket
     * @param totalGrcWeight - the total amount of grc weight for the bucket
     * @param glwWeight - the glw weight of the leaf in the report being claimed
     * @param grcWeight - the grc weight of the leaf in the report being claimed
     */
    function checkWeightsForOverflow(
        uint256 bucketId,
        uint256 totalGlwWeight,
        uint256 totalGrcWeight,
        uint256 glwWeight,
        uint256 grcWeight
    ) external {
        _checkWeightsForOverflow(bucketId, totalGlwWeight, totalGrcWeight, glwWeight, grcWeight);
    }

    function pushedWeights(uint256 bucketId) external view returns (uint64, uint64) {
        return (_weightsPushed[bucketId].pushedGlwWeight, _weightsPushed[bucketId].pushedGrcWeight);
    }

    function currentWeekInternal() public view returns (uint256) {
        return _currentWeek();
    }

    function domainSeperatorV4MainInternal() public view returns (bytes32) {
        return _domainSeperatorV4Main();
    }

    function domainSeperatorOZ() public view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
