// You can edit this code!
// Click here and start typing.
package main

import "fmt"

// UniV2 contains the state of a Uniswap V2 pool.
type UniV2 struct {
	// Amount of USD and GLW in the pool.
	USD float64
	GLW float64
	// The pool fee (as a percentage).
	Fee float64
}

// Buy will buy GLW from the UniV2 pool. The return value is the amount of GLW
// that was received.
func (u *UniV2) Buy(amtUSD float64) (amtGLW float64) {
	k := u.USD * u.GLW
	nUSD := u.USD + amtUSD
	nGLW := k / nUSD
	amtGLW = u.GLW - nGLW
	amtGLW *= (1 - u.Fee)

	u.USD = nUSD
	u.GLW = u.GLW - amtGLW
	return amtGLW
}

// SimulateBuy returns the amount of GLW that would be purchased for the given
// USD value, but does not actually execute the trade.
func (u *UniV2) SimulateBuy(amtUSD float64) (amtGLW float64) {
	k := u.USD * u.GLW
	nUSD := u.USD + amtUSD
	nGLW := k / nUSD
	amtGLW = u.GLW - nGLW
	amtGLW *= (1 - u.Fee)

	return amtGLW
}

// Sell will sell GLW to the UniV2 pool. The return value is the amount of USD
// received.
func (u *UniV2) Sell(amtGLW float64) (amtUSD float64) {
	k := u.USD * u.GLW
	nGLW := u.GLW + amtGLW
	nUSD := k / nGLW
	amtUSD = u.USD - nUSD
	amtUSD *= (1 - u.Fee)

	u.USD = u.USD - amtUSD
	u.GLW = nGLW
	return amtUSD
}

// SimulateSell returns the amount of USD that would be received for selling
// the given quantity of GLW tokens, but does not actually execute the trade.
func (u *UniV2) SimulateSell(amtGLW float64) (amtUSD float64) {
	k := u.USD * u.GLW
	nGLW := u.GLW + amtGLW
	nUSD := k / nGLW
	nUSD *= (1 - u.Fee)

	amtUSD = u.USD - nUSD
	return amtUSD
}

// Print the state of the UniV2 pool.
func (u *UniV2) Print(header string) {
	fmt.Println("UniV2 state", header)
	fmt.Println("USD:", u.USD)
	fmt.Println("GLW:", u.GLW)
	fmt.Println("Fee:", u.Fee)
	fmt.Println("Value:", 2*u.USD)
	fmt.Println("Price:", (u.USD/u.GLW)/(1-u.Fee))
}

// Glowswap contains the state of a Glowswap pool.
type Glowswap struct {
	USDRef float64
	GLWRef float64
	M      float64
}

