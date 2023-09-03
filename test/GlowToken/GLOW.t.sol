// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/testing/TestGLOW.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
import {Handler} from "./Handler.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract GlowTest is Test {
    //-------------------- Mock Addresses --------------------
    address public constant SIMON = address(0x11241998);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    address public constant VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);

    //-------------------- Contracts --------------------
    TestGLOW public glw;
    Handler public handler;

    //-------------------- Setup --------------------
    function setUp() public {
        //Create contracts
        glw = new TestGLOW(EARLY_LIQUIDITY,VESTING_CONTRACT);
        handler = new Handler(address(glw));

        //Make sure early liquidity receives 12 million tokens
        assertEq(glw.balanceOf(EARLY_LIQUIDITY), 12_000_000 ether);

        //Set fuzzing selectors
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.stake.selector;
        selectors[1] = Handler.unstake.selector;
        selectors[2] = Handler.claimUnstakedTokens.selector;
        FuzzSelector memory fs = FuzzSelector({addr: address(handler), selectors: selectors});

        //Ensure total supply when constructed is 72_000_000 ether
        assertEq(glw.totalSupply(), 72_000_000 ether);

        //Mint some to ourselves for testing
        glw.mint(address(handler), 1e20 ether);

        //Set fuzzing targets
        targetSender(address(SIMON));
        targetSelector(fs);
        targetContract(address(handler));
    }

    ///--------------------- MODIFIERS ---------------------

    modifier mintTokens(address user, uint256 amount) {
        vm.startPrank(user);
        glw.mint(user, amount);
        vm.stopPrank();
        _;
    }

    modifier stakeBalance(address user) {
        vm.startPrank(user);
        uint256 balance = glw.balanceOf(user);
        glw.stake(balance);
        vm.stopPrank();
        _;
    }

    modifier stakeMoreThanBalanceShouldRevert(address user) {
        vm.startPrank(user);
        uint256 balance = glw.balanceOf(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SIMON, 0, balance + 1));
        glw.stake(balance + 1);
        vm.stopPrank();
        _;
    }

    modifier checkNumStaked(address user, uint256 amount) {
        vm.startPrank(user);
        assertEq(glw.numStaked(user), amount);
        vm.stopPrank();
        _;
    }

    modifier stakeZeroShouldRevert(address user) {
        vm.startPrank(user);
        vm.expectRevert(IGlow.CannotStakeZeroTokens.selector);
        glw.stake(0);
        vm.stopPrank();
        _;
    }

    modifier stakeTokens(address user, uint256 amount) {
        vm.startPrank(user);
        glw.stake(amount);
        vm.stopPrank();
        _;
    }

    modifier unstakeTokens(address user, uint256 amount) {
        vm.startPrank(user);
        glw.unstake(amount);
        vm.stopPrank();
        _;
    }

    modifier unstakeMoreThanNumStakedShouldFail(address user) {
        vm.startPrank(user);
        uint256 numStaked = glw.numStaked(user);
        vm.expectRevert(IGlow.UnstakeAmountExceedsStakedBalance.selector);
        glw.unstake(numStaked + 1);
        vm.stopPrank();
        _;
    }

    function test_Mint() public {
        uint256 amountToMint = 1e9 ether;
        vm.startPrank(SIMON);
        glw.mint(SIMON, amountToMint);
        assertEq(glw.balanceOf(SIMON), amountToMint);
    }

    //-------------------- SINGLE POSITION TESTING --------------------

    /**
     * @dev Tests that we can stake
     */
    function test_Stake()
        public
        mintTokens(SIMON, 1e9 ether)
        stakeBalance(SIMON)
        checkNumStaked(SIMON, 1e9 ether)
        stakeZeroShouldRevert(SIMON)
        stakeMoreThanBalanceShouldRevert(SIMON)
        mintTokens(SIMON, 1e9 ether)
        stakeBalance(SIMON)
        checkNumStaked(SIMON, 1e9 ether * 2)
    {}

    function test_stakeAndUnstake()
        public
        mintTokens(SIMON, 1e9 ether)
        stakeTokens(SIMON, 1 ether)
        checkNumStaked(SIMON, 1 ether)
        unstakeMoreThanNumStakedShouldFail(SIMON)
        unstakeTokens(SIMON, 1 ether)
        checkNumStaked(SIMON, 0)
    {}

    function test_StakeAndUnstake_SinglePosition()
        public
        mintTokens(SIMON, 1e9 ether)
        stakeTokens(SIMON, 1 ether)
        checkNumStaked(SIMON, 1 ether)
    {
        vm.startPrank(SIMON);
        //Record timestamp to compare later
        uint256 unstakeBlockTimestamp = block.timestamp;
        glw.unstake(1 ether);

        //Get Allow Positions
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            //Make sure the cooldown is 5 years from now and that the amount is 1 ether
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            assertEq(pos.cooldownEnd, unstakeBlockTimestamp + FIVE_YEARS);
            assertEq(pos.amount, 1 ether);
        }
        vm.stopPrank();
    }

    function test_StakeAndUnstake_SinglePosition_stakingShouldClaimGLOW() public {
        test_StakeAndUnstake_SinglePosition();
        vm.startPrank(SIMON);
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);

        {
            uint256 amountStakedThatIsReadyToClaim;
            for (uint256 i; i < unstakedPositions.length; i++) {
                amountStakedThatIsReadyToClaim += unstakedPositions[i].amount;
            }

            assertEq(amountStakedThatIsReadyToClaim, 1 ether);
            vm.warp(unstakedPositions[0].cooldownEnd + 1);
        }

        uint256 numStakedBefore = (glw.numStaked(SIMON));
        assertEq(numStakedBefore, 0);

        uint256 glowBalanceBefore = glw.balanceOf(SIMON);
        glw.stake(0.5 ether);

        uint256 glowBalanceAfter = glw.balanceOf(SIMON);
        //The balanace after staking should actually be .5 greater
        //since the first position had to be claimed
        assertEq(glowBalanceAfter, glowBalanceBefore + 0.5 ether);

        uint256 numStakedAfter = glw.numStaked(SIMON);
        console.log("num staked after  = %s ", numStakedAfter);
        assertEq(glw.numStaked(SIMON), 0.5 ether);

        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        //The unstakked positions length should be 0 since our
        //Unstaked position's cooldown ended
        assertEq(unstakedPositions.length, 0);

        vm.stopPrank();
    }

    //-------------------- MULTIPLE POSITIONS TESTING --------------------

    /// @dev stakes a total of 55 ether and then unstakes across 10  unstaked positions
    /// @dev each position has 1,2,3,4 ether,.....10 ether.
    modifier stageStakeAndUnstakeMultiplePositions() {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }

        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 10);
        _;
    }

    function test_StakeAndUnstakeMultiplePositions_allExpired() public stageStakeAndUnstakeMultiplePositions {
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        vm.warp(unstakedPositions[9].cooldownEnd + 1);

        //We staked 55 ether and unstaked 55 ether
        uint256 numStaked = glw.numStaked(SIMON);
        assertEq(numStaked, 0);

        //We also fast forwarded to the end of the last position
        //which means that those unstaked positions
        //Will be claimed in the next stake event

        uint256 balBefore = glw.balanceOf(SIMON);
        glw.stake(3 ether);
        uint256 balanceAfter = glw.balanceOf(SIMON);

        //balAfter should be balBefore + 55 ether - 3 ether
        assertEq(balanceAfter, balBefore + 55 ether - 3 ether);

        //Unstaked positions should also be zero since we cleared it

        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 0);
    }

    function test_StakeAndUnstakeMultiplePositions_noneExpired() public stageStakeAndUnstakeMultiplePositions {
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        //unstakedPositions should be length 10 before starting a new stake
        assertEq(unstakedPositions.length, 10);
        //The first pos should have 1 ether
        assertEq(unstakedPositions[0].amount, 1 ether);
        //The second post should have 2 ether
        assertEq(unstakedPositions[1].amount, 2 ether);

        glw.stake(2.5 ether);
        //verify that numStaked is 2.5 ether
        assertEq(glw.numStaked(SIMON), 2.5 ether);

        //Get unstaked positions after the stake
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        /*
         -  The length should be 9 now since staking draws from the unstaked positions if they have yet to expire.
                - The first position had 1 ether and the second had 2 ether
                - Position 0 (first position) should be completely gone
                - and our position 1 (second position) should have .5 ether left in it
                - (1 ether + 2 ether - 2.5 ether) = .5 ether
        */
        assertEq(unstakedPositions.length, 9);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            //We make sure the first position now has .5 ether
            if (i == 0) {
                assertEq(pos.amount, 0.5 ether);
                continue;
            }
            //We also make sure the remaining positions were untuched
            assertEq(pos.amount, _calculateAmountToStakeForIndex(i + 1));
        }
    }

    function test_StakeAndUnstakeMultiplePositions_oneExpired() public stageStakeAndUnstakeMultiplePositions {
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        // unstakedPositions should be length 10 before starting a new stake
        assertEq(unstakedPositions.length, 10);

        //Warp to the end of the first bucket
        //This means we should have 1 ether that is ready to claim
        //and we should have 54 ether that is still on cooldown
        vm.warp(unstakedPositions[0].cooldownEnd + 1);

        uint256 balBefore = glw.balanceOf(SIMON);
        // We are testing to make sure that the length of unstaked position will
        // be equal to 0 and that we indeed had to transfer zero tokens
        glw.stake(55 ether);
        unstakedPositions = glw.unstakedPositionsOf(SIMON);

        uint256 balAfter = glw.balanceOf(SIMON);

        //Make sure the balances are equal
        assertEq(balBefore, balAfter);
        //since we staked a total of 55 ether, the new length should be 0
        assertEq(unstakedPositions.length, 0);
    }

    function test_StakeAndUnstakeMultiplePositions_useAllStakePositions()
        public
        stageStakeAndUnstakeMultiplePositions
    {
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        //unstakedPositions should be length 10 before starting a new stake
        assertEq(unstakedPositions.length, 10);

        uint256 balBeforeStaking55 = glw.balanceOf(SIMON);
        glw.stake(55 ether);
        uint256 balAfterStaking55 = glw.balanceOf(SIMON);
        //since thet total amount in our unstaked positions is 55 ether, we should have used all
        // those positiosn and now have a length of 0 and the same balance as before
        assertEq(balBeforeStaking55, balAfterStaking55);
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 0);
        assertEq(glw.numStaked(SIMON), 55 ether);

        //Let's mint some more
        glw.mint(SIMON, 1e4 ether);

        //Stake once more
        glw.stake(1 ether);
        assertEq(glw.numStaked(SIMON), 56 ether);

        //Unstake .5 ether
        glw.unstake(0.5 ether);
        //We should now have a length of 1 in our unstaked position
        // with .5 ether in the unstaked position
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);
        assertEq(unstakedPositions[0].amount, 0.5 ether);

        // stake 1.5 ether now
        uint256 balBefore = glw.balanceOf(SIMON);
        glw.stake(1.5 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        //Sanity check to make sure we actually transferred 1 ether of tokens
        //since our unstaked position has .5 ether,
        //we only need to transfer 1 ether since staking can pull from unstaked positions
        assertEq(balAfter, balBefore - 1 ether);

        //make sure we have a total of 57 ether staked
        assertEq(glw.numStaked(SIMON), 57 ether);

        //The length should be 0 since we should have nothing in our unstaked positions since we restaked
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 0);
    }

    function test_UnstakeOver100ShouldForceCooldown() public {
        //make sure we don't start at timestamp 0
        vm.warp(glw.EMERGENCY_COOLDOWN_PERIOD() * 12345);
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(amountToMint);

        //Unstake MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN times
        // This should go through perfectly
        for (uint256 i; i < glw.MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN(); ++i) {
            glw.unstake(1 ether);
        }

        //Anything past the max unstakes should revert until we've passed the cooldown period
        vm.expectRevert(IGlow.UnstakingOnEmergencyCooldown.selector);
        glw.unstake(1 ether);

        //Warp Forward past the cooldown
        vm.warp(block.timestamp + glw.EMERGENCY_COOLDOWN_PERIOD());
        //After the emergency cooldown period, we should be able to unstake again
        glw.unstake(0.2 ether);

        //Forward 10 years
        vm.warp(block.timestamp + 365 * 10 * 1 days);
        glw.stake(0.2 ether);

        //Our length should be zero since we forwarded in time past all the cooldowns
        uint256 len = glw.unstakedPositionsOf(SIMON).length;
        assertEq(len, 0);

        //Now on the 100th it should revert
        for (uint256 i; i < glw.MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN(); ++i) {
            glw.unstake(1 ether);
        }

        len = glw.unstakedPositionsOf(SIMON).length;
        assertEq(len, 100);

        //The 101th should need a cooldown
        vm.expectRevert(IGlow.UnstakingOnEmergencyCooldown.selector);
        glw.unstake(1 ether);

        //Warp Forward past the cooldown
        vm.warp(block.timestamp + glw.EMERGENCY_COOLDOWN_PERIOD());
        //After the emergency cooldown period, we should be able to unstake again
        glw.unstake(0.2 ether);
    }

    function test_ClaimZeroTokensShouldFail() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        glw.unstake(1 ether);
        vm.warp(block.timestamp + FIVE_YEARS);
        vm.expectRevert(IGlow.CannotClaimZeroTokens.selector);
        glw.claimUnstakedTokens(0);
    }

    function test_ClaimTokens() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        glw.unstake(1 ether);
        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(1 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 1 ether);

        assertEq(glwBalAfter, glwBalBefore - 1 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 0);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    function test_ClaimTokens_ClaimableTotalGT_Amount_NoNewTail() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        glw.unstake(1 ether);
        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(0.1 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(0.1 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 0.1 ether);

        assertEq(glwBalAfter, glwBalBefore - 0.1 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    function test_ClaimTokens_ClaimableTotalGT_Amount_NewTail() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        //Create 2 staked positions
        glw.unstake(0.01 ether);
        glw.unstake(0.99 ether);

        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1.1 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(0.1 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 0.1 ether);

        assertEq(glwBalAfter, glwBalBefore - 0.1 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    function test_ClaimPartialFill() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(1 ether);

        glw.unstake(1 ether);
        vm.warp(block.timestamp + 5 minutes);
        //should revert since we need to wait 5 years
        vm.expectRevert(IGlow.InsufficientClaimableBalance.selector);
        glw.claimUnstakedTokens(0.5 ether);

        vm.warp(block.timestamp + FIVE_YEARS);
        uint256 balBefore = glw.balanceOf(SIMON);
        uint256 glwBalBefore = glw.balanceOf(address(glw));
        glw.claimUnstakedTokens(0.5 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        uint256 glwBalAfter = glw.balanceOf(address(glw));
        assertEq(balAfter, balBefore + 0.5 ether);

        assertEq(glwBalAfter, glwBalBefore - 0.5 ether);

        //Our unstaked positions should be empty now
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);
        //Should have .5 ether
        assertEq(unstakedPositions[0].amount, 0.5 ether);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    //-------------------- Inflation Tests --------------------

    function test_InflationShouldRevertIfContractsNotSet() public {
        vm.expectRevert(IGlow.AddressNotSet.selector);
        glw.claimGLWFromGCAAndMinerPool();
        vm.expectRevert(IGlow.AddressNotSet.selector);
        glw.claimGLWFromVetoCouncil();
        vm.expectRevert(IGlow.AddressNotSet.selector);
        glw.claimGLWFromGrantsTreasury();
    }

    modifier setInflationContracts() {
        vm.startPrank(SIMON);
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
        vm.stopPrank();
        _;
    }

    function test_ClaimInflationFromGCA() public setInflationContracts {
        vm.startPrank(SIMON);

        vm.expectRevert(IGlow.CallerNotGCA.selector);
        glw.claimGLWFromGCAAndMinerPool();
        //Sanity Check to make sure GCA has 0 balance
        vm.stopPrank();

        vm.startPrank(GCA);
        vm.warp(glw.GENESIS_TIMESTAMP());
        glw.claimGLWFromGCAAndMinerPool();
        assertEq(glw.balanceOf(GCA), 0);

        //Should be able to pull 185,000 * 1e18 tokens in 1 week
        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        glw.claimGLWFromGCAAndMinerPool();
        uint256 balanceAfterFirstClaim = glw.balanceOf(GCA);
        //.00000005% rounding error caught
        assertEq(_fallsWithinBounds(balanceAfterFirstClaim, 184_999.999 ether, 185_000.001 ether), true);

        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        //balanceAfterSecond claim should be exactly the same as the first claim since no time has passed
        glw.claimGLWFromGCAAndMinerPool();
        uint256 balanceAfterSecondClaim = glw.balanceOf(GCA);
        assertEq(balanceAfterFirstClaim, balanceAfterSecondClaim);
    }

    function test_ClaimFromVetoCouncil() public setInflationContracts {
        vm.startPrank(SIMON);
        vm.expectRevert(IGlow.CallerNotVetoCouncil.selector);
        glw.claimGLWFromVetoCouncil();
        vm.stopPrank();

        vm.startPrank(VETO_COUNCIL);
        vm.warp(glw.GENESIS_TIMESTAMP());
        glw.claimGLWFromVetoCouncil();
        assertEq(glw.balanceOf(VETO_COUNCIL), 0);

        //Should be able to pull 5,000 * 1e18 tokens in 1 week
        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        glw.claimGLWFromVetoCouncil();
        uint256 balanceAfterFirstClaim = glw.balanceOf(VETO_COUNCIL);
        //.0.00000002% rounding error caught
        assertEq(_fallsWithinBounds(balanceAfterFirstClaim, 4_999.9999 ether, 5_000.0001 ether), true);

        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        //balanceAfterSecond claim should be exactly the same as the first claim since no time has passed
        glw.claimGLWFromVetoCouncil();
        uint256 balanceAfterSecondClaim = glw.balanceOf(VETO_COUNCIL);
        assertEq(balanceAfterFirstClaim, balanceAfterSecondClaim);
    }

    function test_ClaimFromGrantsTreasury() public setInflationContracts {
        vm.startPrank(SIMON);
        vm.expectRevert(IGlow.CallerNotGrantsTreasury.selector);
        glw.claimGLWFromGrantsTreasury();
        vm.stopPrank();

        vm.startPrank(GRANTS_TREASURY);
        vm.warp(glw.GENESIS_TIMESTAMP());
        glw.claimGLWFromGrantsTreasury();
        assertEq(glw.balanceOf(GRANTS_TREASURY), 0);

        //Should be able to pull 40,000 * 1e18 tokens in 1 week
        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        glw.claimGLWFromGrantsTreasury();
        uint256 balanceAfterFirstClaim = glw.balanceOf(GRANTS_TREASURY);
        //.00000025% rounding error caught
        assertEq(_fallsWithinBounds(balanceAfterFirstClaim, 39_999.999 ether, 40_000.0001 ether), true);

        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        //balanceAfterSecond claim should be exactly the same as the first claim since no time has passed
        glw.claimGLWFromGrantsTreasury();
        uint256 balanceAfterSecondClaim = glw.balanceOf(GRANTS_TREASURY);
        assertEq(balanceAfterFirstClaim, balanceAfterSecondClaim);
    }

    function test_InflationGettersShouldRevertIfContractsNotSet() public {
        vm.expectRevert(IGlow.AddressNotSet.selector);
        (uint256 a, uint256 b, uint256 c) = glw.gcaInflationData();

        vm.expectRevert(IGlow.AddressNotSet.selector);
        (a, b, c) = glw.vetoCouncilInflationData();

        vm.expectRevert(IGlow.AddressNotSet.selector);
        (a, b, c) = glw.grantsTreasuryInflationData();

        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);

        //Should now work
        (a, b, c) = glw.gcaInflationData();
        (a, b, c) = glw.vetoCouncilInflationData();
        (a, b, c) = glw.grantsTreasuryInflationData();
    }

    function test_SetContractAddressesCannotBeZero() public {
        //All combinations of 0 addresses should revert
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(0), a(0));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(0), a(1));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(1), a(0));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(1), a(0), a(0));

        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(0), a(1), a(2));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(1), a(0), a(2));
        vm.expectRevert(IGlow.ZeroAddressNotAllowed.selector);
        glw.setContractAddresses(a(1), a(2), a(0));
    }

    function test_SetContractAddressesCannotBeDuplicates() public {
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, VETO_COUNCIL, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, VETO_COUNCIL, GRANTS_TREASURY);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, GRANTS_TREASURY, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(VETO_COUNCIL, GRANTS_TREASURY, GRANTS_TREASURY);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, VETO_COUNCIL, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, VETO_COUNCIL, GRANTS_TREASURY);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, GRANTS_TREASURY, VETO_COUNCIL);
        vm.expectRevert(IGlow.DuplicateAddressNotAllowed.selector);
        glw.setContractAddresses(GRANTS_TREASURY, GRANTS_TREASURY, GRANTS_TREASURY);
    }

    function test_ShouldOnlyBeAbleToSetContractAddressesOnce() public {
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
        vm.expectRevert(IGlow.AddressAlreadySet.selector);
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
    }

    function test_UnstakedPositionsOf() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }
        //Should have 10 unstaked positions and my tail should be 0
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 10);

        //let's make sure all the values are correct
        for (uint256 i; i < 10; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i));
        }
        //Let's fast forward 5 years to claim some positions which should update the tail
        vm.warp(block.timestamp + 365 days * 5);

        //This should pop the first position (move the tail by 1)
        uint256 amountToUnstake = _calculateAmountToStakeForIndex(0);
        glw.claimUnstakedTokens(amountToUnstake);

        //Now if we query we should only get 9 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 9);

        //assert that the values are correct ,
        //we should have 9 positions and the first position should be _calculateAmountToStakeForIndex(1)
        for (uint256 i; i < 9; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 1));
        }

        //Let's pop 2 positions
        uint256 amountToPop2 = _calculateAmountToStakeForIndex(1) + _calculateAmountToStakeForIndex(2);
        glw.claimUnstakedTokens(amountToPop2);

        //Now if we query we should only get 7 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 7);

        //assert that the values are correct ,
        //we should have 7 positions and the first position should be _calculateAmountToStakeForIndex(3)
        for (uint256 i; i < 7; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 3));
        }
    }

    function test_UnstakedPositionsOfPagination() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }
        //Should have 10 unstaked positions and my tail should be 0
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 10);

        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 10);
        assertEq(unstakedPositions.length, 10);

        //Sanity check to make sure we can correclty paginate
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 5);
        assertEq(unstakedPositions.length, 5);

        //Let's check the pagination results to make sure they're consistent
        for (uint256 i; i < 5; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i));
        }

        //Let's get 5,10
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 5, 10);
        assertEq(unstakedPositions.length, 5);
        for (uint256 i; i < 5; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 5));
        }

        //if we try to get more than 10 we should get only 10
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 11);
        assertEq(unstakedPositions.length, 10);

        //Let's fast forward 5 years to claim some positions which should update the tail
        vm.warp(block.timestamp + 365 days * 5);

        uint256 amountToUnstake = _calculateAmountToStakeForIndex(0);
        glw.claimUnstakedTokens(amountToUnstake);

        //Now if we query 0,10 we should only get 9 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 10);
        assertEq(unstakedPositions.length, 9);

        //assert that the values are correct ,
        //we should have 9 positions and the first position should be _calculateAmountToStakeForIndex(1)
        for (uint256 i; i < 9; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 1));
        }

        //Let's unclaim 2
        uint256 amountToPop2 = _calculateAmountToStakeForIndex(1) + _calculateAmountToStakeForIndex(2);
        glw.claimUnstakedTokens(amountToPop2);

        //Now if we query 0,10 we should only get 7 positions
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 10);

        //assert that the values are correct ,
        //we should have 7 positions and the first position should be _calculateAmountToStakeForIndex(3)
        assertEq(unstakedPositions.length, 7);
        for (uint256 i; i < 7; ++i) {
            assertEq(unstakedPositions[i].amount, _calculateAmountToStakeForIndex(i + 3));
        }

        //Let's query 0,7 to make sure we get the same results
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 0, 7);
        assertEq(unstakedPositions.length, 7);
    }

    function test_PaginationTailGreaterThanLengthShouldReturnEmptyArray() public {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        for (uint256 i; i < 10; ++i) {
            glw.unstake(_calculateAmountToStakeForIndex(i));
            vm.warp(block.timestamp + 5 minutes);
        }

        // start should be > than length case 0
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON, 11, 12);
        assertEq(unstakedPositions.length, 0);

        //start should be == length, case 1
        unstakedPositions = glw.unstakedPositionsOf(SIMON, 10, 12);
        assertEq(unstakedPositions.length, 0);
    }

    //-------------------- Helpers --------------------
    function _fallsWithinBounds(uint256 actual, uint256 lowerBound, uint256 upperBound) internal pure returns (bool) {
        return actual >= lowerBound && actual <= upperBound;
    }

    function a(uint256 a) internal pure returns (address) {
        return address(uint160(a));
    }

    function _calculateAmountToStakeForIndex(uint256 index) internal pure returns (uint256) {
        return (index + 1) * 1 ether;
    }

    function logUnstakedPosition(uint256 id, IGlow.UnstakedPosition memory pos) internal {
        console.logString("-------------------------------");
        console.log("id = ", id);
        console.log("timestamp expiration", pos.cooldownEnd);
        console.log("amount in unstake pool", pos.amount);
        console.logString("-------------------------------");
    }
}
