import {
  createUseReadContract,
  createUseWriteContract,
  createUseSimulateContract,
  createUseWatchContractEvent,
} from 'wagmi/codegen';

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MinerPoolAndGCA
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const minerPoolAndGcaAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: '_gcaAgents', internalType: 'address[]', type: 'address[]' },
      { name: '_glowToken', internalType: 'address', type: 'address' },
      { name: '_governance', internalType: 'address', type: 'address' },
      { name: '_requirementsHash', internalType: 'bytes32', type: 'bytes32' },
      { name: '_earlyLiquidity', internalType: 'address', type: 'address' },
      { name: '_usdcToken', internalType: 'address', type: 'address' },
      { name: '_vetoCouncil', internalType: 'address', type: 'address' },
      { name: '_holdingContract', internalType: 'address', type: 'address' },
      { name: '_gcc', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'payable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'CLAIM_PAYOUT_RELAY_PERMIT_TYPEHASH',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'GCC',
    outputs: [{ name: '', internalType: 'contract IGCC', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'GENESIS_TIMESTAMP',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'GLOW_REWARDS_PER_BUCKET',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'GLOW_TOKEN',
    outputs: [{ name: '', internalType: 'contract IGlow', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'GOVERNANCE',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'HOLDING_CONTRACT',
    outputs: [
      { name: '', internalType: 'contract ISafetyDelay', type: 'address' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'OFFSET_LEFT',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'OFFSET_RIGHT',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'REWARDS_PER_SECOND_FOR_ALL',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'SHARES_REQUIRED_PER_COMP_PLAN',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'TOTAL_VESTING_PERIODS',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'USDC',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'allGcas',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '', internalType: 'address', type: 'address' },
      { name: '', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'amountWithdrawnAtPaymentNonce',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'bucket',
    outputs: [
      {
        name: 'bucket',
        internalType: 'struct IGCA.Bucket',
        type: 'tuple',
        components: [
          { name: 'originalNonce', internalType: 'uint64', type: 'uint64' },
          { name: 'lastUpdatedNonce', internalType: 'uint64', type: 'uint64' },
          {
            name: 'finalizationTimestamp',
            internalType: 'uint128',
            type: 'uint128',
          },
          {
            name: 'reports',
            internalType: 'struct IGCA.Report[]',
            type: 'tuple[]',
            components: [
              { name: 'totalNewGCC', internalType: 'uint128', type: 'uint128' },
              {
                name: 'totalGLWRewardsWeight',
                internalType: 'uint64',
                type: 'uint64',
              },
              {
                name: 'totalGRCRewardsWeight',
                internalType: 'uint64',
                type: 'uint64',
              },
              { name: 'merkleRoot', internalType: 'bytes32', type: 'bytes32' },
              {
                name: 'proposingAgent',
                internalType: 'address',
                type: 'address',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'bucketId', internalType: 'uint256', type: 'uint256' },
      { name: 'user', internalType: 'address', type: 'address' },
    ],
    name: 'bucketClaimBitmap',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'bucketDelayDuration',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'bucketEndSubmissionTimestampNotReinstated',
    outputs: [{ name: '', internalType: 'uint128', type: 'uint128' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'bucketFinalizationTimestampNotReinstated',
    outputs: [{ name: '', internalType: 'uint128', type: 'uint128' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'bucketGlobalState',
    outputs: [
      {
        name: '',
        internalType: 'struct IGCA.BucketGlobalState',
        type: 'tuple',
        components: [
          { name: 'totalNewGCC', internalType: 'uint128', type: 'uint128' },
          {
            name: 'totalGLWRewardsWeight',
            internalType: 'uint64',
            type: 'uint64',
          },
          {
            name: 'totalGRCRewardsWeight',
            internalType: 'uint64',
            type: 'uint64',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'bucketStartSubmissionTimestampNotReinstated',
    outputs: [{ name: '', internalType: 'uint128', type: 'uint128' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'claimGlowFromInflation',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'user', internalType: 'address', type: 'address' },
      { name: 'paymentNonce', internalType: 'uint256', type: 'uint256' },
      {
        name: 'activeGCAsAtPaymentNonce',
        internalType: 'address[]',
        type: 'address[]',
      },
      { name: 'userIndex', internalType: 'uint256', type: 'uint256' },
      { name: 'claimFromInflation', internalType: 'bool', type: 'bool' },
      { name: 'sig', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'claimPayout',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'bucketId', internalType: 'uint256', type: 'uint256' },
      { name: 'glwWeight', internalType: 'uint256', type: 'uint256' },
      { name: 'usdcWeight', internalType: 'uint256', type: 'uint256' },
      { name: 'proof', internalType: 'bytes32[]', type: 'bytes32[]' },
      { name: 'index', internalType: 'uint256', type: 'uint256' },
      { name: 'user', internalType: 'address', type: 'address' },
      { name: 'claimFromInflation', internalType: 'bool', type: 'bool' },
      { name: 'signature', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'claimRewardFromBucket',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'bucketId', internalType: 'uint256', type: 'uint256' },
      { name: 'glwWeight', internalType: 'uint256', type: 'uint256' },
      { name: 'usdcWeight', internalType: 'uint256', type: 'uint256' },
      { name: 'index', internalType: 'uint256', type: 'uint256' },
      { name: 'claimFromInflation', internalType: 'bool', type: 'bool' },
    ],
    name: 'createClaimRewardFromBucketDigest',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'relayer', internalType: 'address', type: 'address' },
      { name: 'paymentNonce', internalType: 'uint256', type: 'uint256' },
      { name: 'relayNonce', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'createRelayDigest',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'currentBucket',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'delayBucketFinalization',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', internalType: 'uint256', type: 'uint256' }],
    name: 'donateToUSDCMinerRewardsPool',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'amount', internalType: 'uint256', type: 'uint256' }],
    name: 'donateToUSDCMinerRewardsPoolEarlyLiquidity',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'earlyLiquidity',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'eip712Domain',
    outputs: [
      { name: 'fields', internalType: 'bytes1', type: 'bytes1' },
      { name: 'name', internalType: 'string', type: 'string' },
      { name: 'version', internalType: 'string', type: 'string' },
      { name: 'chainId', internalType: 'uint256', type: 'uint256' },
      { name: 'verifyingContract', internalType: 'address', type: 'address' },
      { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
      { name: 'extensions', internalType: 'uint256[]', type: 'uint256[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'gcasToSlash', internalType: 'address[]', type: 'address[]' },
      { name: 'newGCAs', internalType: 'address[]', type: 'address[]' },
      {
        name: 'proposalCreationTimestamp',
        internalType: 'uint256',
        type: 'uint256',
      },
    ],
    name: 'executeAgainstHash',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    name: 'gcaAgents',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'gca', internalType: 'address', type: 'address' }],
    name: 'gcaPayoutData',
    outputs: [
      {
        name: '',
        internalType: 'struct IGCA.GCAPayout',
        type: 'tuple',
        components: [
          {
            name: 'lastClaimedTimestamp',
            internalType: 'uint64',
            type: 'uint64',
          },
          { name: 'maxClaimTimestamp', internalType: 'uint64', type: 'uint64' },
          {
            name: 'totalSlashableBalance',
            internalType: 'uint128',
            type: 'uint128',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getBucketTracker',
    outputs: [
      {
        name: '',
        internalType: 'struct BucketSubmission.BucketTracker',
        type: 'tuple',
        components: [
          { name: 'lastUpdatedBucket', internalType: 'uint48', type: 'uint48' },
          { name: 'maxBucketId', internalType: 'uint48', type: 'uint48' },
          {
            name: 'firstAddedBucketId',
            internalType: 'uint48',
            type: 'uint48',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'user', internalType: 'address', type: 'address' },
      { name: 'paymentNonce', internalType: 'uint256', type: 'uint256' },
      {
        name: 'activeGCAsAtPaymentNonce',
        internalType: 'address[]',
        type: 'address[]',
      },
      { name: 'userIndex', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getPayoutData',
    outputs: [
      { name: 'withdrawableAmount', internalType: 'uint256', type: 'uint256' },
      { name: 'slashableAmount', internalType: 'uint256', type: 'uint256' },
      {
        name: 'amountAlreadyWithdrawn',
        internalType: 'uint256',
        type: 'uint256',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'start', internalType: 'uint256', type: 'uint256' },
      { name: 'end', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getProposalHashes',
    outputs: [{ name: '', internalType: 'bytes32[]', type: 'bytes32[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getProposalHashes',
    outputs: [{ name: '', internalType: 'bytes32[]', type: 'bytes32[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'handleMintToCarbonCreditAuction',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'hasBucketBeenDelayed',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'bucketId', internalType: 'uint256', type: 'uint256' }],
    name: 'isBucketFinalized',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'isGCA',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'index', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'isGCA',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', internalType: 'address', type: 'address' }],
    name: 'isSlashed',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'nextProposalIndexToUpdate',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', internalType: 'address', type: 'address' }],
    name: 'nextRelayNonce',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'paymentNonce',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'nonce', internalType: 'uint256', type: 'uint256' },
      { name: 'index', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'paymentNonceToCompensationPlan',
    outputs: [{ name: '', internalType: 'uint32[5]', type: 'uint32[5]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'nonce', internalType: 'uint256', type: 'uint256' }],
    name: 'paymentNonceToShiftStartTimestamp',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'nonce', internalType: 'uint256', type: 'uint256' }],
    name: 'payoutNonceToGCAHash',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    name: 'proposalHashes',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'hash', internalType: 'bytes32', type: 'bytes32' },
      { name: 'incrementSlashNonce', internalType: 'bool', type: 'bool' },
    ],
    name: 'pushHash',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'requirementsHash',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'id', internalType: 'uint256', type: 'uint256' }],
    name: 'reward',
    outputs: [
      {
        name: '',
        internalType: 'struct BucketSubmission.WeeklyReward',
        type: 'tuple',
        components: [
          { name: 'inheritedFromLastWeek', internalType: 'bool', type: 'bool' },
          { name: 'amountInBucket', internalType: 'uint256', type: 'uint256' },
          { name: 'amountToDeduct', internalType: 'uint256', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_requirementsHash', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'setRequirementsHash',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'slashNonce',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    name: 'slashNonceToSlashTimestamp',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'plan', internalType: 'uint32[5]', type: 'uint32[5]' },
      { name: 'indexOfGCA', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'submitCompensationPlan',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'bucketId', internalType: 'uint256', type: 'uint256' },
      { name: 'totalNewGCC', internalType: 'uint256', type: 'uint256' },
      {
        name: 'totalGlwRewardsWeight',
        internalType: 'uint256',
        type: 'uint256',
      },
      {
        name: 'totalGRCRewardsWeight',
        internalType: 'uint256',
        type: 'uint256',
      },
      { name: 'root', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'submitWeeklyReport',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'bucketId', internalType: 'uint256', type: 'uint256' },
      { name: 'totalNewGCC', internalType: 'uint256', type: 'uint256' },
      {
        name: 'totalGlwRewardsWeight',
        internalType: 'uint256',
        type: 'uint256',
      },
      {
        name: 'totalGRCRewardsWeight',
        internalType: 'uint256',
        type: 'uint256',
      },
      { name: 'root', internalType: 'bytes32', type: 'bytes32' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'submitWeeklyReportWithBytes',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'bucketId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'totalAmountDonated',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'AmountDonatedToBucket',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'bucketId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      { name: 'gca', internalType: 'address', type: 'address', indexed: false },
      {
        name: 'slashNonce',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'totalNewGCC',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'totalGlwRewardsWeight',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'totalGRCRewardsWeight',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'root',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: false,
      },
      {
        name: 'extraData',
        internalType: 'bytes',
        type: 'bytes',
        indexed: false,
      },
    ],
    name: 'BucketSubmissionEvent',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'agent',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'plan',
        internalType: 'uint32[5]',
        type: 'uint32[5]',
        indexed: false,
      },
    ],
    name: 'CompensationPlanSubmitted',
  },
  { type: 'event', anonymous: false, inputs: [], name: 'EIP712DomainChanged' },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'agent',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'totalSlashableBalance',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'GCAPayoutClaimed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'slashedGcas',
        internalType: 'address[]',
        type: 'address[]',
        indexed: false,
      },
    ],
    name: 'GCAsSlashed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'newGcas',
        internalType: 'address[]',
        type: 'address[]',
        indexed: false,
      },
    ],
    name: 'NewGCAsAppointed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'proposalHash',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: false,
      },
    ],
    name: 'ProposalHashPushed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'index',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'proposalHash',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: false,
      },
    ],
    name: 'ProposalHashUpdate',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'requirementsHash',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: false,
      },
    ],
    name: 'RequirementsHashUpdated',
  },
  {
    type: 'error',
    inputs: [{ name: 'target', internalType: 'address', type: 'address' }],
    name: 'AddressEmptyCode',
  },
  {
    type: 'error',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'AddressInsufficientBalance',
  },
  { type: 'error', inputs: [], name: 'AlreadyMintedToCarbonCreditAuction' },
  { type: 'error', inputs: [], name: 'BucketAlreadyDelayed' },
  { type: 'error', inputs: [], name: 'BucketAlreadyFinalized' },
  { type: 'error', inputs: [], name: 'BucketIndexOutOfBounds' },
  { type: 'error', inputs: [], name: 'BucketNotFinalized' },
  { type: 'error', inputs: [], name: 'BucketSubmissionEnded' },
  { type: 'error', inputs: [], name: 'BucketSubmissionNotOpen' },
  { type: 'error', inputs: [], name: 'CallerNotEarlyLiquidity' },
  { type: 'error', inputs: [], name: 'CallerNotGCA' },
  { type: 'error', inputs: [], name: 'CallerNotGCAAtIndex' },
  { type: 'error', inputs: [], name: 'CallerNotGovernance' },
  { type: 'error', inputs: [], name: 'CallerNotVetoCouncilMember' },
  {
    type: 'error',
    inputs: [],
    name: 'CannotDelayBucketThatNeedsToUpdateSlashNonce',
  },
  { type: 'error', inputs: [], name: 'CannotDelayEmptyBucket' },
  { type: 'error', inputs: [], name: 'CannotSetNonceToZero' },
  {
    type: 'error',
    inputs: [],
    name: 'CompensationPlanLengthMustBeGreaterThanZero',
  },
  {
    type: 'error',
    inputs: [],
    name: 'ElectricityFutureAuctionBidMustBeGreaterThanMinimumBid',
  },
  {
    type: 'error',
    inputs: [],
    name: 'ElectricityFuturesAuctionAuthorizationTooLong',
  },
  { type: 'error', inputs: [], name: 'ElectricityFuturesAuctionBidTooLow' },
  { type: 'error', inputs: [], name: 'ElectricityFuturesAuctionEnded' },
  {
    type: 'error',
    inputs: [],
    name: 'ElectricityFuturesAuctionInvalidSignature',
  },
  { type: 'error', inputs: [], name: 'ElectricityFuturesSignatureExpired' },
  { type: 'error', inputs: [], name: 'EmptyRoot' },
  { type: 'error', inputs: [], name: 'FailedInnerCall' },
  { type: 'error', inputs: [], name: 'GCCAlreadySet' },
  { type: 'error', inputs: [], name: 'GlowWeightGreaterThanTotalWeight' },
  { type: 'error', inputs: [], name: 'GlowWeightOverflow' },
  { type: 'error', inputs: [], name: 'HashesNotUpdated' },
  { type: 'error', inputs: [], name: 'IndexDoesNotMatchNextProposalIndex' },
  { type: 'error', inputs: [], name: 'InsufficientShares' },
  { type: 'error', inputs: [], name: 'InvalidGCAHash' },
  { type: 'error', inputs: [], name: 'InvalidProof' },
  { type: 'error', inputs: [], name: 'InvalidRelaySignature' },
  { type: 'error', inputs: [], name: 'InvalidShares' },
  { type: 'error', inputs: [], name: 'InvalidShortString' },
  { type: 'error', inputs: [], name: 'InvalidUserIndex' },
  { type: 'error', inputs: [], name: 'NoBalanceToPayout' },
  { type: 'error', inputs: [], name: 'NotGCA' },
  { type: 'error', inputs: [], name: 'NotUSDCToken' },
  { type: 'error', inputs: [], name: 'ProposalAlreadyUpdated' },
  { type: 'error', inputs: [], name: 'ProposalHashDoesNotMatch' },
  { type: 'error', inputs: [], name: 'ProposalHashesEmpty' },
  { type: 'error', inputs: [], name: 'ProposalHashesNotUpdated' },
  { type: 'error', inputs: [], name: 'ReportGCCMustBeLT200Billion' },
  { type: 'error', inputs: [], name: 'ReportWeightMustBeLTUint64MaxDiv5' },
  {
    type: 'error',
    inputs: [
      { name: 'bits', internalType: 'uint8', type: 'uint8' },
      { name: 'value', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'SafeCastOverflowedUintDowncast',
  },
  {
    type: 'error',
    inputs: [{ name: 'token', internalType: 'address', type: 'address' }],
    name: 'SafeERC20FailedOperation',
  },
  { type: 'error', inputs: [], name: 'SignatureDoesNotMatchUser' },
  { type: 'error', inputs: [], name: 'SignerNotGCA' },
  { type: 'error', inputs: [], name: 'SlashedAgentCannotClaimReward' },
  {
    type: 'error',
    inputs: [{ name: 'str', internalType: 'string', type: 'string' }],
    name: 'StringTooLong',
  },
  { type: 'error', inputs: [], name: 'USDCWeightGreaterThanTotalWeight' },
  { type: 'error', inputs: [], name: 'USDCWeightOverflow' },
  { type: 'error', inputs: [], name: 'UserAlreadyClaimed' },
] as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// React
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__
 */
export const useReadMinerPoolAndGca = /*#__PURE__*/ createUseReadContract({
  abi: minerPoolAndGcaAbi,
});

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"CLAIM_PAYOUT_RELAY_PERMIT_TYPEHASH"`
 */
export const useReadMinerPoolAndGcaClaimPayoutRelayPermitTypehash =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'CLAIM_PAYOUT_RELAY_PERMIT_TYPEHASH',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"GCC"`
 */
export const useReadMinerPoolAndGcaGcc = /*#__PURE__*/ createUseReadContract({
  abi: minerPoolAndGcaAbi,
  functionName: 'GCC',
});

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"GENESIS_TIMESTAMP"`
 */
export const useReadMinerPoolAndGcaGenesisTimestamp =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'GENESIS_TIMESTAMP',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"GLOW_REWARDS_PER_BUCKET"`
 */
export const useReadMinerPoolAndGcaGlowRewardsPerBucket =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'GLOW_REWARDS_PER_BUCKET',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"GLOW_TOKEN"`
 */
export const useReadMinerPoolAndGcaGlowToken =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'GLOW_TOKEN',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"GOVERNANCE"`
 */
export const useReadMinerPoolAndGcaGovernance =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'GOVERNANCE',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"HOLDING_CONTRACT"`
 */
export const useReadMinerPoolAndGcaHoldingContract =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'HOLDING_CONTRACT',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"OFFSET_LEFT"`
 */
export const useReadMinerPoolAndGcaOffsetLeft =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'OFFSET_LEFT',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"OFFSET_RIGHT"`
 */
export const useReadMinerPoolAndGcaOffsetRight =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'OFFSET_RIGHT',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"REWARDS_PER_SECOND_FOR_ALL"`
 */
export const useReadMinerPoolAndGcaRewardsPerSecondForAll =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'REWARDS_PER_SECOND_FOR_ALL',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"SHARES_REQUIRED_PER_COMP_PLAN"`
 */
export const useReadMinerPoolAndGcaSharesRequiredPerCompPlan =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'SHARES_REQUIRED_PER_COMP_PLAN',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"TOTAL_VESTING_PERIODS"`
 */
export const useReadMinerPoolAndGcaTotalVestingPeriods =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'TOTAL_VESTING_PERIODS',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"USDC"`
 */
export const useReadMinerPoolAndGcaUsdc = /*#__PURE__*/ createUseReadContract({
  abi: minerPoolAndGcaAbi,
  functionName: 'USDC',
});

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"allGcas"`
 */
export const useReadMinerPoolAndGcaAllGcas =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'allGcas',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"amountWithdrawnAtPaymentNonce"`
 */
export const useReadMinerPoolAndGcaAmountWithdrawnAtPaymentNonce =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'amountWithdrawnAtPaymentNonce',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"bucket"`
 */
export const useReadMinerPoolAndGcaBucket = /*#__PURE__*/ createUseReadContract(
  { abi: minerPoolAndGcaAbi, functionName: 'bucket' },
);

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"bucketClaimBitmap"`
 */
export const useReadMinerPoolAndGcaBucketClaimBitmap =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'bucketClaimBitmap',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"bucketDelayDuration"`
 */
export const useReadMinerPoolAndGcaBucketDelayDuration =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'bucketDelayDuration',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"bucketEndSubmissionTimestampNotReinstated"`
 */
export const useReadMinerPoolAndGcaBucketEndSubmissionTimestampNotReinstated =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'bucketEndSubmissionTimestampNotReinstated',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"bucketFinalizationTimestampNotReinstated"`
 */
export const useReadMinerPoolAndGcaBucketFinalizationTimestampNotReinstated =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'bucketFinalizationTimestampNotReinstated',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"bucketGlobalState"`
 */
export const useReadMinerPoolAndGcaBucketGlobalState =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'bucketGlobalState',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"bucketStartSubmissionTimestampNotReinstated"`
 */
export const useReadMinerPoolAndGcaBucketStartSubmissionTimestampNotReinstated =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'bucketStartSubmissionTimestampNotReinstated',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"createClaimRewardFromBucketDigest"`
 */
export const useReadMinerPoolAndGcaCreateClaimRewardFromBucketDigest =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'createClaimRewardFromBucketDigest',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"createRelayDigest"`
 */
export const useReadMinerPoolAndGcaCreateRelayDigest =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'createRelayDigest',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"currentBucket"`
 */
export const useReadMinerPoolAndGcaCurrentBucket =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'currentBucket',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"earlyLiquidity"`
 */
export const useReadMinerPoolAndGcaEarlyLiquidity =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'earlyLiquidity',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"eip712Domain"`
 */
export const useReadMinerPoolAndGcaEip712Domain =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'eip712Domain',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"gcaAgents"`
 */
export const useReadMinerPoolAndGcaGcaAgents =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'gcaAgents',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"gcaPayoutData"`
 */
export const useReadMinerPoolAndGcaGcaPayoutData =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'gcaPayoutData',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"getBucketTracker"`
 */
export const useReadMinerPoolAndGcaGetBucketTracker =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'getBucketTracker',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"getPayoutData"`
 */
export const useReadMinerPoolAndGcaGetPayoutData =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'getPayoutData',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"getProposalHashes"`
 */
export const useReadMinerPoolAndGcaGetProposalHashes =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'getProposalHashes',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"hasBucketBeenDelayed"`
 */
export const useReadMinerPoolAndGcaHasBucketBeenDelayed =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'hasBucketBeenDelayed',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"isBucketFinalized"`
 */
export const useReadMinerPoolAndGcaIsBucketFinalized =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'isBucketFinalized',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"isGCA"`
 */
export const useReadMinerPoolAndGcaIsGca = /*#__PURE__*/ createUseReadContract({
  abi: minerPoolAndGcaAbi,
  functionName: 'isGCA',
});

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"isSlashed"`
 */
export const useReadMinerPoolAndGcaIsSlashed =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'isSlashed',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"nextProposalIndexToUpdate"`
 */
export const useReadMinerPoolAndGcaNextProposalIndexToUpdate =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'nextProposalIndexToUpdate',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"nextRelayNonce"`
 */
export const useReadMinerPoolAndGcaNextRelayNonce =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'nextRelayNonce',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"paymentNonce"`
 */
export const useReadMinerPoolAndGcaPaymentNonce =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'paymentNonce',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"paymentNonceToCompensationPlan"`
 */
export const useReadMinerPoolAndGcaPaymentNonceToCompensationPlan =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'paymentNonceToCompensationPlan',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"paymentNonceToShiftStartTimestamp"`
 */
export const useReadMinerPoolAndGcaPaymentNonceToShiftStartTimestamp =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'paymentNonceToShiftStartTimestamp',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"payoutNonceToGCAHash"`
 */
export const useReadMinerPoolAndGcaPayoutNonceToGcaHash =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'payoutNonceToGCAHash',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"proposalHashes"`
 */
export const useReadMinerPoolAndGcaProposalHashes =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'proposalHashes',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"requirementsHash"`
 */
export const useReadMinerPoolAndGcaRequirementsHash =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'requirementsHash',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"reward"`
 */
export const useReadMinerPoolAndGcaReward = /*#__PURE__*/ createUseReadContract(
  { abi: minerPoolAndGcaAbi, functionName: 'reward' },
);

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"slashNonce"`
 */
export const useReadMinerPoolAndGcaSlashNonce =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'slashNonce',
  });

/**
 * Wraps __{@link useReadContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"slashNonceToSlashTimestamp"`
 */
export const useReadMinerPoolAndGcaSlashNonceToSlashTimestamp =
  /*#__PURE__*/ createUseReadContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'slashNonceToSlashTimestamp',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__
 */
export const useWriteMinerPoolAndGca = /*#__PURE__*/ createUseWriteContract({
  abi: minerPoolAndGcaAbi,
});

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"claimGlowFromInflation"`
 */
export const useWriteMinerPoolAndGcaClaimGlowFromInflation =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'claimGlowFromInflation',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"claimPayout"`
 */
export const useWriteMinerPoolAndGcaClaimPayout =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'claimPayout',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"claimRewardFromBucket"`
 */
export const useWriteMinerPoolAndGcaClaimRewardFromBucket =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'claimRewardFromBucket',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"delayBucketFinalization"`
 */
export const useWriteMinerPoolAndGcaDelayBucketFinalization =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'delayBucketFinalization',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"donateToUSDCMinerRewardsPool"`
 */
export const useWriteMinerPoolAndGcaDonateToUsdcMinerRewardsPool =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'donateToUSDCMinerRewardsPool',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"donateToUSDCMinerRewardsPoolEarlyLiquidity"`
 */
export const useWriteMinerPoolAndGcaDonateToUsdcMinerRewardsPoolEarlyLiquidity =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'donateToUSDCMinerRewardsPoolEarlyLiquidity',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"executeAgainstHash"`
 */
export const useWriteMinerPoolAndGcaExecuteAgainstHash =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'executeAgainstHash',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"handleMintToCarbonCreditAuction"`
 */
export const useWriteMinerPoolAndGcaHandleMintToCarbonCreditAuction =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'handleMintToCarbonCreditAuction',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"pushHash"`
 */
export const useWriteMinerPoolAndGcaPushHash =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'pushHash',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"setRequirementsHash"`
 */
export const useWriteMinerPoolAndGcaSetRequirementsHash =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'setRequirementsHash',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"submitCompensationPlan"`
 */
export const useWriteMinerPoolAndGcaSubmitCompensationPlan =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'submitCompensationPlan',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"submitWeeklyReport"`
 */
export const useWriteMinerPoolAndGcaSubmitWeeklyReport =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'submitWeeklyReport',
  });

/**
 * Wraps __{@link useWriteContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"submitWeeklyReportWithBytes"`
 */
export const useWriteMinerPoolAndGcaSubmitWeeklyReportWithBytes =
  /*#__PURE__*/ createUseWriteContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'submitWeeklyReportWithBytes',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__
 */
export const useSimulateMinerPoolAndGca =
  /*#__PURE__*/ createUseSimulateContract({ abi: minerPoolAndGcaAbi });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"claimGlowFromInflation"`
 */
export const useSimulateMinerPoolAndGcaClaimGlowFromInflation =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'claimGlowFromInflation',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"claimPayout"`
 */
export const useSimulateMinerPoolAndGcaClaimPayout =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'claimPayout',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"claimRewardFromBucket"`
 */
export const useSimulateMinerPoolAndGcaClaimRewardFromBucket =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'claimRewardFromBucket',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"delayBucketFinalization"`
 */
export const useSimulateMinerPoolAndGcaDelayBucketFinalization =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'delayBucketFinalization',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"donateToUSDCMinerRewardsPool"`
 */
export const useSimulateMinerPoolAndGcaDonateToUsdcMinerRewardsPool =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'donateToUSDCMinerRewardsPool',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"donateToUSDCMinerRewardsPoolEarlyLiquidity"`
 */
export const useSimulateMinerPoolAndGcaDonateToUsdcMinerRewardsPoolEarlyLiquidity =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'donateToUSDCMinerRewardsPoolEarlyLiquidity',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"executeAgainstHash"`
 */
export const useSimulateMinerPoolAndGcaExecuteAgainstHash =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'executeAgainstHash',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"handleMintToCarbonCreditAuction"`
 */
export const useSimulateMinerPoolAndGcaHandleMintToCarbonCreditAuction =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'handleMintToCarbonCreditAuction',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"pushHash"`
 */
export const useSimulateMinerPoolAndGcaPushHash =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'pushHash',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"setRequirementsHash"`
 */
export const useSimulateMinerPoolAndGcaSetRequirementsHash =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'setRequirementsHash',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"submitCompensationPlan"`
 */
export const useSimulateMinerPoolAndGcaSubmitCompensationPlan =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'submitCompensationPlan',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"submitWeeklyReport"`
 */
export const useSimulateMinerPoolAndGcaSubmitWeeklyReport =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'submitWeeklyReport',
  });

/**
 * Wraps __{@link useSimulateContract}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `functionName` set to `"submitWeeklyReportWithBytes"`
 */
export const useSimulateMinerPoolAndGcaSubmitWeeklyReportWithBytes =
  /*#__PURE__*/ createUseSimulateContract({
    abi: minerPoolAndGcaAbi,
    functionName: 'submitWeeklyReportWithBytes',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__
 */
export const useWatchMinerPoolAndGcaEvent =
  /*#__PURE__*/ createUseWatchContractEvent({ abi: minerPoolAndGcaAbi });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"AmountDonatedToBucket"`
 */
export const useWatchMinerPoolAndGcaAmountDonatedToBucketEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'AmountDonatedToBucket',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"BucketSubmissionEvent"`
 */
export const useWatchMinerPoolAndGcaBucketSubmissionEventEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'BucketSubmissionEvent',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"CompensationPlanSubmitted"`
 */
export const useWatchMinerPoolAndGcaCompensationPlanSubmittedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'CompensationPlanSubmitted',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"EIP712DomainChanged"`
 */
export const useWatchMinerPoolAndGcaEip712DomainChangedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'EIP712DomainChanged',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"GCAPayoutClaimed"`
 */
export const useWatchMinerPoolAndGcaGcaPayoutClaimedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'GCAPayoutClaimed',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"GCAsSlashed"`
 */
export const useWatchMinerPoolAndGcaGcAsSlashedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'GCAsSlashed',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"NewGCAsAppointed"`
 */
export const useWatchMinerPoolAndGcaNewGcAsAppointedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'NewGCAsAppointed',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"ProposalHashPushed"`
 */
export const useWatchMinerPoolAndGcaProposalHashPushedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'ProposalHashPushed',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"ProposalHashUpdate"`
 */
export const useWatchMinerPoolAndGcaProposalHashUpdateEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'ProposalHashUpdate',
  });

/**
 * Wraps __{@link useWatchContractEvent}__ with `abi` set to __{@link minerPoolAndGcaAbi}__ and `eventName` set to `"RequirementsHashUpdated"`
 */
export const useWatchMinerPoolAndGcaRequirementsHashUpdatedEvent =
  /*#__PURE__*/ createUseWatchContractEvent({
    abi: minerPoolAndGcaAbi,
    eventName: 'RequirementsHashUpdated',
  });
