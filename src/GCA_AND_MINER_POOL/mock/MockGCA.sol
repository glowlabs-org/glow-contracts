import "../GCA.sol";

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract MockGCA is GCA {
    /**
     * @notice constructs a new GCA contract
     * @param _gcaAgents the addresses of the gca agents
     * @param _glowToken the address of the glow token
     * @param _governance the address of the governance contract
     */
    constructor(address[] memory _gcaAgents, address _glowToken, address _governance)
        GCA(_gcaAgents, _glowToken, _governance)
    {}

    function setGCAs(address[] calldata newGcas) external {
        _setGCAs(newGcas);
    }
}
