// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IGovernance} from "@/interfaces/IGovernance.sol";

//TEMP!
contract Governance is IGovernance {
    uint256 private constant _PROPOSAL_DURATION = 7 * uint256(1 days) * 16;
    IGovernance.Proposal[] private _proposals;
    uint256 public lastStoredExpiredProposalId;

    /**
     * @notice Allows the GCC contract to grant nominations to {to} when they retire GCC
     * @param to the address to grant nominations to
     * @param amount the amount of nominations to grant
     */

    function grantNominations(address to, uint256 amount) external override {
        return;
    }

    /// @inheritdoc IGovernance
    function getProposalWithStatus(uint256 proposalId) public view returns (Proposal memory proposal) {
        return _proposals[proposalId];
    }

    //     function mockCreateProposal(uint proposalId,
    //     Proposal calldata proposal,
    //   uint256 latestExpiredProposalStartSearchPosition)
    // internal {

    //     //Step 1: Check if the latestExpiredProposalStartSearchPosition is a proposal that has not yet expired
    //     Proposal memory searchPositionProposal = proposals[latestExpiredProposalStartSearchPosition];
    //     if(searchPositionProposal.type == IGovernance.ProposalType.None) {
    //       revert ProposalNotInitialized(latestExpiredProposalStartSearchPosition);
    //     }
    //     // If proposal has already expired, search forwards to see if there are any more recent proposals that have expired
    //     if(block.timestamp < searchPositionProposal.expirationTimestamp) {
    //       revert ProposalHasNotExpired(proposalId);
    //     }

    //       while(true) {
    //         if(block.timestamp >= proposals[++latestExpiredProposalStartSearchPosition]) {
    //           continue;
    //         } else {
    //           --latestExpiredProposalStartSearchPosition;
    //           break;
    //         }
    //       }

    //     uint256 totalActiveProposals = (proposals.length) - latestExpiredProposalStartSearchPosition;
    //     uint256 totalActiveProposals = (11 * 1e17) ** totalActiveProposals;
    //     //spend nominations .....
    //     //update state if necessary
    //     if(latestExpiredProposalId != latestExpiredProposalStartSearchPosition) {
    //     lastStoredExpiredProposalId = latestExpiredProposalStartSearchPosition;
    //       }
    //     //push proposal to storage
    //     proposals.push(proposal);
    //     //emit events....
    //   }
}
