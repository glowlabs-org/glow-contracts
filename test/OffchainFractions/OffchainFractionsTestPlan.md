# OffchainFractions Test Plan

## Overview
Comprehensive test suite for the `OffchainFractions.sol` contract covering unit tests, fuzz tests, invariants, and edge cases.

## Contract Analysis

### Key State Variables
- `stepsPurchased`: mapping(user => mapping(creator => mapping(id => steps)))
- `_fractions`: mapping(creator => mapping(id => FractionData))
- `i_CFHFactory`: CounterfactualHolderFactory (immutable)

### Critical State Transitions
1. **Creation** → **Active** (first purchase)
2. **Active** → **MinReached** (reaches minSharesToRaise)
3. **Active** → **Expired** (block.timestamp > expiration)
4. **Active** → **ManuallyClosed** (creator calls closeFraction)
5. **MinReached** → **Completed** (soldSteps == totalSteps)
6. **Expired/Closed** → **Refunded** (users claim refunds)

### Key Functions to Test
- `createFraction()` - Creates new fraction sales
- `buyFractions()` - Purchase steps in sales
- `claimRefund()` - Claim refunds for unfilled sales
- `closeFraction()` - Manually close sales
- `getFraction()` - View function

## Unit Tests

### createFraction()
- ✅ **test_createFraction_Success**: Basic successful creation
- ✅ **test_createFraction_WithCounterfactualAddress**: Using CFH addresses
- ✅ **test_createFraction_ZeroMinShares**: No minimum requirement
- ✅ **test_createFraction_RevertAlreadyExists**: Duplicate ID prevention
- ✅ **test_createFraction_RevertInvalidToken**: Zero address token
- ✅ **test_createFraction_RevertInvalidToAddress**: Zero recipient
- ✅ **test_createFraction_RevertRecipientCannotBeSelf**: Contract as recipient
- ✅ **test_createFraction_RevertStepMustBeGreaterThanZero**: Zero step price
- ✅ **test_createFraction_RevertCannotHaveZeroTotalSteps**: Zero total steps

### buyFractions()
- ✅ **test_buyFractions_Success**: Basic purchase below minimum
- ✅ **test_buyFractions_ReachMinShares**: First time reaching minimum
- ✅ **test_buyFractions_AfterMinSharesReached**: Purchases after minimum
- ✅ **test_buyFractions_CompleteRound**: Fill entire round
- ✅ **test_buyFractions_PartialFill**: Request more than available
- ✅ **test_buyFractions_RevertZeroSteps**: Zero steps purchase
- ✅ **test_buyFractions_RevertExpired**: After expiration
- ✅ **test_buyFractions_RevertAlreadyClosed**: Manually closed
- ✅ **test_buyFractions_RevertInsufficientSharesAvailable**: minStepsToBuy > available
- ✅ **test_buyFractions_RevertTaxToken**: Tax token detection

### claimRefund()
- ✅ **test_claimRefund_ExpiredNotFilled**: Expired + below minimum
- ✅ **test_claimRefund_ManuallyClosedNotFilled**: Closed + below minimum
- ✅ **test_claimRefund_RevertNoStepsPurchased**: No purchases to refund
- ✅ **test_claimRefund_RevertRoundFullyFilled**: Above minimum threshold
- ✅ **test_claimRefund_RevertNotExpired**: Not expired and not closed

### closeFraction()
- ✅ **test_closeFraction_Success**: Basic closure
- ✅ **test_closeFraction_RevertAlreadyClosed**: Already closed
- ✅ **test_closeFraction_RevertCannotCloseFullRound**: Above minimum

### Edge Cases
- ✅ **test_multipleUsers_SameRound**: Multiple buyers
- ✅ **test_exactMinimumBoundary**: Exact minimum threshold
- ✅ **test_expirationBoundary**: Exact expiration timing
- ✅ **test_integerOverflow_Prevention**: Large number handling
- ✅ **test_reentrancy_Protection**: Reentrancy attack prevention
- ✅ **test_frontrunning_Scenarios**: MEV protection

## Fuzz Tests

### Input Validation
- ✅ **testFuzz_createFraction_ValidInputs**: Random valid parameters
- ✅ **testFuzz_buyFractions_ValidPurchases**: Random purchase amounts
- ✅ **testFuzz_refund_Scenarios**: Random refund conditions
- ✅ **testFuzz_expiration_Timing**: Random expiration times
- ✅ **testFuzz_minShares_Boundaries**: Random minimum thresholds

### Boundary Conditions
- ✅ **testFuzz_stepPrice_Extremes**: Min/max step prices
- ✅ **testFuzz_totalSteps_Extremes**: Min/max total steps
- ✅ **testFuzz_purchaseAmounts_EdgeCases**: Edge case purchase amounts

## Invariant Tests

### Financial Invariants
- ✅ **invariant_totalStepsNeverExceedAvailable**: soldSteps ≤ totalSteps
- ✅ **invariant_contractBalanceMatchesUnfulfilledPurchases**: Balance consistency
- ✅ **invariant_stepsPurchasedConsistency**: Mapping consistency
- ✅ **invariant_noTokensLocked**: No permanently locked tokens
- ✅ **invariant_minSharesLogicConsistency**: Minimum shares logic

