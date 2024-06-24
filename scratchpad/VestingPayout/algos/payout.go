// package main

// import "fmt"

// const VESTING_PERIOD  = 100 as uint64

// // simple shows how to compute the size of the person's slashable
// // balance and withdrawable balance in the simple case where none of
// // their payouts have vested fully, and they've had the same salary
// // the whole time.
// func simple(weeklySalary float64, weeksActive float64) (withdrawBalance float64, slashBalance float64) {
// 	// This code doesn't handle edge cases where the weeksActive is too large.
// 	if weeksActive > VESTING_PERIOD {
// 		panic("simple() cannot compute a payout that exceeds the vesting period")
// 	}

// 	// The total amount of potential payout is going to be 100 tokens
// 	// on week 1, 99 tokens on week 2, etc. Essentially an arithmetic
// 	// sequence for the first 100 weeks.
// 	totalBalance := weeklySalary * weeksActive

// 	//the latest week will be the weekly salary * the vesting amount since it is the last week
// 	//Only 1% will have vested
// 	latestWeekPayout := weeklySalary / VESTING_PERIOD

// 	//The earliest week will be the weekly salary * the # of weeks active
// 	//since it's vested x times longer than the latest week
// 	earliestWeekPayout := latestWeekPayout * weeksActive

// 	// Perform the arithmetic series to get the withdrawableBalance
// 	withdrawableBalance := weeksActive * (latestWeekPayout + earliestWeekPayout) / 2
// 	slashableBalance := totalBalance - withdrawableBalance
// 	return withdrawableBalance, slashableBalance
// }

// // The longer function handles the edge case where the user has been receiving payouts
// // for more than the vesting period, which means that some of the weeks have fully
// // vested. Handling this edge case is pretty simple, you just identify which weeks
// // have fully vested and then do a linear computation for them.
// func longer(weeklySalary, weeksActive float64) (withdraw, slash float64) {
// 	// If weeksActive is small, use the simple code to compute the result.
// 	if weeksActive <= VESTING_PERIOD {
// 		return simple(weeklySalary, weeksActive)
// 	}

// 	// Determine how many unvested weeks have elapsed, and how many fully
// 	// vested weeks have elapsed, and the total balance.
// 	unvestedWeeks := float64(VESTING_PERIOD)
// 	fullyVestedWeeks := weeksActive - VESTING_PERIOD
// 	totalBalance := weeklySalary * weeksActive

// 	// Perform the arthimetic series to determine the value of the unvested weeks.
// 	latestWeekPayout := weeklySalary / VESTING_PERIOD
// 	earliestWeekPayout := weeklySalary
// 	partiallyVestedPayout := unvestedWeeks * (latestWeekPayout + earliestWeekPayout) / 2
// 	fullyVestedPayout := fullyVestedWeeks * weeklySalary

// 	// Compute the total payouts.
// 	withdrawBal := partiallyVestedPayout + fullyVestedPayout
// 	slashBal := totalBalance - withdrawBal
// 	return withdrawBal, slashBal
// }

// // fullRange performs the full computation to determine how much a worker is owed for one salary amount.
// // The inputs are:
// //  1. what the salary was (weekylSalary)
// //  2. how long the salary was in effect (weeksActive)
// //  3. how long ago the salary stopped being in effect (weeksStopped)
// //
// // note that if a worker receives a salary for 1 week, then tries to withdraw the balance 208 weeks later,
// // you would call this function with the values `fullRange(salary, 1, 208)`.
// //
// // For the full computation, we first determine how many fully vested weeks there are, then we determine
// // how many partially vested weeks there are, finally we determine how far along the partially vested weeks
// // are. For the case of one weekly salary, this function handles all edge cases.
// func fullRange(weeklySalary, weeksActive, weeksStopped float64) (withdraw, slash float64) {
// 	// Determine the number of fully vested weeks.
// 	fullyVestedWeeks := 0.0
// 	if weeksActive+weeksStopped > VESTING_PERIOD {
// 		fullyVestedWeeks = weeksActive + weeksStopped - VESTING_PERIOD
// 	}
// 	if fullyVestedWeeks > weeksActive {
// 		fullyVestedWeeks = weeksActive
// 	}
// 	fullyVestedWeeksValue := fullyVestedWeeks * weeklySalary

// 	// Determine the number of partially vested weeks.
// 	partiallyVestedWeeks := weeksActive - fullyVestedWeeks

// 	// Determine the amount of vesting that has happened for the lowest value partially
// 	// vested week and the highest value partially vested week, then use those to compute
// 	// the arithmetic sequence to determine the payout.
// 	lowestValueWeek := (1 + weeksStopped) * weeklySalary / VESTING_PERIOD
// 	highestValueWeek := (weeksActive + weeksStopped) * weeklySalary / VESTING_PERIOD
// 	if highestValueWeek > weeklySalary {
// 		highestValueWeek = weeklySalary
// 	}
// 	partiallyVestedWeeksValue := partiallyVestedWeeks * (lowestValueWeek + highestValueWeek) / 2

