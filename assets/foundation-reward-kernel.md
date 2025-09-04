# Foundation Reward Kernel & Counterfactual Holder Factory

## Overview

The **FoundationRewardKernel** is a Merkle-tree based reward distribution system that allows the Glow Foundation to distribute tokens to users in a secure, verifiable manner. It works in conjunction with the **CounterfactualHolderFactory** to handle the unique challenge of distributing "guarded" tokens that have transfer restrictions.

## The Guarded Token Problem

In Glow's guarded launch phase, tokens like GLOW and USDG have strict transfer restrictions - they can only be transferred between EOAs (Externally Owned Accounts) and specifically allowlisted contracts. Looking at the transfer restrictions in `USDG.sol` and `Glow.GuardedLaunch.sol`:

```solidity
function _update(address from, address to, uint256 value) internal override(ERC20) {
    if (permanentlyFreezeTransfers) {
        revert ErrPermanentlyFrozen();
    }
    _revertIfNotAllowlistedContract(from);
    _revertIfNotAllowlistedContract(to);
    super._update(from, to, value);
}
```

This creates a challenge: how do you distribute guarded tokens from a multisig (which is a contract) to users when contracts can't freely transfer these tokens?

## CounterfactualHolderFactory Solution

The **CounterfactualHolderFactory** solves this elegantly using CREATE2 deterministic deployments:

1. **Predictable Addresses**: It can predict the address of a contract before deploying it using CREATE2
2. **Just-in-Time Deployment**: Contracts are only deployed when needed for execution
3. **Token Holding**: Guarded tokens can be sent to these predicted addresses before the contract exists
4. **Execution**: When execution is needed, the contract is deployed and immediately executes the required transfers

This allows guarded tokens to be "held" at contract addresses without actually having contracts deployed, bypassing the transfer restrictions.

## Foundation Reward Kernel Flow

### Key Components

- **Foundation Multisig**: Posts Merkle roots for reward distributions with maximum token amounts
- **Rejection Multisig**: Comprised of veto council members who can reject bad roots within 2 weeks
- **Hot Wallet (`from` parameter)**: A more accessible wallet that holds the actual tokens for distribution

### Security Model & Separation of Concerns

1. **Foundation Multisig**: 
   - Posts reward roots with specified maximum amounts per token
        * Good safeguard around bad merkle roots.
   - Cannot directly distribute tokens
   - Controls what can be claimed, but not the actual token movement

2. **Rejection Multisig** (Veto Council Members):
   - Can reject malicious or erroneous roots within the 2-week finality period
   - Provides a safety net against foundation errors or compromise
   - Cannot post roots, only reject them

3. **Hot Wallet/Multisig**:
   - Holds the actual tokens and approves the contract to spend them
   - Specified via the `from` parameter in claims
   - Can be rotated easily since no funds are custodied in the contract itself

### Operational Flow

1. **Setup**: A larger, more secure multisig sends the appropriate amount of tokens to a hot multisig
2. **Approval**: The hot multisig approves the FoundationRewardKernel to spend tokens
3. **Root Posting**: Foundation multisig posts a Merkle root with maximum claimable amounts
4. **Safety Period**: 2-week window where rejection multisig can reject bad roots
5. **Claiming**: After finality, users can claim rewards using Merkle proofs

### Key Benefits

- **No Custodied Funds**: The contract doesn't hold tokens, making it safe to redeploy if needed
- **Flexible Hot Wallet**: The `from` parameter allows using any approved wallet for distributions
- **Guarded Token Compatible**: Works with transfer-restricted tokens via CounterfactualHolderFactory
- **Multi-layered Security**: Separation between posting, rejecting, and token holding responsibilities
- **Redeployable**: Easy to upgrade or fix since no funds are locked in the contract