// Buy will buy some GLW from the Glowswap pool.
func (g *Glowswap) Buy(amtUSD float64) (amtGLW float64) {
	if g.M >= 0 {
		oldFeeRate := g.M / (2*g.M + g.USDRef)
		oldGLW := (g.GLWRef * (oldFeeRate*g.M + g.USDRef)) / (g.M + g.USDRef)

		newM := g.M + amtUSD
		newFeeRate := newM / (2*newM + g.USDRef)
		newGLW := (g.GLWRef * (newFeeRate*newM + g.USDRef)) / (newM + g.USDRef)

		g.M = newM
		return oldGLW - newGLW
	} else {
		// This is the mirror of the sell function.
		gm := g.M * -1
		fmt.Println("gm:", gm)
		// Compute the number of GLW that need to be sold to get back
		// zero IL. If the amount of GLW being sold is more than that,
		// we will have to complete a sell using the smaller amount to
		// get back to the reference, and then flip the equations to
		// complete the sell. We could call Sell a second time with the
		// remaining amount, but that makes it harder to implement
		// SimulateSell, so we do it all inline.
		feeRate := gm / (2*gm + g.GLWRef)
		usdToCenter := (gm * g.USDRef * (feeRate*gm + g.GLWRef)) / ((gm + g.GLWRef) * (gm + g.GLWRef))
		remaining := amtUSD - usdToCenter
		if remaining > 0 {
			amtUSD = usdToCenter
		}

		// If we are selling all the way back to zero IL, the math is
		// simpler. We'll only use the complex reference point update
		// equation if we aren't selling back to zero IL. If we aren't
		// selling back to zero IL, we also know that there's nothing
		// remaining, so we can return inside of the conditional.
		newK := g.USDRef * (feeRate*gm + g.GLWRef)
		usdReserves := newK / (g.GLWRef + gm)
		if amtUSD != usdToCenter {
			newGLWReserves := newK / (usdReserves + amtUSD)
			h := newGLWReserves - g.GLWRef
			amtGLW = gm - h
			newGLWRef := (h*h*(-1*(2*gm+g.GLWRef)) + 2*h*gm*gm + g.GLWRef*(2*gm*gm+2*gm*g.GLWRef+g.GLWRef*g.GLWRef)) / ((gm + g.GLWRef) * (gm + g.GLWRef))

			// Update the Glowswap state and return.
			g.M = -1 * (newGLWReserves - newGLWRef)
			g.GLWRef = newGLWRef
			return amtGLW
		}

		// amtGLW is now equal to glwToCenter, we've covered all other
		// cases. We'll grab new state values for Glowswap to reset,
		// and then continue selling, which is actually a mirror of the
		// buy operation when moving away from the center.
		newGLWRef := newK / g.USDRef
		newUSDRef := g.USDRef
		newM := float64(0)
		amtGLW = gm

		// Continue the sell with flipped variables if there is still amtGLW remaining.
		if remaining > 0 {
			oldGLW := (newGLWRef * newUSDRef) / newUSDRef

			newM = remaining
			newFeeRate := newM / (2*newM + newUSDRef)
			newGLW := (newGLWRef * (newFeeRate*newM + newUSDRef)) / (newM + newUSDRef)

			amtGLW += oldGLW - newGLW
		}

		g.USDRef = newUSDRef
		g.GLWRef = newGLWRef
		g.M = newM
		return amtGLW
	}
}

// SimulateBuy will simulate a buy from the Glowswap pool without actually
// changing the pool state.
func (g *Glowswap) SimulateBuy(amtUSD float64) (amtGLW float64) {
	if g.M >= 0 {
		oldFeeRate := g.M / (2*g.M + g.USDRef)
		oldGLW := (g.GLWRef * (oldFeeRate*g.M + g.USDRef)) / (g.M + g.USDRef)

		newM := g.M + amtUSD
		newFeeRate := newM / (2*newM + g.USDRef)
		newGLW := (g.GLWRef * (newFeeRate*newM + g.USDRef)) / (newM + g.USDRef)

		return oldGLW - newGLW
	} else {
		// This is the mirror of the sell function.
		gm := g.M * -1

		// Compute the number of GLW that need to be sold to get back
		// zero IL. If the amount of GLW being sold is more than that,
		// we will have to complete a sell using the smaller amount to
		// get back to the reference, and then flip the equations to
		// complete the sell. We could call Sell a second time with the
		// remaining amount, but that makes it harder to implement
		// SimulateSell, so we do it all inline.
		feeRate := gm / (2*gm + g.GLWRef)
		usdToCenter := (gm * g.USDRef * (feeRate*gm + g.GLWRef)) / ((gm + g.GLWRef) * (gm + g.GLWRef))
		remaining := amtUSD - usdToCenter
		if remaining > 0 {
			amtUSD = usdToCenter
		}

		// If we are selling all the way back to zero IL, the math is
		// simpler. We'll only use the complex reference point update
		// equation if we aren't selling back to zero IL. If we aren't
		// selling back to zero IL, we also know that there's nothing
		// remaining, so we can return inside of the conditional.
		newK := g.USDRef * (feeRate*gm + g.GLWRef)
		usdReserves := newK / (g.GLWRef + gm)
		if amtUSD != usdToCenter {
			newGLWReserves := newK / (usdReserves + amtUSD)
			h := newGLWReserves - g.GLWRef
			amtGLW = gm - h

			// Update the Glowswap state and return.
			return amtGLW
		}

		// amtGLW is now equal to glwToCenter, we've covered all other
		// cases. We'll grab new state values for Glowswap to reset,
		// and then continue selling, which is actually a mirror of the
		// buy operation when moving away from the center.
		newGLWRef := newK / g.USDRef
		newUSDRef := g.USDRef
		newM := float64(0)
		amtGLW = gm

		// Continue the sell with flipped variables if there is still amtGLW remaining.
		if remaining > 0 {
			oldGLW := (newGLWRef * newUSDRef) / newUSDRef

			newM = remaining
			newFeeRate := newM / (2*newM + newUSDRef)
			newGLW := (newGLWRef * (newFeeRate*newM + newUSDRef)) / (newM + newUSDRef)

			amtGLW += oldGLW - newGLW
		}

		return amtGLW
	}
}

