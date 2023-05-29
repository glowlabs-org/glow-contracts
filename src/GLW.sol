// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GLW is ERC20 {
    uint256 private lastNominationDepositedTimestamp;
    /// @dev Upon construction 66 million GLW is sent to the vesting contract
    /// @dev Upon construction 6 million GLW is sent to the liquidity contract

    constructor(address _vestingContract, address _liquidityContract) ERC20("Glow", "GLW") {
        _mint(_vestingContract, 66_000_000 ether);
        _mint(_liquidityContract, 6_000_000 ether);
    }

    /// @dev This function is the entry point for users to stake their GLW
    /// @dev once users stake, they will earn nominations for each GCC retired
    function stake(uint256 amount) external {
        return;
    }

    /// @dev This function is the entry point for users to unstake their GLW
    /// @dev after unstake, the user will no longer earn nominations for GCC retired and their GLW will be untrasferrable for 5 years
    function unstake(uint256 amount) external {
        return;
    }

    /// @dev This function is the entry point for approved entities to claim their GLW
    /// @dev when this function is called, the GLW owed to the entity is minted and transferred to the entity
    /*
        * 9 million tokens must be distributed to carbon credit producers mining in the GLW Pool.
        * The remaining 3 million are used for the governance protocol.
        * 2.1 Million to grants proposals
        * 300,000 to veto council compensation
        * 600,000 to GCA compensation
    */
    function claimFromProtocolInflation() external {
        return;
    }

    /// @param account The address of the account to check
    /// @return The amount of GLW staked by `account`
    /// @dev is also called by `Governance` to determine voting power
    function numStakedGLW(address account) external view returns (uint256) {
        return 0;
    }

    /// @param amount the amount of nominations to add to the nomination pool that is dispersed to stakers
    /// @dev this function is called by the `GCC` contract when a GCC is retired
    function increaseNominationPool(uint256 amount) external {
        return;
    }

    /// @dev will disperse the nomination pool to stakers
    /// @dev will make sure that a user cannot transfer their GLW that is on cooldown
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20) {
        return;
    }

    /// @dev this function will return the total pool of nominations
    /// @dev it decays with a half life of 12 months
    function totalNominations() public view returns (uint256) {
        return 0;
    }

    /// @dev this function will return the total nominations of an account
    /// @dev it decays with a half life of 12 months
    function nominationsOf(address account) public view returns (uint256) {
        return 0;
    }

    /// @dev helper that will adjust the amount of nominations on the half life of 12 months
    function _adjustWithHalfLife(uint256 amount, uint256 lastUpdatedTimestamp) internal pure returns (uint256) {
        return 0;
    }
}
