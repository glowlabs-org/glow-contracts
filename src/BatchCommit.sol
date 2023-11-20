// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGCC} from "@/interfaces/IGCC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BatchRetire
 * @notice A contract for batch committing GCC and USDC
 * @dev This contract is used to committments GCC and USDC in batches and emit bytes
 *             - that capture the breakdown of the commitments
 *     The bytes are as follows
 *         struct Commitment {
 *             address from,
 *             uint256 amount,
 *         }
 *         bytes = abi.encode(Commitment[])
 */
contract BatchCommit {
    /// @notice the GCC token
    IGCC public immutable GCC;

    /// @notice the USDC token
    IERC20 public immutable USDC;

    /**
     * @notice emitted when GCC is committed
     * @param data the bytes that capture the breakdown of the commitments
     *         -   as mentioned in the contract description
     */
    event GCCEmission(bytes data);
    /**
     * @notice emitted when GCC is committed
     * @param data the bytes that capture the breakdown of the commitments
     *         -   as mentioned in the contract description
     */
    event USDCEmission(bytes data);

    /**
     * @param gcc the address of the GCC token
     * @param usdc the address of the USDC token
     */
    constructor(address gcc, address usdc) {
        GCC = IGCC(gcc);
        USDC = IERC20(usdc);
    }

    /**
     * @notice the entry point for committing GCC
     * @param amount the amount of GCC to commit
     * @param data the bytes that capture the breakdown of the commitments
     *         -   as mentioned in the contract description
     */
    function commitGCC(uint256 amount, address rewardAddress, bytes calldata data) external {
        GCC.transferFrom(msg.sender, address(this), amount);
        GCC.commitGCC(amount, rewardAddress);
        emit GCCEmission(data);
    }

    /**
     * @notice the entry point for committing USDC
     * @param amount the amount of USDC to commit
     * @param data the bytes that capture the breakdown of the commitments
     *         -   as mentioned in the contract description
     */
    function commitUSDC(uint256 amount, address rewardAddress, bytes calldata data) external {
        uint256 balBefore = USDC.balanceOf(address(this));
        USDC.transferFrom(msg.sender, address(this), amount);
        uint256 balAfter = USDC.balanceOf(address(this));
        uint256 amountToRetire = balAfter - balBefore;
        USDC.approve(address(GCC), amountToRetire);
        GCC.commitUSDC(amountToRetire, rewardAddress);
        emit USDCEmission(data);
    }
}
