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
        address _carbonCreditAuction,
        address _vetoCouncil
    )
        MinerPoolAndGCA(
            _gcaAgents,
            _glowToken,
            _governance,
            _requirementsHash,
            _earlyLiquidity,
            _grcToken,
            _carbonCreditAuction,
            _vetoCouncil
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

    function getUserBitmapForBucket(uint256 bucketId, address user) public view returns (uint256) {
        return _getUserBitmapForBucket(bucketId, user);
    }

    function setGRCToken(address grcToken, bool adding, uint256 currentBucket) public {
        _setGRCToken(grcToken, adding, currentBucket);
    }
}