// Sell will sell some GLW to the Glowswap pool.
func (g *Glowswap) Sell(amtGLW float64) (amtUSD float64) {
	if g.M >= 0 {
		// Compute the number of GLW that need to be sold to get back
		// zero IL. If the amount of GLW being sold is more than that,
		// we will have to complete a sell using the smaller amount to
		// get back to the reference, and then flip the equations to
		// complete the sell. We could call Sell a second time with the
		// remaining amount, but that makes it harder to implement
		// SimulateSell, so we do it all inline.
		feeRate := g.M / (2*g.M + g.USDRef)
		glwToCenter := (g.M * g.GLWRef * (feeRate*g.M + g.USDRef)) / ((g.M + g.USDRef) * (g.M + g.USDRef))
		remaining := amtGLW - glwToCenter
		if remaining > 0 {
			amtGLW = glwToCenter
		}

		// If we are selling all the way back to zero IL, the math is
		// simpler. We'll only use the complex reference point update
		// equation if we aren't selling back to zero IL. If we aren't
		// selling back to zero IL, we also know that there's nothing
		// remaining, so we can return inside of the conditional.
		newK := g.GLWRef * (feeRate*g.M + g.USDRef)
		glwReserves := newK / (g.USDRef + g.M)
		if amtGLW != glwToCenter {
			newUSDReserves := newK / (glwReserves + amtGLW)
			h := newUSDReserves - g.USDRef
			amtUSD = g.M - h
			newUSDRef := (h*h*(-1*(2*g.M+g.USDRef)) + 2*h*g.M*g.M + g.USDRef*(2*g.M*g.M+2*g.M*g.USDRef+g.USDRef*g.USDRef)) / ((g.M + g.USDRef) * (g.M + g.USDRef))

			// Update the Glowswap state and return.
			g.M = newUSDReserves - newUSDRef
			g.USDRef = newUSDRef
			return amtUSD
		}

		// amtGLW is now equal to glwToCenter, we've covered all other
		// cases. We'll grab new state values for Glowswap to reset,
		// and then continue selling, which is actually a mirror of the
		// buy operation when moving away from the center.
		newUSDRef := newK / g.GLWRef
		newGLWRef := g.GLWRef
		newM := float64(0)
		amtUSD = g.M

		// Continue the sell with flipped variables if there is still amtGLW remaining.
		if remaining > 0 {
			oldUSD := (newUSDRef * newGLWRef) / newGLWRef

			newM = remaining
			newFeeRate := newM / (2*newM + newGLWRef)
			newUSD := (newUSDRef * (newFeeRate*newM + newGLWRef)) / (newM + newGLWRef)

			amtUSD += oldUSD - newUSD
		}

		g.USDRef = newUSDRef
		g.GLWRef = newGLWRef
		g.M = newM * -1
		return amtUSD
	} else {
		// This is the mirror of the buy function.
		gm := g.M * -1
		oldFeeRate := gm / (2*gm + g.GLWRef)
		oldUSD := (g.USDRef * (oldFeeRate*gm + g.GLWRef)) / (gm + g.GLWRef)

		newM := gm + amtGLW
		newFeeRate := newM / (2*newM + g.GLWRef)
		newUSD := (g.USDRef * (newFeeRate*newM + g.GLWRef)) / (newM + g.GLWRef)

		g.M = newM * -1
		return oldUSD - newUSD
	}
}

