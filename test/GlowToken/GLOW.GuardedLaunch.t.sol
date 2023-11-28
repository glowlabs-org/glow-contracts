// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import "forge-std/console.sol";
import {IGlow} from "../../src/interfaces/IGlow.sol";
import {Handler} from "./Handler.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";

contract GlowGuardedLaunchTest is Test {
    //-------------------- Mock Addresses --------------------
    address public constant SIMON = address(0x11241998);
    address public otherAccount = address(0xaafdafadfafda);
    uint256 public constant FIVE_YEARS = 365 days * 5;
    address public constant GCA = address(0x1);
    address public VETO_COUNCIL = address(0x2);
    address public constant GRANTS_TREASURY = address(0x3);
    address public constant EARLY_LIQUIDITY = address(0x4);
    address public constant VESTING_CONTRACT = address(0x5);
    address[] startingAgents = [SIMON];
    address mockGovernance = address(0x1233918293819389128);
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);
    address mockImpactCatalyst = address(0x1233918293823119389128);
    address mockHoldingContract = address(0xffffaafaeeef);
    //-------------------- Contracts --------------------
    TestGLOW public glw;
    Handler public handler;
    VetoCouncil public vetoCouncil;
    MockUSDC public usdc;
    TestUSDG public usdg;
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    //-------------------- Setup --------------------

    function setUp() public {
        //Create contracts
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));

        usdc = new MockUSDC();
        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory)
        });

        vm.startPrank(SIMON);
        glw = new TestGLOW(EARLY_LIQUIDITY,VESTING_CONTRACT,SIMON,address(usdg),address(uniswapFactory));
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
        // assertEq(glw.totalSupply(), 72_000_000 ether);
        vetoCouncil = new VetoCouncil(address(mockGovernance), address(glw),startingAgents);
        VETO_COUNCIL = address(vetoCouncil);
        //Mint some to ourselves for testing
        glw.allowlistAddress(address(handler));
        glw.mint(address(handler), 1e20 ether);

        //Set fuzzing targets
        targetSender(address(SIMON));
        targetSelector(fs);
        targetContract(address(handler));
        vm.stopPrank();

        vm.startPrank(usdgOwner);
        usdg.setAllowlistedContracts({
            _glow: address(glw),
            _gcc: address(glw), //no need for gcc here
            _holdingContract: address(mockHoldingContract),
            _vetoCouncilContract: VETO_COUNCIL,
            _impactCatalyst: mockImpactCatalyst
        });
        vm.stopPrank();
    }

    ///--------------------- MODIFIERS ---------------------

    /// @param user - the address to mint tokens to
    /// @param amount - the amount of tokens to mint to the user
    /// @dev starts prank as the user and mints tokens to the user
    ///     -   and the nends the prank
    modifier mintTokens(address user, uint256 amount) {
        vm.startPrank(user);
        glw.mint(user, amount);
        vm.stopPrank();
        _;
    }

    /// @notice stakes the entire glow balance of a user
    /// @param user - the address of the user to prank as and stake entire glow galance
    modifier stakeBalance(address user) {
        vm.startPrank(user);
        uint256 balance = glw.balanceOf(user);
        glw.stake(balance);
        vm.stopPrank();
        _;
    }

    /// @notice starts prank as user and expects a revert when we try to stake more than the user's balance
    /// @param user - the user to prank as
    modifier stakeMoreThanBalanceShouldRevert(address user) {
        vm.startPrank(user);
        uint256 balance = glw.balanceOf(user);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SIMON, 0, balance + 1));
        glw.stake(balance + 1);
        vm.stopPrank();
        _;
    }

    /// @notice ensures that the {user} has {amount} staked in the glw contract
    /// @param user - the user to check
    /// @param amount - the amount to compare the to numStaked of user
    modifier checkNumStaked(address user, uint256 amount) {
        vm.startPrank(user);
        assertEq(glw.numStaked(user), amount);
        vm.stopPrank();
        _;
    }

    /// @notice tests that staking zero tokens should revert
    modifier stakeZeroShouldRevert(address user) {
        vm.startPrank(user);
        vm.expectRevert(IGlow.CannotStakeZeroTokens.selector);
        glw.stake(0);
        vm.stopPrank();
        _;
    }

    /// @notice prans as {user} and stakes {amount} of glw
    /// @param user - the user to prank as
    /// @param amount - the amount of tokens to stake
    modifier stakeTokens(address user, uint256 amount) {
        vm.startPrank(user);
        glw.stake(amount);
        vm.stopPrank();
        _;
    }

    /// @notice unstakes {amount} of tokens as {user}
    /// @param user - the user to prank and unstake as
    /// @param amount - the amount of glw to unstake
    modifier unstakeTokens(address user, uint256 amount) {
        vm.startPrank(user);
        glw.unstake(amount);
        vm.stopPrank();
        _;
    }

    /// @notice tries to usntake  more than the number of tokens the user has staked
    /// @dev we expect this to reverts
    /// @param user - address of the user to run this test ass
    modifier unstakeMoreThanNumStakedShouldFail(address user) {
        vm.startPrank(user);
        uint256 numStaked = glw.numStaked(user);
        vm.expectRevert(IGlow.UnstakeAmountExceedsStakedBalance.selector);
        glw.unstake(numStaked + 1);
        vm.stopPrank();
        _;
    }

    modifier unstakeTokensExpectRevertMoreThanNumStaked(address user, uint256 amount) {
        vm.startPrank(user);
        vm.expectRevert(IGlow.UnstakeAmountExceedsStakedBalance.selector);
        glw.unstake(amount);
        vm.stopPrank();
        _;
    }

    function test_guarded_sendTokensToNotAllowlistedContract_shouldRevert() public {
        handler = new Handler(address(glw));
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1 ether);
        vm.expectRevert(GlowGuardedLaunch.ErrIsContract.selector);
        glw.transfer(address(handler), 1 ether);
        vm.stopPrank();
    }

    function test_freezeNetwork_notVetoCouncilMember_shouldRevert() public setInflationContracts {
        vm.expectRevert(GlowGuardedLaunch.ErrNotVetoCouncilMember.selector);
        glw.freezeContract();
    }

    function test_freezeNetwork_VetoCouncilMember_shouldWork() public setInflationContracts {
        vm.startPrank(SIMON);
        glw.freezeContract();
        vm.stopPrank();
    }

    function test_networkFrozen_tradesCannotHappen() public setInflationContracts {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1 ether);
        glw.freezeContract();
        vm.expectRevert(GlowGuardedLaunch.ErrPermanentlyFrozen.selector);
        glw.transfer(otherAccount, 1 ether);
        vm.stopPrank();
    }

    /// @dev starts prank as SIMON
    ///     -   and mints tokens to simon
    function test_guarded_Mint() public {
        uint256 amountToMint = 1e9 ether;
        vm.startPrank(SIMON);
        glw.mint(SIMON, amountToMint);
        assertEq(glw.balanceOf(SIMON), amountToMint);
    }

    function test_guarded_DoubleStake2() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 15 ether);
        assert(glw.balanceOf(SIMON) == 15 ether);

        // Stake 12, create two unstaking positions 1 + 12, wait, claim only the first 1 GLOW position
        glw.stake(13 ether);
        glw.unstake(1 ether);
        glw.unstake(12 ether);
        vm.warp(block.timestamp + FIVE_YEARS + 5 minutes);
        glw.claimUnstakedTokens(1 ether);
        assertEq(glw.balanceOf(SIMON), 3 ether); // 15 - 1 - 12 + 1
        assertEq(glw.numStaked(SIMON), 0);

        /*
    Pointers head: 1
    Pointers tail: 1
    Unstaking:
        - 1 @ t0 (claimed)
        - 12 @ t0
        */

        // !!! Restake reusing unstaking position three times
        // Each time Simon reuses the 12 unstaking GLOW for free, plus he has to spend extra 1 GLOW,
        // so he ends up with zero GLOW balance (but 39 staked GLOW)

        glw.stake(13 ether);
        vm.expectRevert();
        glw.stake(13 ether);
        vm.expectRevert();
        glw.stake(13 ether);
        // assertEq(glw.balanceOf(SIMON), 0);
        // assertEq(glw.numStaked(SIMON), 13 ether);
    }

    function testFail_DoubleStake2() public {
        address USER = vm.addr(0x13337);
        vm.startPrank(USER);
        glw.mint(USER, 15 ether);
        // Stake 12, create two unstaking positions 1 + 12, wait, claim only
        //   the first 1 GLOW position
        glw.stake(13 ether);
        glw.unstake(1 ether);
        glw.unstake(12 ether);
        vm.warp(block.timestamp + FIVE_YEARS + 5 minutes);
        glw.claimUnstakedTokens(1 ether);
        assertEq(glw.balanceOf(USER), 3 ether); // 15 - 1 - 12 + 1
        assertEq(glw.numStaked(USER), 0);
        /*
        Pointers head: 1 Pointers tail: 1 Unstaking:
          - 1 @ t0 (claimed)
        - 12 @ t0 */
        // Restake reusing unstaking position three times
        // Each time the user reuses the 12 unstaking GLOW for free, plus
        //   they have to spend extra 1 GLOW,
        // so they end up with zero GLOW balance (but 39 staked GLOW)
        glw.stake(13 ether);
        glw.stake(13 ether);
        glw.stake(13 ether);
        assertEq(glw.balanceOf(USER), 0);
        assertEq(glw.numStaked(USER), 13 ether * 3);
        /*
        Pointers head: 1 Pointers tail: 1
        Unstaking:
        - 1 @ t0 (claimed)
        - 12 @ t0
        */
        glw.unstake(13 ether * 3);
        assertEq(glw.balanceOf(USER), 0);
        assertEq(glw.numStaked(USER), 0);
        /*
        Pointers head: 2 Pointers tail: 1 Unstaking:
        - 1 @ t0 (claimed)
        - 12 @ t0
        - 39 @ t1
        */
        vm.warp(block.timestamp + FIVE_YEARS + 5 minutes);
        glw.claimUnstakedTokens(12 ether);
        // The next call will revert because GLOW does not have enough
        // balance
        vm.expectRevert();
        glw.claimUnstakedTokens(39 ether);
        // to claim their unstaking tokens
        glw.mint(address(glw), 39 ether);
        glw.claimUnstakedTokens(39 ether);
        assertEq(glw.balanceOf(USER), 39 ether + 12 ether);
    }

    //-------------------- SINGLE POSITION TESTING --------------------

    /**
     * @dev Tests that we can stake
     *     -   1. Mint 1e9 tokens to SIMON
     *     -   2. Stake the entire balance of SIMON
     *     -   3. Ensure simon is staking 1e9 tokens
     *     -   4. Ensure staking zero tokens should revert
     *     -   5. Ensure that staking more than Simon's balance should revert
     *     -   6. Mint 1e9 tokens to simon again
     *     -   7. Stake the entire balance again
     *     -   8. Make sure that simon now has 1e9 * 2 tokens
     */
    function test_guarded_NewStake()
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

    function test_guarded_stakeAndUnstake()
        public
        mintTokens(SIMON, 1e9 ether)
        stakeTokens(SIMON, 1 ether)
        checkNumStaked(SIMON, 1 ether)
        unstakeMoreThanNumStakedShouldFail(SIMON)
        unstakeTokensExpectRevertMoreThanNumStaked(SIMON, 1.1 ether)
        unstakeTokens(SIMON, 1 ether)
        checkNumStaked(SIMON, 0)
    {}

    /**
     * @dev This test is designed to test if unstaking correctly appends to a user's unstaked position
     *     -   1. Mint 1e9 tokens to SIMON
     *     -   2. Stake 1 token
     *     -   3. Ensure 1 token is staked
     *     -   4. Unstake 1 ether
     *     -   5. Ensure that SIMON has 1 unstaked dposiiton
     *     -   6a. Ensure the unstaked position's cooldown end is the unstake timestamp + 5 years
     *     -   6b. Ensure the amount inside the unstaked position is 1 token
     */
    function test_guarded_StakeAndUnstake_SinglePosition()
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

    function test_guarded_stake_withEnoughInAnUnstakedPosition_notAtPosiiton0_shouldTrigger_newHead()
        public
        mintTokens(SIMON, 1e9 ether)
        stakeTokens(SIMON, 1 ether)
        unstakeTokens(SIMON, 0.2 ether)
        unstakeTokens(SIMON, 0.2 ether)
        unstakeTokens(SIMON, 0.6 ether)
    {
        //Get pointers
        IGlow.Pointers memory pointers = glw.accountUnstakedPositionPointers(SIMON);
        assert(pointers.head == 2);
        //We should have 3 unstaked positions
        //with [.2,.2,.6]
        //Let's stake .6 and see if the head is now equal to 1
        //Since the .6 should consume everything in the most recent unstaked position
        vm.startPrank(SIMON);
        glw.stake(0.6 ether);
        pointers = glw.accountUnstakedPositionPointers(SIMON);
        assert(pointers.head == 1);
        vm.stopPrank();
    }

    function test_guarded_unstakedPositionsOfPagination_headEqualsTail_emptyPosition_shouldReturnLengthZeroArray()
        public
    {
        IGlow.UnstakedPosition[] memory unstakedPosition = glw.unstakedPositionsOf(SIMON, 0, 10);
        assert(unstakedPosition.length == 0);
    }

    function test_guarded_unstakedPositionsOfPaginations_headEqualTails_notEmptyPosition_shouldReturnLengthOneArray()
        public
        mintTokens(SIMON, 1e9 ether)
        stakeTokens(SIMON, 1 ether)
        unstakeTokens(SIMON, 1 ether)
    {
        IGlow.UnstakedPosition[] memory unstakedPosition = glw.unstakedPositionsOf(SIMON, 0, 10);
        assert(unstakedPosition.length == 1);
    }
    /**
     * @dev When users stake glow, they are allowed to pull from their unstaked positions. For example, if a user has 100 tokens in their unstaked positions,
     *         -   they can reuse those pending tokens to stake. This means that users do not need to put up fresh tokens every single time they stake.
     *         -   If users have tokens in their unstaked positions that are not yet claimed, the stake function handles the claim for the user.
     *         -   This means that if a user has 10 tokens that are ready to be claimed and wants to stake 1 token, the user will actually receive 9 tokens, (and also not have to send any tokens)
     *         -   when they go to stake that 1 token. This tests focusese on that logic.
     *
     *         -   1. Repeats all steps inside ```test_guarded_StakeAndUnstake_SinglePosition_stakingShouldClaimGLOW``` above.
     *         -   2. Fast forwards to the cooldown end of the unstaked position
     *         -       -   This means that the 1 token inside the unstaked position is ready to be claimed
     *         -   3. Perform some sanity checks
     *         -       -   a. Ensure the amount in the unstake position is still 1 token
     *         -       -   b. Ensure that we have zero tokens staked
     *         -   4. Stake .5 tokens
     *         -   5. Ensure that SIMON, RECEIVED, .5 tokens
     *         -       -   Since we are staking .5 tokens and have 1 token that is ready to be claimed
     *         -           The expected behavior is that SIMON receives .5 of that unstaked token and uses the rest to cover his new stake
     *         -   6. Ensure that unstaked positons is correctly updated and that there are now no unstaked positions left.
     */

    function test_guarded_NewStakeAndUnstake_SinglePosition_stakingShouldClaimGLOW() public {
        test_guarded_StakeAndUnstake_SinglePosition();
        vm.startPrank(SIMON);
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);

        {
            uint256 amountStakedThatIsReadyToClaim;
            for (uint256 i; i < unstakedPositions.length; i++) {
                amountStakedThatIsReadyToClaim += unstakedPositions[i].amount;
                logUnstakedPosition(i, unstakedPositions[i]);
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
        assertEq(glowBalanceAfter, glowBalanceBefore);

        uint256 numStakedAfter = glw.numStaked(SIMON);
        console.log("num staked after  = %s ", numStakedAfter);
        assertEq(glw.numStaked(SIMON), 0.5 ether);

        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        logUnstakedPosition(0, unstakedPositions[0]);

        //Length should be 1 since our first unstaked position should
        //Still have .5
        assertEq(unstakedPositions.length, 1);

        vm.stopPrank();
    }

    // //-------------------- MULTIPLE POSITIONS TESTING --------------------

    /// @dev stakes a total of 55 ether and then unstakes across 10  unstaked positions
    /// @dev each position has 1,2,3,4 ether,.....10 ether.
    modifier stageStakeAndUnstakeMultiplePositions() {
        vm.startPrank(SIMON);
        uint256 amountToMint = 1e9 ether;
        glw.mint(SIMON, amountToMint);
        glw.stake(55 ether);
        uint256 totalInUnstakePool;
        for (uint256 i; i < 10; ++i) {
            uint256 unstakeAmount = _calculateAmountToStakeForIndex(i);
            glw.unstake(unstakeAmount);
            totalInUnstakePool += unstakeAmount;
            vm.warp(block.timestamp + 5 minutes);
        }

        assert(totalInUnstakePool == 55 ether);
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 10);
        _;
    }

    /**
     * @dev This test is meant to be the same as the test above, except it tests claiming unstaked positions across multiple positions as opposed to just one. This ensures that looping is correctly happening and values are correctly being adjusted.
     *         1. Create 10 unstaked positions each with a different expiration and amount for a total of 55 tokens
     *             - Check the ```stageStakeAndUnstakeMultiplePositions``` for more information
     *         2. Fast forward to the final position's cooldown
     *         3. Ensure that SIMON has 0 staked (sanity check)
     *         4. Try staking 3 tokens
     *         5. Make sure that we receive 52 tokens
     *             -   We had a total of 55 tokens across unstaked positions and now we want to stake 3 tokens. The contract should refund us 52 tokens and keep 3 tokens to stake with
     *         6. Make sure all unstaked positions are cleared.
     */
    function test_guarded_NewStakeAndUnstakeMultiplePositions_allExpired()
        public
        stageStakeAndUnstakeMultiplePositions
    {
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        vm.warp(unstakedPositions[9].cooldownEnd + 1);

        // We staked 55 ether and unstaked 55 ether
        uint256 numStaked = glw.numStaked(SIMON);
        assertEq(numStaked, 0);

        //We also fast forwarded to the end of the last position
        //which means that those unstaked positions
        //Will be claimed in the next stake event
        uint256 balBefore = glw.balanceOf(SIMON);
        //3 ether staked, means we should not have 3 ether staked
        glw.stake(3 ether);
        assert(glw.numStaked(SIMON) == 3 ether);
        //Since we unstaked 55,
        //And we have 3 that has been restaked,
        //We should have 52 ready to be claimed?

        glw.claimUnstakedTokens(52 ether);
        uint256 balanceAfter = glw.balanceOf(SIMON);

        // console.log("balance after = ",balanceAfter);
        // console.log("balBefore = ",balBefore);

        // balAfter should be balBefore + 55 ether - 3 ether
        assertEq(balanceAfter, balBefore + 55 ether - 3 ether);

        //Unstaked positions should also be zero since we cleared it
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 0);
    }

    /**
     * @dev This test checks to see the reaction of the Glow contract when none of the unstaked positions have expired. The expected behavior is that the glow contract should pull from unstaked positions when a user goes to stake.
     *         1. Create 10 unstaked positions each with a different expiration and amount for a total of 55 tokens
     *             - Check the ```stageStakeAndUnstakeMultiplePositions``` for more information
     *         2. Stake 2.5 tokens
     *         3. Ensure that we have 2.5 tokens staked
     *         4. Pull all unstaked posiitons
     *         5. The first and second unstaked positions should have 1 token and 2 tokens respectively. By staking 2.5 tokens, we expect that the contract will use the full 1 token in the unstaked position and 1.5 of the tokens in the second unstaked position to fulfill this 2.5 token stake request. This means, we can expect the tail of the unstaked position to move up 1 (or the length of the unstaked positions to decrease by 1)
     *         6. Ensure that new array length has decreased by 1.
     *         7. Loop through the unstaked positions.
     *             -   If first position, ensure that the new amount inside that unstaked position is .5 tokens. This is because we needed to pull 1.5 tokens from the 2 tokens that existed in that unstaked position previously.
     *             - For the rest of the positions, ensure that the amounts stayed the same.
     */
    function test_guarded_StakeAndUnstakeMultiplePositions_noneExpired() public stageStakeAndUnstakeMultiplePositions {
        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        //unstakedPositions should be length 10 before starting a new stake
        assertEq(unstakedPositions.length, 10);
        //The first pos should have 1 ether
        assertEq(unstakedPositions[0].amount, 1 ether);
        //The second post should have 2 ether
        assertEq(unstakedPositions[1].amount, 2 ether);

        //The last unstaked position, should have 10 inside,
        //So now it should have 7.5
        glw.stake(2.5 ether);
        //verify that numStaked is 2.5 ether
        assertEq(glw.numStaked(SIMON), 2.5 ether);

        //Get unstaked positions after the stake
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 10);
        for (uint256 i; i < unstakedPositions.length; ++i) {
            IGlow.UnstakedPosition memory pos = unstakedPositions[i];
            //We make sure the first position now has .5 ether
            if (i == 9) {
                assertEq(pos.amount, 7.5 ether);
                continue;
            }
            // We also make sure the remaining positions were untouched
            assertEq(pos.amount, _calculateAmountToStakeForIndex(i));
        }
    }

    function test_guarded_StakeAndUnstakeMultiplePositions_useAllStakePositions()
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
        // assertEq(glw.numStaked(SIMON), 55 ether);

        //Let's mint some more
        glw.mint(SIMON, 1e4 ether);

        //Stake once more
        uint256 balBefore = glw.balanceOf(SIMON);
        glw.stake(1 ether);
        uint256 balAfter = glw.balanceOf(SIMON);
        assertEq(balAfter + 1 ether, balBefore);
        assertEq(glw.numStaked(SIMON), 56 ether);
        //We have 56 staked now,

        //Unstake .5 ether
        glw.unstake(0.5 ether);
        //We should have 55.5 staked now
        //We should now have a length of 1 in our unstaked position
        // with .5 ether in the unstaked position
        unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);
        //Our position should have .5 ether in it, since it had 1
        // and we removed .5
        assertEq(unstakedPositions[0].amount, 0.5 ether);

        //Recap: We should have 55.5 staked with .5 in an unstaked positioj
        // stake 1.5 ether now

        balBefore = glw.balanceOf(SIMON);
        glw.stake(1.5 ether);
        balAfter = glw.balanceOf(SIMON);
        //Recap: We should have 57 staked with and
        //since we had .5 in an unstaked position and staked 1.5
        //Our unstaked position should be depleted since we used it
        //To stake

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

    function test_guarded_UnstakeOver100ShouldForceCooldown() public {
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
        //Let's claim all our positions
        IGlow.UnstakedPosition[] memory positions = glw.unstakedPositionsOf(SIMON);
        {
            uint256 sumOfUnstakedPositions;
            for (uint256 i; i < positions.length; ++i) {
                sumOfUnstakedPositions += positions[i].amount;
            }
            glw.claimUnstakedTokens(sumOfUnstakedPositions);
        }
        IGlow.Pointers memory pointers = glw.accountUnstakedPositionPointers(SIMON);
        console.log("head  = ", pointers.head);
        console.log("tail  = ", pointers.tail);
        // glw.stake(0.2 ether);

        //Our length should be zero since we forwarded in time past all the cooldowns
        positions = glw.unstakedPositionsOf(SIMON);
        assertEq(positions.length, 0);

        //Now on the 100th it should revert
        for (uint256 i; i < glw.MAX_UNSTAKES_BEFORE_EMERGENCY_COOLDOWN(); ++i) {
            glw.unstake(1);
        }

        positions = glw.unstakedPositionsOf(SIMON);
        assertEq(positions.length, 100);

        //The 101th should need a cooldown
        vm.expectRevert(IGlow.UnstakingOnEmergencyCooldown.selector);
        glw.unstake(1 ether);

        //Warp Forward past the cooldown
        vm.warp(block.timestamp + glw.EMERGENCY_COOLDOWN_PERIOD());
        //After the emergency cooldown period, we should be able to unstake again
        glw.unstake(0.2 ether);
    }

    function test_guarded_ClaimZeroTokensShouldFail() public {
        vm.startPrank(SIMON);
        glw.mint(SIMON, 1e9 ether);
        glw.stake(1 ether);
        glw.unstake(1 ether);
        vm.warp(block.timestamp + FIVE_YEARS);
        vm.expectRevert(IGlow.CannotClaimZeroTokens.selector);
        glw.claimUnstakedTokens(0);
    }

    function test_guarded_ClaimTokens() public {
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

    function test_guarded_ClaimTokens_ClaimableTotalGT_Amount_NoNewTail() public {
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

        assertEq(unstakedPositions[0].amount, 0.9 ether);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    function test_guarded_ClaimTokens_ClaimableTotalGT_Amount_NewTail() public {
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

        IGlow.UnstakedPosition[] memory unstakedPositions = glw.unstakedPositionsOf(SIMON);
        assertEq(unstakedPositions.length, 1);
        assertEq(unstakedPositions[0].amount, 0.99 ether - 0.1 ether + 0.01 ether);

        //Sanity check: num staked should be zero
        assertEq(glw.numStaked(SIMON), 0);
    }

    // //-------------------- Inflation Tests --------------------

    function test_guarded_InflationShouldRevertIfContractsNotSet() public {
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

    function test_setLP_liquidityPool_shouldBeAbleToBeCreated() public {
        seedLP(1 ether, 10 * 1e6);
    }

    function test_guarded_executeSwap_glwUSDG() public {
        seedLP(1 ether, 10 * 1e6);
        uint256 amountGlow = 0.5 ether;
        vm.startPrank(usdgOwner);
        glw.mint(usdgOwner, amountGlow);
        glw.approve(address(uniswapRouter), amountGlow);
        address[] memory path = new address[](2);
        path[0] = address(glw);
        path[1] = address(usdg);
        uniswapRouter.swapExactTokensForTokens(amountGlow, 0, path, usdgOwner, block.timestamp);
        vm.stopPrank();
    }

    function test_guarded_ClaimInflationFromGCA() public setInflationContracts {
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

    function test_guarded_ClaimFromVetoCouncil() public setInflationContracts {
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

    function test_guarded_ClaimFromGrantsTreasury() public setInflationContracts {
        vm.startPrank(SIMON);
        vm.expectRevert(IGlow.CallerNotGrantsTreasury.selector);
        glw.claimGLWFromGrantsTreasury();
        vm.stopPrank();

        vm.startPrank(GRANTS_TREASURY);
        vm.warp(glw.GENESIS_TIMESTAMP());
        glw.claimGLWFromGrantsTreasury();
        //Grants treasury starts with 6 million ether
        uint256 startingBalance = 0 ether;
        assertEq(glw.balanceOf(GRANTS_TREASURY), startingBalance);

        //Should be able to pull 40,000 * 1e18 tokens in 1 week
        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        glw.claimGLWFromGrantsTreasury();
        uint256 balanceAfterFirstClaim = glw.balanceOf(GRANTS_TREASURY);
        //.00000025% rounding error caught
        assertEq(
            _fallsWithinBounds(
                balanceAfterFirstClaim, 39_999.999 ether + startingBalance, 40_000.0001 ether + startingBalance
            ),
            true
        );

        vm.warp(glw.GENESIS_TIMESTAMP() + 7 days);
        //balanceAfterSecond claim should be exactly the same as the first claim since no time has passed
        glw.claimGLWFromGrantsTreasury();
        uint256 balanceAfterSecondClaim = glw.balanceOf(GRANTS_TREASURY);
        assertEq(balanceAfterFirstClaim, balanceAfterSecondClaim);
    }

    function test_guarded_InflationGettersShouldRevertIfContractsNotSet() public {
        vm.startPrank(SIMON);
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
        vm.stopPrank();
    }

    function test_guarded_SetContractAddressesCannotBeZero() public {
        //All combinations of 0 addresses should revert
        vm.startPrank(SIMON);
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
        vm.stopPrank();
    }

    function test_guarded_SetContractAddressesCannotBeDuplicates() public {
        vm.startPrank(SIMON);
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
        vm.stopPrank();
    }

    function test_guarded_ShouldOnlyBeAbleToSetContractAddressesOnce() public {
        vm.startPrank(SIMON);
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
        vm.expectRevert(IGlow.AddressAlreadySet.selector);
        glw.setContractAddresses(GCA, VETO_COUNCIL, GRANTS_TREASURY);
        vm.stopPrank();
    }

    function test_guarded_UnstakedPositionsOf() public {
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

    function test_guarded_UnstakedPositionsOfPagination() public {
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

    function test_guarded_PaginationTailGreaterThanLengthShouldReturnEmptyArray() public {
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

    function seedLP(uint256 amountGlow, uint256 amountUSDG) public {
        vm.startPrank(usdgOwner);
        glw.mint(usdgOwner, amountGlow);
        glw.approve(address(uniswapRouter), amountGlow);
        usdc.mint(usdgOwner, amountUSDG);
        usdc.approve(address(usdg), amountUSDG);
        usdg.swap(usdgOwner, amountUSDG);
        usdg.approve(address(uniswapRouter), amountUSDG);
        uniswapRouter.addLiquidity(
            address(glw), address(usdg), amountGlow, amountUSDG, amountGlow, amountUSDG, usdgOwner, block.timestamp
        );
        vm.stopPrank();
    }
}
