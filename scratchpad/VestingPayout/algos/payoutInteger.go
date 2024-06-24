// package main

// import "fmt"

// const VESTING_PERIOD = uint64(100 * (86400 * 7))

// // fullRange performs the full computation to determine how much a worker is owed for one salary amount.
// // The inputs are:
// //  1. what the salary was (weekylSalary)
// //  2. how long the salary was in effect (secondsActive)
// //  3. how long ago the salary stopped being in effect (secondsStopped)
// //
// // note that if a worker receives a salary for 1 week, then tries to withdraw the balance 208 seconds later,
// // you would call this function with the values `fullRange(salary, 1, 208)`.
// //
// // For the full computation, we first determine how many fully vested seconds there are, then we determine
// // how many partially vested seconds there are, finally we determine how far along the partially vested seconds
// // are. For the case of one weekly salary, this function handles all edge cases.
// func fullRangeInteger(rewardsPerSecond uint64, secondsActive uint64, secondsStopped uint64) (withdraw uint64, slash uint64) {
// 	// Determine the number of fully vested seconds.
// 	fullyVestedSeconds := uint64(0)
// 	if secondsActive+secondsStopped > VESTING_PERIOD {
// 		fullyVestedSeconds = secondsActive + secondsStopped - VESTING_PERIOD
// 	}
// 	if fullyVestedSeconds > secondsActive {
// 		fullyVestedSeconds = secondsActive
// 	}

// 	fullyVestedSecondsValue := fullyVestedSeconds * rewardsPerSecond

// 	// Determine the number of partially vested seconds.
// 	partiallyVestedseconds := secondsActive - fullyVestedSeconds

// 	// Determine the amount of vesting that has happened for the lowest value partially
// 	// vested week and the highest value partially vested week, then use those to compute
// 	// the arithmetic sequence to determine the payout.
// 	lowestValueSecond := (1 + secondsStopped) * rewardsPerSecond / VESTING_PERIOD
// 	highestValueSecond := (secondsActive + secondsStopped) * rewardsPerSecond / VESTING_PERIOD
// 	if highestValueSecond > rewardsPerSecond {
// 		highestValueSecond = rewardsPerSecond
// 	}
// 	partiallyVestedsecondsValue := partiallyVestedseconds * (lowestValueSecond + highestValueSecond) / 2

// 	// Compute the final values
// 	totalBalance := secondsActive * rewardsPerSecond
// 	fmt.Printf("totalBalance: %d\n", totalBalance)
// 	vestedBalance := fullyVestedSecondsValue + partiallyVestedsecondsValue
// 	slashBalance := totalBalance - vestedBalance
// 	return vestedBalance, slashBalance
// }

// func weeksInSeconds(weeks float64) (seconds uint64) {
// 	secondsInAWeek := uint64(86400 * 7)
// 	return uint64(weeks * float64(secondsInAWeek))
// }

// func main() {

// 	fmt.Printf("Using 'full range'\n")
// 	seconds := weeksInSeconds(.2)
// 	fmt.Printf("Seconds: %d\n", seconds)
// 	withdraw, slash := fullRangeInteger(16534391534391534, seconds, 0)
// 	fmt.Printf("Withdraw: %d, Slash: %d\n", withdraw, slash)

// }
