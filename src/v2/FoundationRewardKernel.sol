// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {LibBitmap} from "@solady/utils/LibBitmap.sol";
import {TransientSlot} from "./utils/TransientBytes/TransientSlot.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {CounterfactualHolderFactory} from "./CounterfactualHolderFactory.sol";
import {Call} from "./Structs.sol";

contract FoundationRewardKernel is ReentrancyGuard, Multicall {
    using LibBitmap for *;
    using TransientSlot for *;
    using SafeERC20 for *;

    error NotFoundationMultisig();
    error NotRejectionMultisig();
    error AlreadyFinalized();
    error DuplicateToken();
    error AlreadyRejected();
    error NonexistentDataAtNonce();
    error CannotPostZeroRoot();
    error NotYetFinalized();
    error InvalidMerkleProof();
    error AlreadyClaimedNonce();
    error MaxClaimedExceeded();
    error LengthsDontMatch();
    error CannotClaimFromRejectedNonce();

    uint256 public constant FINALITY = 2 weeks;

    struct RewardData {
        bytes32 merkleRoot;
        uint48 pushTimestamp;
        mapping(address token => uint256 maxAmountToSend) maxReward;
        mapping(address token => uint256 amountClaimed) amountClaimed;
        bool rejected;
    }

    struct TokenAndAmount {
        address token;
        uint256 amount;
    }

    address public immutable FOUNDATION_MULTISIG;
    address public immutable REJECTION_MULTISIG;
    CounterfactualHolderFactory public immutable CFH_FACTORY;

    uint256 public $nextPostNonce;
    mapping(address user => LibBitmap.Bitmap) internal $claimedBitmap;
    mapping(uint256 nonce => RewardData) internal $rewardData;

    event NonceRejected(uint256 indexed nonce);
    event RootPosted(uint256 indexed nonce, bytes32 indexed root, TokenAndAmount[] taa);
    event RewardClaimed(
        address indexed user,
        address indexed to,
        uint256 indexed nonce,
        address from,
        TokenAndAmount[] taa,
        bool[] isGuarded
    );

    constructor(address _foundationMultisig, address _rejectionMultisig, CounterfactualHolderFactory f) payable {
        FOUNDATION_MULTISIG = _foundationMultisig;
        REJECTION_MULTISIG = _rejectionMultisig;
        CFH_FACTORY = f;
    }

    function postPayoutRoot(bytes32 root, TokenAndAmount[] memory taa) external {
        if (msg.sender != FOUNDATION_MULTISIG) {
            revert NotFoundationMultisig();
        }
        if (root == bytes32(0)) {
            revert CannotPostZeroRoot();
        }
        uint256 nonce = $nextPostNonce++;

        RewardData storage rd = $rewardData[nonce];
        rd.merkleRoot = root;
        rd.pushTimestamp = uint48(block.timestamp);

        checkNoDuplicates(taa);
        uint256 l = taa.length;
        for (uint256 i; i < l; ++i) {
            rd.maxReward[taa[i].token] = taa[i].amount;
        }

        emit RootPosted(nonce, root, taa);
    }

    function rejectNonce(uint256 nonce) external {
        if (msg.sender != REJECTION_MULTISIG) {
            revert NotRejectionMultisig();
        }

        RewardData storage rd = $rewardData[nonce];
        if (rd.merkleRoot == bytes32(0)) {
            revert NonexistentDataAtNonce();
        }
        if (rd.rejected) revert AlreadyRejected();
        if (_isTimestampFinalized(rd.pushTimestamp)) {
            revert AlreadyFinalized();
        }

        rd.rejected = true;
        emit NonceRejected(nonce);
    }

    function claimPayout(
        uint256 nonce,
        bytes32[] calldata proof,
        TokenAndAmount[] memory taa,
        address from,
        address to,
        bool[] memory isGuardedToken
    ) external nonReentrant {
        if (isGuardedToken.length != taa.length) {
            revert LengthsDontMatch();
        }
        if ($claimedBitmap[msg.sender].get(nonce)) {
            revert AlreadyClaimedNonce();
        }
        $claimedBitmap[msg.sender].set(nonce);

        RewardData storage rd = $rewardData[nonce];
        if (rd.rejected) {
            revert CannotClaimFromRejectedNonce();
        }
        if (!_isTimestampFinalized(rd.pushTimestamp)) {
            revert NotYetFinalized();
        }
        bytes32 taaHash = keccak256(abi.encode(taa));
        bytes32 leaf = keccak256(abi.encode(msg.sender, taaHash));
        bytes32 root = rd.merkleRoot;
        if (!MerkleProofLib.verifyCalldata(proof, root, leaf)) {
            revert InvalidMerkleProof();
        }

        uint256 l = taa.length;
        for (uint256 i; i < l; ++i) {
            address token = taa[i].token;
            uint256 amt = taa[i].amount;
            uint256 newAmountClaimed = rd.amountClaimed[token] + amt;
            if (newAmountClaimed > rd.maxReward[token]) {
                revert MaxClaimedExceeded();
            }
            rd.amountClaimed[token] = newAmountClaimed;

            handleTokenTransfer(token, from, to, amt, isGuardedToken[i]);
        }

        emit RewardClaimed(msg.sender, to, nonce, from, taa, isGuardedToken);
    }

    function handleTokenTransfer(address token, address from, address to, uint256 amount, bool isGuardedToken)
        internal
    {
        if (!isGuardedToken) {
            IERC20(token).safeTransferFrom(from, to, amount);
            return;
        }
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: token, data: abi.encodeWithSelector(IERC20.transfer.selector, to, amount)});
        CFH_FACTORY.executeFrom(from, token, calls);
    }

    function checkNoDuplicates(TokenAndAmount[] memory taa) internal {
        uint256 l = taa.length;
        for (uint256 i; i < l; ++i) {
            bytes32 slot = to(taa[i].token);
            if (slot.asBoolean().tload()) {
                revert DuplicateToken();
            }
            slot.asBoolean().tstore(true);
        }

        //Clear the slots
        for (uint256 i; i < l; ++i) {
            bytes32 slot = to(taa[i].token);
            slot.asBoolean().tstore(false);
        }
    }

    function _isTimestampFinalized(uint256 ts) internal view returns (bool) {
        return block.timestamp >= ts + FINALITY;
    }

    function to(address a) internal pure returns (bytes32 s) {
        assembly {
            s := a
        }
    }
}