// SimulateSell will simulate a sale of some GLW to the Glowswap pool, without
// actually executing the trade.
func (g *Glowswap) SimulateSell(amtGLW float64) (amtUSD float64) {
	if g.M >= 0 {
		// Compute the number of GLW that need to be sold to get back
		// zero IL. If the amount of GLW being sold is more than that,
		// we will have to complete a sell using the smaller amount to
		// get back to the reference, and then flip the equations to
		// complete the sell. We could call Sell a second time with the
		// remaining amount, but that makes it harder to implement
		// SimulateSell, so we do it all inline.
		feeRate := g.M / (2*g.M + g.USDRef)
		glwToCenter := (g.M * g.GLWRef * (feeRate*g.M + g.USDRef)) / ((g.M + g.USDRef) * (g.M + g.USDRef))
		remaining := amtGLW - glwToCenter
		if remaining > 0 {
			amtGLW = glwToCenter
		}

		// If we are selling all the way back to zero IL, the math is
		// simpler. We'll only use the complex reference point update
		// equation if we aren't selling back to zero IL. If we aren't
		// selling back to zero IL, we also know that there's nothing
		// remaining, so we can return inside of the conditional.
		newK := g.GLWRef * (feeRate*g.M + g.USDRef)
		glwReserves := newK / (g.USDRef + g.M)
		if amtGLW != glwToCenter {
			newUSDReserves := newK / (glwReserves + amtGLW)
			h := newUSDReserves - g.USDRef
			amtUSD = g.M - h

			return amtUSD
		}

		// amtGLW is now equal to glwToCenter, we've covered all other
		// cases. We'll grab new state values for Glowswap to reset,
		// and then continue selling, which is actually a mirror of the
		// buy operation when moving away from the center.
		newUSDRef := newK / g.GLWRef
		newGLWRef := g.GLWRef
		newM := float64(0)
		amtUSD = g.M

		// Continue the sell with flipped variables if there is still amtGLW remaining.
		if remaining > 0 {
			oldUSD := (newUSDRef * newGLWRef) / newGLWRef

			newM = remaining
			newFeeRate := newM / (2*newM + newGLWRef)
			newUSD := (newUSDRef * (newFeeRate*newM + newGLWRef)) / (newM + newGLWRef)

			amtUSD += oldUSD - newUSD
		}

		return amtUSD
	} else {
		// This is the mirror of the buy function.
		gm := g.M * -1
		oldFeeRate := gm / (2*gm + g.GLWRef)
		oldUSD := (g.USDRef * (oldFeeRate*gm + g.GLWRef)) / (gm + g.GLWRef)

		newM := gm + amtGLW
		newFeeRate := newM / (2*newM + g.GLWRef)
		newUSD := (g.USDRef * (newFeeRate*newM + g.GLWRef)) / (newM + g.GLWRef)

		return oldUSD - newUSD
	}
}

// Print will print the state of the Glowswap pool, including the computed
// reserves.
func (g *Glowswap) Print(header string) {
	fmt.Println("Glowswap state", header)
	fmt.Println("USDRef:", g.USDRef)
	fmt.Println("GLWRef:", g.GLWRef)
	fmt.Println("M", g.M)

	if g.M >= 0 {
		feeRate := g.M / (2*g.M + g.USDRef)
		fmt.Println("Fee Rate:", feeRate)
		usd := g.USDRef + g.M
		glw := (g.GLWRef * (feeRate*g.M + g.USDRef)) / (g.M + g.USDRef)
		fmt.Println("USD:", usd)
		fmt.Println("GLW:", glw)
		fmt.Println("Value:", 2*usd)
		fmt.Println("Price:", (usd/glw)/(1-feeRate))
	} else {
		gm := -1 * g.M
		feeRate := gm / (2*gm + g.GLWRef)
		fmt.Println("Fee Rate:", feeRate)
		usd := (g.USDRef * (feeRate*gm + g.GLWRef)) / (gm + g.GLWRef)
		glw := g.GLWRef + gm
		fmt.Println("USD:", usd)
		fmt.Println("GLW:", glw)
		fmt.Println("Value:", 2*usd)
		fmt.Println("Price:", (usd/glw)/(1-feeRate))
	}
}