### State Invariants
- ✅ **invariant_fractionDataIntegrity**: Struct field consistency
- ✅ **invariant_ownershipConsistency**: Creator ownership
- ✅ **invariant_expirationLogic**: Expiration enforcement

## State Transition Tests

### Lifecycle Testing
- ✅ **test_stateTransition_Creation_To_Active**: First purchase
- ✅ **test_stateTransition_Active_To_MinReached**: Reach minimum
- ✅ **test_stateTransition_Active_To_Expired**: Time expiration
- ✅ **test_stateTransition_Active_To_Closed**: Manual closure
- ✅ **test_stateTransition_MinReached_To_Completed**: Full completion
- ✅ **test_stateTransition_Expired_To_Refunded**: Refund process

### Invalid Transitions
- ✅ **test_invalidTransition_ClosedToPurchase**: Cannot buy after close
- ✅ **test_invalidTransition_ExpiredToPurchase**: Cannot buy after expiry
- ✅ **test_invalidTransition_RefundWhenFilled**: Cannot refund when filled

## Integration Tests

### CounterfactualHolderFactory Integration
- ✅ **test_integration_CounterfactualAddress**: CFH address generation
- ✅ **test_integration_CFH_FundFlow**: Funds to CFH addresses
- ✅ **test_integration_CFH_MultipleTokens**: Different tokens

### Multi-User Scenarios
- ✅ **test_integration_MultipleRounds**: Multiple fraction rounds
- ✅ **test_integration_ConcurrentPurchases**: Simultaneous purchases
- ✅ **test_integration_CrossRoundRefunds**: Refunds across rounds

## Security Tests

### Attack Vectors
- ✅ **test_security_ReentrancyAttack**: Reentrancy protection
- ✅ **test_security_IntegerOverflow**: Overflow prevention
- ✅ **test_security_IntegerUnderflow**: Underflow in refunds
- ✅ **test_security_FrontrunningProtection**: MEV resistance
- ✅ **test_security_GasGriefing**: Gas limit attacks

### Access Control
- ✅ **test_security_OnlyOwnerActions**: Creator-only functions
- ✅ **test_security_UnauthorizedClosure**: Unauthorized closures
- ✅ **test_security_RefundPermissions**: Refund permissions

## Gas Optimization Tests

### Gas Usage Analysis
- ✅ **test_gas_createFraction**: Creation gas usage
- ✅ **test_gas_buyFractions**: Purchase gas usage
- ✅ **test_gas_claimRefund**: Refund gas usage
- ✅ **test_gas_batchOperations**: Batch operation efficiency

## Error Handling Tests

### Custom Error Coverage
- ✅ All custom errors should be tested
- ✅ Error conditions should be reproducible
- ✅ Error messages should be informative

## Event Testing

### Event Emission
- ✅ **test_events_FractionCreated**: Creation events
- ✅ **test_events_FractionSold**: Purchase events
- ✅ **test_events_RoundFilled**: Completion events
- ✅ **test_events_FractionClosed**: Closure events
- ✅ **test_events_FractionRefunded**: Refund events
- ✅ **test_events_MinSharesReached**: Minimum threshold events

## Test Data & Scenarios

### Standard Test Data
```solidity
bytes32 constant FRACTION_ID = keccak256("test_fraction");
uint256 constant STEP_PRICE = 1e18;
uint256 constant TOTAL_STEPS = 100;
uint256 constant MIN_SHARES = 50;
uint48 constant EXPIRATION_TIME = uint48(block.timestamp + 7 days);
```

### Edge Case Scenarios
1. **Exact Minimum Boundary**: Purchase exactly minSharesToRaise
2. **Expiration Boundary**: Purchase at exact expiration time
3. **Maximum Values**: Test with type(uint256).max values
4. **Zero Values**: Test with zero where invalid
5. **Concurrent Operations**: Multiple users acting simultaneously

## Mock Contracts Needed
- ✅ **MockERC20**: Standard ERC20 token
- ✅ **MockTaxToken**: Token with transfer fees
- ✅ **MockReentrantToken**: Malicious reentrancy token
- ✅ **MockCounterfactualFactory**: CFH factory mock

## Test Utilities
- ✅ **Helper Functions**: Common setup patterns
- ✅ **State Assertions**: Verify contract state
- ✅ **Event Assertions**: Verify event emissions
- ✅ **Balance Tracking**: Monitor token flows

## Coverage Goals
- **Line Coverage**: >95%
- **Branch Coverage**: >90%
- **Function Coverage**: 100%
- **Statement Coverage**: >95%

## Recommended Test Execution Order
1. Unit tests (basic functionality)
2. Edge case tests (boundary conditions)
3. Integration tests (cross-contract)
4. Security tests (attack vectors)
5. Fuzz tests (random inputs)
6. Invariant tests (system properties)
7. Gas optimization tests (efficiency)

## Notes
- Use `vm.expectRevert()` for all revert tests. Make sure to include the selector.
    - You can do vm.expectRevert(Error.selector);
- Use `vm.expectEmit()` for all event tests
- Use `bound()` for fuzz test input validation
- Consider using handlers for complex invariant testing
- Mock external dependencies for isolated testing
- Test both success and failure paths
- Verify state changes after each operation
- Test with realistic and extreme parameter values
