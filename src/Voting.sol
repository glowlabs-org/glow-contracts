// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// contract Voting {
//     struct Voter {
//         uint weight;
//         bool voted;
//         address delegate;
//         uint vote;
//     }

//     struct Proposal {
//         uint voteCount;
//     }

//     address public chairperson;
//     uint public timeout;
//     mapping(address => Voter) public voters;
//     Proposal[] public proposals;

//     modifier onlyChairperson() {
//         require(msg.sender == chairperson, "Only chairperson can call this function.");
//         _;
//     }

//     modifier beforeTimeout() {
//         require(block.timestamp < timeout, "Voting period has ended.");
//         _;
//     }

//     constructor(uint _numProposals, uint _votingDuration) {
//         chairperson = msg.sender;
//         voters[chairperson].weight = 1;
//         timeout = block.timestamp + _votingDuration;

//         for (uint i = 0; i < _numProposals; ) {
//             proposals.push(Proposal({voteCount: 0}));
//             unchecked{++i;}
//         }
//     }

//     function giveRightToVote(address voter) public onlyChairperson beforeTimeout {
//         require(!voters[voter].voted, "The voter already voted.");
//         require(voters[voter].weight == 0, "The voter already has the right to vote.");
//         voters[voter].weight = 1;
//     }

//     function delegate(address to) public beforeTimeout {
//         Voter storage sender = voters[msg.sender];
//         require(!sender.voted, "You already voted.");
//         require(to != msg.sender, "Self-delegation is disallowed.");

//         while (voters[to].delegate != address(0)) {
//             to = voters[to].delegate;
//             require(to != msg.sender, "Found loop in delegation.");
//         }

//         sender.voted = true;
//         sender.delegate = to;
//         Voter storage delegate_ = voters[to];

//         if (delegate_.voted) {
//             proposals[delegate_.vote].voteCount += sender.weight;
//         } else {
//             delegate_.weight += sender.weight;
//         }
//     }

//     function vote(uint proposal) public beforeTimeout {
//         Voter storage sender = voters[msg.sender];
//         require(sender.weight != 0, "Has no right to vote.");
//         require(!sender.voted, "Already voted.");
//         sender.voted = true;
//         sender.vote = proposal;

//         proposals[proposal].voteCount += sender.weight;
//     }

//     function winningProposal() public view returns (uint winningProposal_) {
//         require(block.timestamp >= timeout, "Voting period has not ended yet.");
//         uint winningVoteCount = 0;
//         for (uint p = 0; p < proposals.length; p++) {
//             if (proposals[p].voteCount > winningVoteCount) {
//                 winningVoteCount = proposals[p].voteCount;
//                 winningProposal_ = p;
//             }
//         }
//     }
// }