func main() {
	// We are creating a simulation for two AMMs, Uniswap V2 and Glowswap.
	// The goal is to see how much money liquidity providers make on each.
	// There are a couple of different scenarios that I hope to simulate.

	// First up, some basic tests to make sure that the UniV2 pool is
	// working.
	// uTest := UniV2{
	// 	USD: 180,
	// 	GLW: 120,

	// 	Fee: 0.003,
	// }
	// uTest.Print("uTest init")
	// fmt.Println()

	// fmt.Println("Buy $60")
	// fmt.Println(uTest.SimulateBuy(60))
	// fmt.Println(uTest.Buy(60))
	// uTest.Print("uTest buy 60")
	// fmt.Println()

	// fmt.Println("Sell !30")
	// fmt.Println(uTest.SimulateSell(30))
	// fmt.Println(uTest.Sell(30))
	// uTest.Print("uTest sell 30")
	// fmt.Println()

	// Second up, some basic tests to make sure the Glowswap pool is
	// working.
	gTest := Glowswap{
		USDRef: 180,
		GLWRef: 120,
		M:      60,
	}
	gTest.Print("gTest init")
	fmt.Println()

	fmt.Println("Buy $60")
	// fmt.Println(gTest.SimulateBuy(60))
	fmt.Println(gTest.Buy(60))
	gTest.Print("gTest buy 60")
	fmt.Println()

	// fmt.Println("Sell !20")
	// fmt.Println(gTest.SimulateSell(20))
	// fmt.Println(gTest.Sell(20))
	// gTest.Print("gTest sell 20")
	// fmt.Println()

	// fmt.Println("Sell !80")
	// fmt.Println(gTest.SimulateSell(80))
	// fmt.Println(gTest.Sell(80))
	// gTest.Print("gTest sell 80")
	// fmt.Println()

	// fmt.Println("Sell !20")
	// fmt.Println(gTest.SimulateSell(20))
	// fmt.Println(gTest.Sell(20))
	// gTest.Print("gTest sell 20")
	// fmt.Println()

	// fmt.Println("Buy $30")
	// fmt.Println(gTest.SimulateBuy(30))
	// fmt.Println(gTest.Buy(30))
	// gTest.Print("gTest buy 30")
	// fmt.Println()

	// fmt.Println("Buy $90")
	// fmt.Println(gTest.SimulateBuy(90))
	// fmt.Println(gTest.Buy(90))
	// gTest.Print("gTest buy 90")
	// fmt.Println()

	// fmt.Println("Buy $50")
	// fmt.Println(gTest.SimulateBuy(50))
	// fmt.Println(gTest.Buy(50))
	// gTest.Print("gTest buy 50")
	// fmt.Println()

	// This ends the testing, seems like the two AMMs have been implemented
	// correctly. Really I should add some automated testing, but for now I
	// just eyeballed the results and compared them to results that were in
	// the Glowswap equations spreadsheet.
}

// Buy $60
// 10.285714285714292
// 10.285714285714292
// Glowswap state gTest buy 60
// USDRef: 180
// GLWRef: 120
// M 120
// Fee Rate: 0.2857142857142857
// USD: 300
// GLW: 85.71428571428571
// Value: 600
// Price: 4.9

// Buy $60
// 10.285714285714292
// Glowswap state gTest buy 60
// USDRef: 180
// GLWRef: 120
// M 120
// Fee Rate: 0.2857142857142857
// USD: 300
// GLW: 85.71428571428571
// Value: 600
// Price: 4.9