// 	// Compute the final values
// 	totalBalance := weeksActive * weeklySalary
// 	vestedBalance := fullyVestedWeeksValue + partiallyVestedWeeksValue
// 	slashBalance := totalBalance - vestedBalance
// 	return vestedBalance, slashBalance
// }

// // fullRange performs the full computation to determine how much a worker is owed for one salary amount.
// // The inputs are:
// //  1. what the salary was (weekylSalary)
// //  2. how long the salary was in effect (weeksActive)
// //  3. how long ago the salary stopped being in effect (weeksStopped)
// //
// // note that if a worker receives a salary for 1 week, then tries to withdraw the balance 208 weeks later,
// // you would call this function with the values `fullRange(salary, 1, 208)`.
// //
// // For the full computation, we first determine how many fully vested weeks there are, then we determine
// // how many partially vested weeks there are, finally we determine how far along the partially vested weeks
// // are. For the case of one weekly salary, this function handles all edge cases.
// func fullRangeInteger(weeklySalary uint64, weeksActive uint64, weeksStopped uint64) (withdraw uint64, slash uint64) {
// 	// Determine the number of fully vested weeks.
// 	fullyVestedWeeks := 0.0
// 	if weeksActive+weeksStopped > VESTING_PERIOD {
// 		fullyVestedWeeks = weeksActive + weeksStopped - VESTING_PERIOD
// 	}
// 	if fullyVestedWeeks > weeksActive {
// 		fullyVestedWeeks = weeksActive
// 	}
// 	fullyVestedWeeksValue := fullyVestedWeeks * weeklySalary

// 	// Determine the number of partially vested weeks.
// 	partiallyVestedWeeks := weeksActive - fullyVestedWeeks

// 	// Determine the amount of vesting that has happened for the lowest value partially
// 	// vested week and the highest value partially vested week, then use those to compute
// 	// the arithmetic sequence to determine the payout.
// 	lowestValueWeek := (1 + weeksStopped) * weeklySalary / VESTING_PERIOD
// 	highestValueWeek := (weeksActive + weeksStopped) * weeklySalary / VESTING_PERIOD
// 	if highestValueWeek > weeklySalary {
// 		highestValueWeek = weeklySalary
// 	}
// 	partiallyVestedWeeksValue := partiallyVestedWeeks * (lowestValueWeek + highestValueWeek) / 2

// 	// Compute the final values
// 	totalBalance := weeksActive * weeklySalary
// 	vestedBalance := fullyVestedWeeksValue + partiallyVestedWeeksValue
// 	slashBalance := totalBalance - vestedBalance
// 	return vestedBalance, slashBalance
// }

// func main() {
// 	/*
// 		Show basic progression for simple(), using a weekly salary of 208 for a variety
// 		of numbers of weeks.
// 	*/
// 	fmt.Printf("Using 'simple'\n")
// 	// for i := 0.0; i <= VESTING_PERIOD; i++ {
// 	// withdraw, slash := simple(208, 10)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }
// 	withdraw, slash := fullRange(10_000*1e18, 12.5, 0)
// 	fmt.Printf("\t %.0f, %.0f\n", withdraw, slash)

// 	// // Show that the progression for 'longer' picks up where simple left off. Since
// 	// // 'longer' actually calls simple, we start by repeating 208.
// 	// //
// 	// // Note that the expectation is that the slashable balance should not change, and
// 	// // also that the withdrawable balance increases by the weekly salary every week.
// 	// fmt.Printf("Using 'longer'\n")
// 	// for i := 0.0; i <= 5; i++ {
// 	// 	withdraw, slash := longer(208, i)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }

// 	// for i := 206.0; i <= 212; i++ {
// 	// 	withdraw, slash := longer(208, i)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }

// 	// // Show some samples from 'fullRange'. Note that when 'weeks stopped' is zero,
// 	// // it should match the output of 'short' and 'longer'.
// 	// fmt.Printf("Using 'fullRange', 0 stopped weeks\n")
// 	// for i := 0.0; i <= 5; i++ {
// 	// 	withdraw, slash := fullRange(208.0, i, 0.0)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }
// 	// for i := 206.0; i <= 212; i++ {
// 	// 	withdraw, slash := fullRange(208.0, i, 0.0)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }
// 	// // Try with 1 week stopped, which means there should be more vesting.
// 	// fmt.Printf("Using 'fullRange', 1 stopped weeks\n")
// 	// for i := 0.0; i <= 5; i++ {
// 	// 	withdraw, slash := fullRange(208.0, i, 1.0)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }
// 	// for i := 206.0; i <= 212; i++ {
// 	// 	withdraw, slash := fullRange(208.0, i, 1.0)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }
// 	// // Try with 12 weeks stopped. You can verify by hand that the values match what they
// 	// // are supposed to.
// 	// fmt.Printf("Using 'fullRange', 12 stopped weeks\n")
// 	// for i := 0.0; i <= 5; i++ {
// 	// 	withdraw, slash := fullRange(208.0, i, 12.0)
// 	// 	fmt.Printf("\t %.0f: %.0f, %.0f\n", i, withdraw, slash)
// 	// }
// }
