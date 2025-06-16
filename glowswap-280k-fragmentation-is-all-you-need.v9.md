# Fragmentation Is All You Need

Glowswap is a new type of Constant Product Market Maker (CPMM) that allows
users to borrow liquidity. The borrowed liquidity goes into a separate CPMM
that only the borrower is allowed to interact with. The mathematical properties
of CPMMs ensure that the borrower will always be able to return as much
liquidity as they borrowed, with interest included.

Borrowing liquidity enables many opportunities such as more efficient
volatility trading, collateralized borrowing, and leveraged longs that don't
have any liquidation risk. Glowswap upgrades the traditional blockchain AMM
into a fertile platform that offers more opportunities for traders.

## Constant Prodcut Market Makers

The central element of Glowswap is a Constant Product Market Maker, or CPMM,
which allows users to freely trade a single asset pair. For example, a CPMM
that trades USDC and GLW will allow users to exchange USDC tokens for GLW
tokens, and vice-versa.

CPMMs can be created using any asset pair, however this document will use USDC
tokens and GLW tokens as the asset pair in all of its examples.

### The Constant Product Rule

When a user exchanges tokens with a CPMM, the number of tokens that the user
receives is determined by the "Constant Product Rule", which states that the
number of assets in the CPMM must have the same product before and after an
exchange.

As an example, a CPMM that has 100 USDC tokens and 100 GLW tokens will have a
product of 10,000. When a user exchanges USDC tokens with this CPMM, the CPMM
will emit the quantity of GLW tokens that will keep the product at 10,000.

Therefore, if a user exchanges 25 USDC tokens with this CPMM, the total USDC
tokens in the CPMM will increase to 125. The updated number of GLW tokens in
the CPMM can be calculated with the equation `10,000 / 125`, which equals 80.
The CPMM will therefore emit 20 tokens to the user so it can maintain its asset
product of 10,000.

|Action          |Result          |USDC|GLW|Product|
|:---------------|:---------------|---:|--:|------:|
|init            |init            | 100|100| 10,000|
|exchange 25 USDC|receive  20  GLW| 125| 80| 10,000|
|exchange 75 USDC|receive  30  GLW| 200| 50| 10,000|
|exchange 50 GLW |receive 100 USDC| 100|100| 10,000|

As you can see from the table above, as more USDC tokens are added to the CPMM,
fewer GLW tokens are emitted per USDC token that gets added. In the first
exchange, a user trades 25 USDC tokens for 20 GLW tokens. In the second
exchange, a user trades three times as many USDC tokens to get just 50% more
GLW tokens.

All of the actions are reversible. In the final exchange, a user adds 50 GLW
tokens and receives 100 USDC tokens, effectively resetting the CPMM to its
original state.

### Liquidity

Every CPMM has some quantity of "liquidity", which is measured by the square
root of its product. The liquidity comes from "liquidity providers", or LPs,
who are users that deposit assets into the CPMM for the purpose of owning
liquidity in the CPMM. Liquidity providers can add liquidity to a CPMM by
depositing any quantity of either asset.

The total amount of liquidity that is received for depositing assets is
calculated by comparing the difference between the amount of liquidity in the
CPMM before the deposit with the amount of liquidity in the CPMM after the
deposit. That difference is assigned to the LP as liquidity.

|Action                 |Result       |USDC|GLW|Product|Liquidity|
|:----------------------|:------------|---:|--:|------:|--------:|
|init                   |init         | 100|100| 10,000|      100|
|deposit 44 USDC        |+20 liquidity| 144|100| 14,400|      120|
|deposit 52 USDC        |+20 liquidity| 196|100| 19,600|      140|
|deposit 44  GLW        |+24 liquidity| 196|144| 28,224|      168|
|deposit 52  GLW        |+24 liquidity| 196|196| 38,416|      196|
|deposit 27 USDC, 27 GLW|+27 liquidity| 223|223| 48,400|      223|
|deposit 27 USDC, 27 GLW|+27 liquidity| 250|250| 62,500|      250|

You can see from the set of actions above that depositing the same number of
tokens does not always result in receiving the same amount of liquidity. As an
asset becomes a greater proportion of the total assets, each additional unit of
that asset will produce less liquidity. Conversely, as an asset becomes a
lesser proportion of the total, each additional unit of that asset will produce
more liquidity.

If assets are added in the same proportion as they already exist in the CPMM,
the amount of liquidity received per unit will stay the same as more assets are
added.

When an LP adds liquidity to a CPMM, they are allowed to withdraw up to the
same amount of liquidity later. And just as liquidity can be added by
depositing any amount of either asset, liquidity can also be removed by
withdrawing any amount of either asset.

The total liquidity that has been removed can be determined by calculating the
difference between the amount of liquidity in the CPMM before and after the
withdrawal. The transaction is only valid if the LP is allowed to withdraw that
much liquidity.

|Action                  |Result       |USDC|GLW|Product|Liquidity|
|:-----------------------|:------------|---:|--:|------:|--------:|
|init                    |init         | 250|250| 62,500|      250|
|withdraw 90 USDC        |-50 liquidity| 160|250| 40,000|      200|
|withdraw 70 USDC        |-50 liquidity|  90|250| 22,500|      150|
|withdraw 90  GLW        |-30 liquidity|  90|160| 14,400|      120|
|withdraw 70  GLW        |-30 liquidity|  90| 90|  8,100|       90|
|withdraw 30 USDC, 30 GLW|-30 liquidity|  60| 60|  3,600|       60|
|withdraw 30 USDC, 30 GLW|-30 liquidity|  30| 30|    900|       30|

You can see that as one asset becomes a smaller proportion of the CPMM, it
costs more liquidity to withdraw that asset, and vice-versa.

### Market Driven Price Discovery

If any member of the public is allowed to exchange freely with a CPMM, then
that CPMM will naturally converge to the real price of its underlying assets.
This is because any member of the public will be able to arbitrage a price
mismatch between the CPMM price and the real price.

For example, let's say the market price of the GLW token is 1 USDC token per
GLW token, but the CPMM has a price of 4 USDC tokens per GLW token. A trader
will be able to make money buy purchasing GLW tokens from the market for 1 USDC
token each and then selling them to the CPMM for 2 USDC tokens each. This
process will push the price of GLW tokens down and can be repeated until the
price of GLW tokens on the CPMM matches the market price of GLW tokens:

|Action          |Result         |USDC|GLW|Price| Profit|
|:---------------|:--------------|---:|--:|----:|------:|
|init            |init           | 400|100| 4.00|      -|
|exchange 25 GLW |receive 80 USDC| 320|125| 2.56|55 USDC|
|exchange 35 GLW |receive 70 USDC| 250|160|~1.56|35 USDC|
|exchange 40 GLW |receive 50 USDC| 200|200| 1.00|10 USDC|

In the above table, the GLW price on the CPMM starts at 4 USDC tokens per GLW
token. Since GLW tokens can be purchased on the market for 1 USDC token each, a
profit opportunity exists.

The first traders to purchase GLW on the market and trade them with the CPMM
make a lot of money; the first trade averages a profit of 2.2 USDC tokens per
GLW token sold to the CPMM.

As more traders participate in the arbitrage, the price of GLW tokens on the
CPMM gets closer to the market price of GLW tokens, and the amount of profit
per GLW token decreases. In total, 100 USDC of profit is made by traders. After
that, the price of the CPMM matches the market price, and no more arbitrage
opportunities exist.

Because these arbitrage opportunities represent free money for traders, the
price of GLW tokens on the CPMM will closely track the market price of GLW
tokens, so long as traders can easily and cheaply perform the arbitrage
transactions.

## Borrowing Liquidity with Glowswap

Glowswap extends the basic CPMM by allowing individuals to borrow liquidity
from the CPMM and hold that liquidity in a separate CPMM which can only be used
by the borrower. On Glowswap, the original CPMM is called the source CPMM, and
the CPMMs that are created with borrowed liquidity are called exclusive CPMMs.
The user that is borrowing the liquidity is called the borrower.

The borrower is required to return as much liquidity as they borrow. Glowswap
is able to guarantee that the borrower can return the liquidity by requiring
the exclusive CPMM to independently maintain as much liquidity as it borrowed,
which means it must adhere to the constant product rule.

A principle called 'The Law of Accumulating Liquidity' ensures that the
borrower is always able to return as much liquidity as they borrowed. The
principle states when the assets of two different CPMMs are merged together,
the combined CPMM will have as much or more liquidity than the sum of the
liquidity in the two individual CPMMs.

This means that no matter what exchanges the borrower makes with their
exclusive CPMM, and no matter what exchanges happen on the source CPMM, the
borrower will be able to return as much liquidity as they borrowed using only
the assets available in their exclusive CPMM.

### The Law of Accumulating Liquidity

The Law of Accumulating Liquidity states that the collective amount of
liquidity in separate CPMMs is always less than or equal to the amount of
liquidity in a CPMM that combines all of the assets together. This law assumes
that every CPMM has a non-zero and positive quantity of each asset.

Let's explore some examples.

|Name    |USDC|GLW|Liquidity|
|-------:|---:|--:|--------:|
|       1| 100|100|      100|
|       2| 100|100|      100|
|Combined| 200|200|      200|

If all CPMMs have the same ratio of assets, then the combined liquidity will be
equal to the sum of the liquidity in each CPMM. You can see that in the above
example.

|Name    |USDC|GLW|Liquidity|
|-------:|---:|--:|--------:|
|       1| 100|100|      100|
|       2| 400| 25|      100|
|Combined| 500|125|      250|

In the above example, both CPMMs start with 100 liquidity, but because the
CPMMs have a different ratio of assets, the combined CPMM has 25% more
liquidity than the two individual CPMMs. This effect gets more extreme as the
differences between the individual CPMMs gets more extreme.

|Name    |USDC|GLW|Liquidity|
|-------:|---:|--:|--------:|
|       1|  25|400|      100|
|       2| 400| 25|      100|
|Combined| 425|425|      425|

In the above example, the combined CPMM has more than twice as much liquidity
as the sum of the liquidity in the individual CPMMs.

|Name    |CPMM USDC|CPMM GLW|CPMM Liquidity|
|-------:|--------:|-------:|-------------:|
|       1|      100|     100|           100|
|       2|       25|     400|           100|
|       3|      400|      25|           100|
|       4|       10|      10|            10|
|Combined|      535|     535|           535|

In the final example above, you can see that the Law of Accumulating Liquidity
holds across any number of CPMMs, with the CPMMs individually having 310
liquidity total, but combined having 535 liquidity total.

The Law of Accumulating Liquidity is useful in the context of exclusive CPMMs
because it means that as long as the borrower is required to adhere to the
Constant Product Rule in their exclusive CPMM, the borrower is also guaranteed
to be able to return as much liquidity as they borrowed, regardless of how the
ratio of assets in the source CPMM and exclusive CPMM change.

The Glowswap smart contracts enforce that all exclusive CPMMs are required to
adhere to the Constant Product Rule, creating safety for the LPs of the source
CPMM and guaranteeing that when an exclusive CPMM is closed and liquidity is
returned, the source CPMM will get back at least as much liquidity as was
borrowed.

### Proving the Law of Accumulating Liquidity

Mathmatically, the Law of Accumulating Liquidity for two CPMMs can be expressed
as:

```
sqrt(x1*y1) + sqrt(x2*y2) <= sqrt((x1 + x2) * (y1 + y2))
```

In the above equality, x1 and y1 are the number of Glow tokens and USDC tokens
in the first CPMM. x2 and y2 are the number of Glow tokens and USDC tokens in
the second CPMM. The equation `sqrt(x1*y1)+sqrt(x2*y2)` evaluates the sum of
the liquidity in the two CPMMs, and the equation `sqrt((x1 + x2) * (y1 + y2))`
evaluates the amount of liquidity in a CPMM that combines all assets together.

The equality can be simplified by squaring both sides:

```
(sqrt(x1*y1) + sqrt(x2*y2))^2 <= sqrt((x1 + x2) * (y1 + y2))^2
```

Which has the result:

```
x1*y1 + 2*sqrt(x1*y1)*sqrt(x2*y2) + x2*y2 <= (x1 + x2) * (y1 + y2)
```

This can be further simplified to:

```
x1*y1 + 2*sqrt(x1*y1*x2*y2) + x2*y2 <= (x1 + x2) * (y1 + y2)
```

The right side can be expanded to:

```
x1*y1 + 2*sqrt(x1*y1*x2*y2) + x2*y2 <= x1*y1 + x1*y2 + x2*y1 + x2*y2
```

You can then eliminate the terms that appear on both sides of the equation,
resulting in:

```
2*sqrt(x1*y1*x2*y2) <= x1*y2 + x2*y1
```

You can then further simplify the equation by setting `a=x1*y2` and
`b=x2*y1`, resuling in:

```
2*sqrt(a*b) <= a + b
```

We can eliminate the remaining square root by squaring both sides:

```
4*a*b <= a^2 + 2*a*b + b^2
```

We then subtract `4*a*b` from both sides, resulting in:

```
0 <= a^2 - 2*a*b + b^2
```

Using a difference of squares, we can simplify further to:

```
0 <= (a-b)^2
```

This completes the proof, as it is well known that the square of any value is
greater than or equal to zero, thus demonstrating that the original equality
was also true.

The proof can easily be extended from two CPMMs to an arbitrary number of
CPMMs. When combining the liquidity from a large number of CPMMs, one can
simply combine 2 CPMMs at a time, until only one CPMM remains. Thanks to the
above proof, we know that each time two CPMMs are combined, the total amount of
liquidity will either stay the same or increase, thus proving that:

For any set of CPMMs, the sum of the liquidity of each CPMM will always be less
than or equal to the liquidity of a single CPMM that combines all of their
assets.

You can confirm the derivation by plugging the original inequality into Wolfram
Alpha like this:

```
sqrt(x1*y1)+sqrt(x2*y2) <= sqrt((x1+x2)*(y1+y2)), x1 > 0, y1 > 0, x2 > 0, y2 > 0
```

Wolfram Alpha will spit out the result:

```
Solution: x1 > 0, x2 > 0, y1 > 0, y2 > 0
```

Which essentially says that the inequality is true for all values where all
four variables are greater than 0, confirming that Wolfram Alpha agrees with
our conclusion.

### Returning Only What Is Necessary

According to the Law of Accumulating Liquidity, an exclusive CPMM may be able
to return all of the liquidity that it borrowed without returning all of the
assets contained in the exclusive CPMM.

For example, a borrower could create an exclusive CPMM with 100 USDC tokens and
100 GLW tokens, then exchange 300 USDC tokens for 75 GLW tokens, then finally
return the liquidity to the source CPMM.

When the borrower first creates the exclusive CPMM, the CPMMs look like this:

|Name     |USDC|GLW|Liquidity|
|:--------|---:|--:|--------:|
|source   | 100|100|      100|
|exclusive| 100|100|      100|
|combined | 200|200|      200|

After the borrower performs the exchange, the CPMMs look like this:

|Name     |USDC|GLW|Liquidity|
|:--------|---:|--:|--------:|
|source   | 100|100|      100|
|exclusive| 400| 25|      100|
|combined | 500|125|      250|

To return 100 liquidity to the source CPMM, the borrower only needs to return
about 61.6% of the assets in the exclusive CPMM, which would leave the CPMMs
looking like this:

|Name     |USDC|GLW|Liquidity|
|:--------|----:|---:|--------:|
|source   | ~347|~115|      200|
|exclusive| ~153| ~10|      ~38|

Since the borrower has returned all of the required liquidity to the source
CPMM, the borrower is actually able to fully withdraw the remaining assets in
the exclusive CPMM and use them without restrictions. In other words, the
borrower receives a refund of ~153 USDC tokens and ~10 GLW tokens.

After all transactions are complete, the borrower has effectively deposited
~147 USDC tokens into the source CPMM, in exchange for ~85 GLW tokens. This
sequence of actions is actually mathematically equivalent to the borrower just
exchanging ~147 USDC tokens for ~85 GLW tokens on the original source CPMM.

A more interesting example shows what happens if the price of GLW tokens
changes on the source CPMM after the borrower has created an exclusive CPMM.
Let's say the GLW token price goes up 16x after the borrower has created an
exclusive CPMM.

The CPMMs initially look like this:

|Name     |USDC|GLW|Liquidity|
|:--------|---:|--:|--------:|
|source   | 100|100|      100|
|exclusive| 100|100|      100|
|combined | 200|200|      200|

The price on the source CPMM increases by 16x because a trader exchanges 300
USDC tokens for 75 GLW tokens:

|Name     |USDC|GLW|Liquidity|
|:--------|---:|--:|--------:|
|source   | 400| 25|      100|
|exclusive| 100|100|      100|
|combined | 500|125|      250|

To return 100 liquidity to the source CPMM, the borrower only needs to return
about 61.6% of the assets in the exclusive CPMM, resulting in a final state of:

|Name     |USDC|GLW|Liquidity|
|:--------|---:|--:|--------:|
|source   |~462|~87|      200|
|exclusive| ~38|~38|      ~38|

The borrower has fully satisfied their obligations, returning as much liquidity
as required. That means the borrower is left with 38 USDC tokens and 38 GLW
tokens of profit.

This invites the question "where did all of the profit come from?". We can gain
insight by looking at the initial state and final state of all participants:

Initial State:

|Name       |USDC|GLW|
|:----------|---:|--:|
|borrower   |   0|  0|
|source CPMM| 200|200|
|trader     | 300|  0|
|total      | 500|200|

Final State:

|Name       |USDC|GLW|
|:----------|---:|--:|
|borrower   | ~38|~38|
|source CPMM|~462|~87|
|trader     |   0| 75|
|total      | 500|200|

The sequence above is equivalent to the trader exchanging roughly 262 USDC
tokens with the source CPMM, receiving roughly 113 GLW tokens, then giving
roughly 38 USDC tokens and roughly 38 GLW tokens to the borrower as a trading
fee.

By reducing the total amount of liquidity in the source CPMM, the borrower
caused the trader to be exposed to more slippage. This slippage created an
arbitrage opportunity for the borrower, and the borrower exploited that
arbitrage opportunity to collect 38 USDC tokens and 38 GLW tokens of profit.

By reducing the total amount of liquidity in the source CPMM, the borrower has
created a de-facto trading fee on the source CPMM which manifests to the
traders as slippage, allowing the borrower to extract value from the traders.

A borrower can use many different strategies to extract value from traders. One
strategy could run an arbitrage transaction after every trade. Another strategy
could wait until the arbitrage opportunity increases above some threshold. And
another could execute an arbitrage transaction at some regular time interval
such as once a day.

These example strategies all related to making profit off of traders and price
volatility in the source CPMM. But there are many different ways that a
borrower can make money using borrowed liquidity.

### Competition for Liquidity

Anyone can be a borrower and employ their own strategy to profit from borrowed
liquidity. Many of these strategies would be entirely risk-free if borrowing
liquidity was free, which means that borrowers would try to collect as much
liquidity as possible.

Instead, borrowers need to pay interest on the liquidity that they borrow. This
both provides an incentive for LPs to add more liquidity to the source CPMM, as
well as creates competition among borrowers who will need to find competitive
strategies for extracting value from borrowed liquidity.

The borrowers with the best strategies for turning liquidity into profit will
be able to tolerate a higher interest rate, and will price out borrowers that
are less effective at extracting value from liquidity.

This competition for liquidity drives the interest rate up, and ensures that
LPs receive the best possible returns for their liquidity without having to set
fees, engage in governance, manage liquidity concentration, or understand
anything about the best borrowing strategies themselves.

## Paying Interest

Borrowers pay interest in the form of liquidity. If an exclusive CPMM borrows
100 liquidity and owes 1% interest, they will need to return 101 liquidity to
the source CPMM. This means that extra assets need to be provided as collateral
when a borrower creates an exclusive CPMM.

### Pre-paying For Interest

When an exclusive CPMM is created, the borrower is required to prepay for the
interest by adding extra assets to the exclusive CPMM, meaning that the
exclusive CPMM will have more liquidity in it than was borrowed from the source
CPMM. The source CPMM will draw from that extra liquidity when extracting
interest payments. This extra liquidity is called "interest liquidity".

When an exclusive CPMM is created, the borrower can extract assets from the
source CPMM in any ratio, and they can provide extra assets to the exclusive
CPMM in any ratio. When the transaction is complete, the exclusive CPMM needs
to independently have as much liquidity as was removed from the source CPMM, as
well as enough interest liquidity to make interest payments.

Here are some examples showing different ways that a borrower can borrow
liquidity from a source CPMM while adding interest liquidity that is equal in
amount to what was borrowed.

|Action      |USDC| GLW|Liquidity|
|:-----------|---:|---:|--------:|
|source init |1000|1000|     1000|
|borrowed    | 100| 100|      100|
|source final| 900| 900|      900|
|interest    | 100| 100|      100|
|exclusive   | 200| 200|      200|

In the above example:
+ the source CPMM started with 1000 USDC tokens and 1000 GLW tokens
+ a borrower borrowed 100 USDC tokens and 100 GLW tokens
+ the borrower added 100 USDC tokens and 100 GLW tokens for interest payments
+ the exclusive CPMM ended at 200 liquidity, 100% more than what was borrowed
+ the final cost to the borrower is 100 USDC tokens and 100 GLW tokens.

A common case is that the borrower only has one asset available to them, such
as a borrower that has lots of GLW tokens but no USDC tokens. One potential
approach would be to borrow liquidity in an equal ratio, and supply interest
liquidity using only GLW tokens:

|Action      |USDC| GLW|Liquidity|
|:-----------|---:|---:|--------:|
|source init |1000|1000|     1000|
|borrowed    | 100| 100|      100|
|source final| 900| 900|      900|
|interest    |   0| 300|      100|
|exclusive   | 100| 400|      200|

In the above example, the borrower added 100 liquidity to the exclusive CPMM by
contributing 300 GLW tokens, which allows the borrower to avoid needing USDC
tokens. The final exclusive CPMM has 100 USDC tokens and 400 GLW tokens, and
the borrower had to pay 300 GLW tokens total to create their exclusive CPMM.

The borrower could have instead only borrowed USDC from the source CPMM,
supplying enough GLW tokens to get the exclusive CPMM up to the desired 200
liquidity:

|Action      |USDC| GLW|Liquidity|
|:-----------|---:|---:|--------:|
|source init |1000|1000|     1000|
|borrowed    | 190|   0|      100|
|source final| 810|1000|      900|
|interest    |   0|~211|      100|
|exclusive   | 190|~211|      200|

In this final example, the borrower extracts 190 USDC tokens from the source
CPMM, removing a total of 100 liquidity. The exclusive CPMM starts with 190
USDC tokens, and can be brought to 200 liquidity total for only ~211 GLW
tokens. Though the borrower has borrowed the exact same amount of liquidity and
supplied the same amount of interest liquidity, the total cost to the borrower
was almost 30% cheaper.

### Borrowing Limits

Glowswap sets a target of having 80% of the total liquidity in exclusive CPMMs.
If less than 80% of the total liquidity has been borrowed, the interest rate
will decrease, and if more than 80% of the total liquidity has been borrowed,
the interest rate will increase. This allows market forces to determine the
optimal interest rate for Glowswap.

For safety reasons, Glowswap does not allow more than 95% of the total
liquidity to be held in exclusive CPMMs. If 95% of the total liquidity has been
borrowed, borrowers will not be able to create new exclusive CPMMs, nor will
they be allowed to add more liquidity to existing CPMMs. They will have to wait
until LPs add more liquidity.

### Establishing the Interest Rate

The interest rate is adjusted on a continuous basis. The minimum interest rate
is 0.1% APY, and the maximum interest rate is 10,000% APY. In most
circumstances, the interest rate is able to adjust by up to 20% of its current
value every day.

For example, if the current interest rate is 10% APY, and one day has passed
since the previous update, the interest rate could be adjusted to any value
between 8.3% and 12%. If two days have passed, the interest rate could be
adjusted to any value between 6.9% and 14.4%.

The interest rate gets updated every time that someone interacts with Glowswap.
If more than two days have passed, it means people are rarely interacting with
Glowswap and the interest rate doesn't need to be dramatically adjusted.
Therefore, if more than two days have passed since the previous interest rate
adjustment, the interest rate will be adjusted as though only two days have
passed.

If the current interest rate is at or below 0.5% APY, the interest rate
calculation will move the interest rate by an absolute adjustment of up to 0.1%
per day, rather than using a relative adjustment. The absolute adjustments when
the interest rate is low ensures that the interest rate can rapidly increase in
the event that there's a long period with a low interest rate.

For example, if the current interest rate is 0.4% and two days have passed, the
new interest rate could be adjusted to any value between 0.2% and 0.6%. The
lowest allowed value for the interest rate is 0.1% APY.

Within the range of possible new interest rates, a value is chosen based on how
much liquidty is currently being used. Four different equations determine how
adjustments are made:

When the current interest rate is above 0.5% and the amount of liquidity in use
is below 80%, the following equation is used:

```
interest_rate /= (1.2 - 0.2 * liquidity_usage / 0.8)^(days)
```

When the current interest rate is above 0.5% and the amount of liquidity in use
is above 80%, the following equation is used:

```
interest_rate *= (1 + 0.8 * 4/3 * (liquidity_usage/0.8 - 1))^(days)
if interest_rate > 10e3 {
    interest_rate = 10e3
}
```

When the current interest rate is below 0.5%, and the amount of liquidity in
use is below 80%, the following equation is used:

```
interest_rate -= 0.1 * liquidity_usage / 0.8 * days
if interest_rate < 0.1 {
    interest_rate = 0.1
}
```

When the current interest rate is below 0.5%, and the amount of liquidity in
use is above 80%, the following equation is used:

```
interest_rate += 4/3 * 0.4 * (liquidity_usage / 0.8 - 1) * days
```

## Returning Liquidity

A key promise that Glowswap makes to borrowers is that an exclusive CPMM will
never need to return liquidity prematurely. As long as the exclusive CPMM has
interest liquidity remaining, the exclusive CPMM will be allowed to retain its
borrowed liquidity. When the interest liquidity runs out, all borrowed
liquidity is immediately returned to the source CPMM.

This means that under certain circumstances, LPs will not be able to
immediately withdraw their liquidity. An LP can only withdraw liquidity if
there is liquidity available in the source CPMM to be withdrawn.

Because Glowswap sets a target of having 80% of the total liquidity loaned out
and allows up to 95% of the total liquidity to be in exclusive CPMMs, the
source CPMM will usually have around 15% of the total liquidity available for
LPs to withdraw. As long as an LP is withdrawing less than 15% of the total
liquidity, they will usually be able to withdraw their liquidity immediately.

If one LP is trying to withdraw more than 15% of the total liquidity, or if
more than the target amount of liquidity has been loaned out, or if many LPs
are trying to withdraw all of their liquidity at once, the LP may be placed
into a withdrawal queue.

The withdrawal queue processes LPs one at a time in FIFO order as liquidity
becomes available. LPs always have priority access to new liquidity - if there
are LPs in the queue waiting to exit Glowswap, no borrowers will be able to
borrow new liquidity until every LP in the queue has been processed, including
LPs that joined the queue after new borrowers appeared.

If there is a withdrawal queue and a new LP deposits liquidity into the source
CPMM, that liquidity will immediately used to process the withdrawal queue.
Similarly, all interest payments made by borrowers will be used to process the
withdrawal queue.

Glowswap strikes a balance to benefit both borrowers and LPs. The promise to
borrowers is that once liquidity has been borrowed, it will remain under the
control of the borrower until there is no more interest liquidity available to
pay for the borrowed liquidity. The promise to LPs is that no borrower will be
able to borrow new liquidity as long as an LP is waiting in the withdrawal
queue.

### Interest Distribution

All of the interest that is paid by borrowers is given to LPs. If 80% of the
total liquidity has been borrowed and borrowers are paying 10% APY, then
liquidity providers will receive 8% APY. This delta exists because there is
more liquidity available than there is liquidity which is actively being paid
for by borrowers.

LPs do not collect interest if they are waiting in the withdrawal queue. If
borrowers are paying 10% APY and there is a very tiny withdrawal queue, it
means that 95% of the total liquidity has been borrowed. Therefore, any LPs
that are not attempting to withdraw their liquidity will be earning 9.5% APY.

If borrowers are paying 10% APY and half of the total liquidity is being
withdrawn in a withdrawal queue, then LPs who are not attempting to withdraw
their liquidity will be earning 19% APY. This is because nobody in the queue is
earning interest on the liquidity that they are waiting to withdraw, therefore
the interest will be distributed to the LPs who are not trying to withdraw.

This means that during periods where many LPs are trying to withdraw liquidity
at once, a much larger incentive exists for new LPs to join and take advantage
of the temporary spike in interest being received by LPs who are staying in the
source CPMM. This spike acts as an incentive that helps to ensure that any
withdrawal queues are short lived.

### Maximum Lock-In Period

Interest payments are continuously collected by Glowswap. Furthermore, if a
withdrawal queue has formed it means that 95% of all available liquidity has
been borrowed, which also means that the interest rate will be increasing by at
least 20% per day.

The interest rate will continue increasing until the withdrawal queue has been
fully processed and all exiting LPs have recovered their liquidity. The
interest rate can rise from 5% APY to 18% APY in just 7 days.

In most plausible scenarios where LPs are trying to exit, all LPs will receive
their liquidity within 7 days because the interest rate can move so
dramatically in that time period, which will strongly encourage borrowers to
return their liquidity and will also strongly encourage new LPs to deposit new
liquidity.

The worst case scenario is where all LPs wish to withdraw their liquidity, all
borrowers wish to keep their liquidity, no LPs are depositing new liquidity
into the source CPMM, and the current APY is 0.1%.

Even in this scenario, LPs will receive all of their liquidity within 140 days.
It will take roughly 63 days for the APY to increase from the minimum of 0.1%
to the maximum of 10,000%, and after that it will take roughly 77 days for the
total interest payments to equal the total amount of borrowed liquidity.
Because nobody in the withdrawal queue is earning interest, the interest
payments will be enough to process every LP attempting to withdraw.

### APY Attacks

An attacker may attempt to manipulate borrowers by borrowing lots of liquidity
to drive the APY up, potentially causing borrowers to run out of interest
liquidity unexpectedly. It takes roughly 4 days to double the APY, which gives
borrowers plenty of time to return liquidity.

4 days is also enough time for both existing LPs and potential new LPs to see
that the interest rate is increasing. In an efficient market, this will
typically cause a large amount of new liquidity to rush in. The attacker will
need to pay the higher interest rate on all of the new liquidity to keep the
attack going, making the attack very expensive to sustain.

Borrowers can add more interest liquidity to their exclusive CPMMs at any time.
They can also return any fraction of their borrowed liquidity to reduce the
cost of maintaining their position. This gives borrowers a lot of flexibility
in the face of an APY attack.

To avoid unexpected liquidation, borrowers should keep a healthy buffer of
interest liquidty in their exclusive CPMMs. Typically a healthy buffer is
between 2% and 5% of the total borrowed liquidity, less if the borrower is
frequently checking in on the status of their exclusive CPMM.

## Exclusive CPMM Slots

This implementation of Glowswap requires iterating over every exclusive CPMM
each time that anyone transacts with the source CPMM or any of the exclusive
CPMMs. To keep gas requirements under control, a limited number of exclusive
CPMMs are allowed to exist.

Specifically, Glowswap targets having 20 exclusive CPMMs, with a maximum of 40
exclusive CPMMs. When 40 exclusive CPMMs exist, the maximum gas required for
any single Glowswap operation will be less than 1.5 million gas.

To limit the number of exclusive CPMMs on Glowswap, each exclusive CPMM is
required to pay a flat slot fee. The slot fee is charged alongside the interest
rate for borrowing liquidity. Because the slot fee is a flat fee, it amortizes
better for exclusive CPMMs that are borrowing larger amounts of liquidity.

The slot fee will increase if there are more than 20 exclusive CPMMs borrowing
liquidity, and the slot fee will decrease if there are fewer than 20 exclusive
CPMMs borrowing liquidity.

### Exclusive CPMM Fee Adjustments

The slot fee has a minimum value of 1 liquidity per 30 days, and is initialized
to this value. The slot fee will adjust according to two different equations.

The equation for updating the fee when there are fewer than 20 exclusive CPMMs
is:

```
flat_fee *= (1-(20 - num_exclusive_cpmms)*0.01)^(days)
if flat_fee < 1 {
    flat_fee = 1
}
```

The equation for updating the fee when there are more than 20 exclusive CPMMs
is:

```
flat_fee *= (1+(num_exclusive_cpmms-20)*0.01)^(days)
```

The above equations mean that the slot fee can change by at most 20% per day.
It will change more rapidly as the number of exclusive CPMMs drifts further
away from the target number of exclusive CPMMs.

Similar to the interest rate for borrowing liquidity, the maximum value for the
number of days is 2. If nobody has transacted with Glowswap in 2 days, it means
that there is not much activity and the slot fee does not need to be changed
dramatically, so the fee will be adjusted as though two days have elapsed.

There is no maximum slot fee. At some point, the fee rises to a level where no
exclusive CPMM can afford to pay the fee anymore, and the exclusive CPMMs will
run out of interest liquidity and have their borrowed liquidity returned,
removing them from Glowswap.

### Creating a New Exclusive CPMM

To prevent attacks where attackers attempt to drive up the slot fee, exclusive
CPMMs need to pay an initialization fee. The equation for determining the
initialization fee is below:

```
joining_fee = flat_fee^(0.6+0.02*num_exclusive_cpmms)
```

If there are no exclusive CPMMs, a new exclusive CPMM will need to pay 2 days
worth of slot fees to be initialized. When there are 20 exclusive CPMMs, the
21st will need to pay exactly 1 month of slot fees to be initialized. And when
there are already 39 exclusive CPMMs, the 40th and final exclusive CPMM will
need to pay roughly 14 months worth of slot fees to be initialized.

The expectation is that the vast majority of exclusive CPMMs will be
initialized when there are between 18 and 22 total exclusive CPMMs. The sharply
increasing initialization fee makes it expensive for attackers to block
legitimate users, while also ensuring that a sufficiently motivated legitimate
user is still able to join.

All of the slot fees and initializtion fees are distributed to the LPs of the
source CPMM.

### The Utility of Limited Exclusive CPMM Slots

The original design for Glowswap used aggregated exclusive CPMMs that were much
more computationally efficient, and therefore could allow for an unlimited
number of exclusive CPMMS. Unfortunately, the design of aggregated exclusive
CPMMs was significantly constrained, resulting in unacceptable capital
inefficiency for borrowers.

The authors of this document believe it may be possible to create aggregated
exclusive CPMMs which are both computationally efficient and capital efficient,
but were unable to find acceptable tradeoffs by the deadline.

It was ultimately determined that the best decision was to limit the total
number of exclusive CPMMs so that large players would be able to achieve
maximum capital efficiency when working with Glowswap. 20 exclusive CPMMs is
not a massive number, but it is large enough to allow lots of healthy
competition between potential players and ensure that the interest rate for
borrowing liquidity remains high.

Future research will hopefully lead to designs that allow for both capital
efficiency as well as broad market pariticpation.

## Use Cases

Glowswap is closer to a financial platform than it is to a simple market maker.
There are many different ways that Glowswap can be used to benefit borrowers,
and this section demonstrates a number of different ways to get value from
borrowed liquidity.

### Pricing Heuristics

When a trader borrows liquidity from the source CPMM, they have to pay interest
on the liquidity. The value of the liquidity is always equal to
`2*SQRT(price)`. Therefore, at a price of 1 USDC token per GLW token, each unit
of liquidity has a value of 2 USDC tokens.

As the price of GLW tokens increases, the value of liquidity will increase, and
therefore the size of the interest payments will also increase. Specifically,
it is a square root relationship, which means the price of liquidity will
double each time that the price of GLW tokens quadruples.

As an example, a trader that borrows 10,000 USDC tokens and 10,000 GLW tokens
when the price is 1 USDC token per GLW token will have borrowed 10,000
liquidity, or $20,000 worth of assets. At 10% APY, the trader will need to pay
roughly $5.48 per day for this borrowed money.

If the price of GLW tokens suddenly quadruples, the price of liquidity will
double. Therefore the trader will need to pay $10.96 per day to keep the same
10,000 liquidity borrowed.

One interesting thing is that when the trader initially borrowed liqudity, the
value of the liquidity and the value of the underling assets was equal. The
trader borrowed 10,000 USDC tokens and 10,000 GLW tokens, which is equal to
10,000 liquidity. The assets themselves were worth a total of $20,000, and the
liquidity was also worth a total of $20,000.

After the price of GLW quadrupled, the trader has 10,000 USDC tokens and 10,000
GLW tokens, worth a total of $50,000. But the value of the liquidity that was
borrowed only increased to $40,000. This means that the trader is now only
paying interest on $40,000 worth of assets despite having control of $50,000
worth of assets. If the trader returns liquidity at this point, they will only
need to return $40,000 worth of assets, allowing them to keep the remaining
$10,000 worth of assets as profit.

### Leveraged Volatility Trading

Glowswap enables traders to easily get exposure to volatility in the price of
the underlying asset pair. If a trader borrows liquidity and creates an
exclusive CPMM, any price volatility in the source CPMM creates an arbitrage
opportunity for the trader.

Importantly, the only risk to the trader is the interest that they have to pay
on the borrowed liquidity. This is because the trader's obligation is to return
the liquidity that they borrowed, and the Constant Product Rule enforced by the
exclusive CPMM combined with the Law of Accumulating Liquidity ensures that the
trader will always have enough liquidity in the exclusive CPMM to return
everything that was borrowed.

Therefore, the trader's main goal when performing leveraged volatility trading
is to ensure that they can make enough money from volatility to cover the cost
of paying interest.

For example, let's say a trader borrows 10,000 USDC tokens and 10,000 GLW
tokens from the source CPMM at a price of 1 USDC token per GLW token and 10%
APY. At that price, they will be paying $5.48 per day in interest.

If the trader is executing 1 arbitrage transaction every hour, each arbitrage
transaction will need to make an average of 22.8 cents for the trader to make a
profit. For that to happen, the price of GLW token needs to change by about 1%
per hour.

If the trader executes 1 arbitrage transaction every 24 hours, each arbitrage
transaction will need to make more than $5.48 in revenue for the trader to make
a profit. For that to happen, the price of GLW token needs to change by about
5% per day.

If the trader executes 1 arbitrage transaction every 30 days, each arbitrage
transaction will need to make more than $164.40 in revenue for the trader to
make a profit. For that to happen, the price of GLW token needs to change by
about 27% each month.

The optimal trading strategy will require the trader to predict the future
price movements of the GLW asset, executing an aribtrage transaction
immediately before the price movements switch directions. Traders that are
better at predicting price movements and optimally timing arbitrage
transactions will make more money, and will therefore be able to borrow
liquidity at a higher interest rate, driving the interest rate up.

Anyone can be a trader trying to make optimal transactions. Glowswap itself can
benefit from the intelligence of the market without needing specific governance
to set parameters such as an optimal fee rate.

This means that, even absent other use cases for liquidity, the minimum
interest rate earned by LPs should be a function of the maximum value that can
be extracted through volatility trading.

### Collateralized Borrowing

Glowswap enables traders to borrow against their assets while retaining
exposure to any price appreciation.

For example, let's say there's a trader with 500 GLW tokens, the current price
is 1 USDC token per GLW token, and the current interest rate is 10% APY.

The trader could borrow 250 liquidity from the source CPMM, which has a value
of $500. The trader could execute this borrow by taking 500 USDC from the
source CPMM and then adding 125 of their own GLW tokens to create an exclusive
CPMM that has 250 liquidity. The net effect is:

+ The source CPMM puts 500 USDC tokens into the exclusive CPMM
+ The trader puts 125 GLW tokens into the exclusive CPMM
+ The exclusive CPMM has 500 USDC tokens and 125 GLW tokens; 250 liquidity
+ The source CPMM has loaned 250 liquidity to the trader via the 500 USDC tkens
+ The trader has to pay 27.4 cents per day in interest
+ The trader has 375 GLW tokens remaining

After setting up the exclusive CPMM, the trader can then exchange their
remaining 375 GLW tokens with the exclusive CPMM to receive 375 USDC. The
exclusive CPMM will end up holding 125 USDC and 500 GLW tokens.

In effect, the trader is paying 27.4 cents per day in interest to borrow 375
USDC tokens against their 500 GLW tokens. Because all 500 GLW tokens are still
in the exclusive CPMM, the trader still has exposure to the value of the GLW
tokens. The full portfolio of the trader is:

+ 125 USDC tokens (in the exclusive CPMM)
+ 500 GLW tokens (in the exclusive CPMM)
+ 375 USDC tokens (owned by the trader)
+ negative 250 liquidity (owed to the source CPMM)
+ 27.4 cents per day in interest owed

At a value of 1 USDC token per GLW token, the portfolio value is $500. That's
$1 per USDC token, $1 per GLW token, and $2 per liquidity. Notably, this is
equal the value of the trader's initial portfolio (just 500 GLW tokens), which
makes sense.

If the GLW token price changes to quadruple the original price, the value of
the portfolio will update to being worth $1500. That's because the USDC will
keep the same value, the liquidity will double in value to $1,000, and the GLW
tokens will quadruple in value to $2000.

Importantly, this means that the collateralized borrowing strategy on Glowswap
does not retain full exposure to the GLW token, because the liquidity increases
in value with the square root of the price of the GLW token, and this portfolio
has a liquidity debt. The upside to the trader for using Glowswap over a more
traditional collateralized borrowing platform is that there is no liquidation
risk. No matter what happens to the GLW token price, the trader's portfolio is
not touched until the trader either returns the liquidity or stops making
interest payments.

Furthermore, the relative potency of the liquidity debt decreases as the GLW
price continues to increase. At quadruple the price, the trader gets 75% of the
value that they would have received for keeping their original GLW tokens. At
16x the original price, the trader's portfolio will be 81.25% of the value that
it would have been if they had held onto their GLW tokens.

The trader also has much better downside protection. In fact, the absolute
worst outcome for the trader is if the GLW token price falls to one quarter of
the original price. At that price, the exclusive CPMM has no value at all and
the trader's entire portfolio is worth the $375 USDC that they withdrew from
their exclusive CPMM.

If the price falls even further, say to 1/16th of the original price, the
exclusive CPMM has value to the trader again. Each GLW token is worth $0.0625,
and each liquidity is worth $0.5, which means the whole portfolio is worth
$406.25. This happens because the debt starts decreasing in value faster than
the GLW tokens are decreasing in value.

The trader has a handful of parameters they can tweak to change the outcome of
this position. For example, by borrowing less USDC, they will be paying a lower
interest rate and also receiving more USDC per dollar spent on interest, at the
cost of receiving fewer USDC per GLW token supplied as collateral. On the other
hand, by borrowing more they can receive more USDC per GLW token of collateral,
but they will have to pay a higher interest rate per USDC received.

The optimal set of parameters will depend on the specific circumstances of the
trader.

### Leveraged Long Portfolios

Leveraged long portfolios are similar to collateralized borrowing portfolios,
except that the borrowed USDC tokens are used to purchase more GLW tokens.

For example, let's say there's a trader with 500 GLW tokens, the current price
is 1 USDC token per GLW token, and the current interest rate is 10% APY. Let's
use the same setup from the collateralized borrowing section, except that the
375 USDC is used to purchase 375 GLW tokens. The final portfolio is:

+ 125 USDC tokens (in the exclusive CPMM)
+ 500 GLW tokens (in the exclusive CPMM)
+ 375 GLW tokens (owned by the trader)
+ negative 250 liquidity (owed to the source CPMM)
+ 27.4 cents per day in interest owed

The trader can actually then exchange their 375 GLW tokens into their exclusive
CPMM, which will result in them pulling out another roughy 53.5 USDC. This
process can be repeated. In the limit, the trader ends up with an exclusive
CPMM that has roughly 933 GLW tokens and roughly 67 USDC tokens. Their final
portfolio is therefore:

+ 67 USDC tokens (in the exclusive CPMM)
+ 933 GLW tokens (in the exclusive CPMM)
+ negative 250 liquidity (owed to the source CPMM)
+ 27.4 cents per day in interest owed

At a value of 1 USDC token per GLW token, the portfolio value is $500, which is
the same value that the trader started with. But the trader now has exposure to
933 GLW tokens instead of 500 GLW tokens.

If the GLW token price changes to quadruple the original price, the value of
the portfolio will update to being worth roughly $2799. That's because the USDC
will keep the same value, the liquidity will double in value to $1,000, and the
GLW tokens will quadruple in value to $3732.

For a price of just 27.4 cents a day, the trader is able to greatly increase
their exposure to GLW tokens increasing in value.

Like collateralized borrowing, the trader can adjust the parameters of the
exclusive CPMM to change their portfolio. For example, by borrowing a smaller
amount of USDC, the trader can reduce the amount of interest they pay per unit
of leverage that they receive, at the cost of receiving a smaller amount of
total leverage.

### Leveraged Short Portfolios

Glowswap is a fully symmetric protocol, which means that leveraged short
positions can be constructed by doing the opposite of leveraged long positions.

For example, let's say that there's a trader with 500 USDC tokens, the current
price is 1 USDC token per GLW token, and the current interest rate is 10% APY.
The trader would like to create a portfolio is that is short the GLW token.

The trader could borrow 250 liquidity from the source CPMM, which has a value
of $500. The trader could execute this borrow by taking 500 GLW tokens and
putting them into the exclusive CPMM. The trader then supplements 125 USDC
tokens of their own to get the exclusive CPMM up to 250 liquidity. The net
result is:

+ The source CPMM puts 500 GLW tokens into the exclusive CPMM
+ The trader puts 125 USDC tokens into the exclusive CPMM
+ The exclusive CPMM has 500 GLW tokens and 125 USDC tokens; 250 liquidity
+ The source CPMM has loaned 250 liquidity to the trader via the 500 GLW tokens
+ The trader has to pay 27.4 cents per day in interest
+ The trader has 375 USDC tokens remaining

After creating this setup, the trader could exchange their remaining USDC
tokens with their exclusive CPMM for GLW tokens and then sell the GLW tokens.
The final result will be a portfolio that has:

+ 500 USDC tokens (in the exclusive CPMM)
+ 125 GLW tokens (in the exclusive CPMM)
+ 375 USDC tokens (owned by the trader)
+ negative 250 liquidity (owed to the source CPMM)
+ 27.4 cents per day in interest owed

The trader can then take the USDC tokens that they own and exchange them with
the exclusive CPMM, giving them even more GLW tokens to sell. This process can
be repeated a few times, eventually resulting in the exclusive CPMM having
roughly 933 USDC tokens and roughly 67 GLW tokens. Their final portfolio is
therefore:

+ 933 USDC tokens (in the exclusive CPMM)
+ 67 GLW tokens (in the exclusive CPMM)
+ negative 250 liquidity (owed to the source CPMM)
+ 27.4 cents per day in interest owed

Consistent with a short position, the portfolio loses value as the price of the
GLW token goes up, and gains value as the price of the GLW token goes down. The
portfolio has a local maximum value of $933 when the value of GLW tokens
reaches 0.

The worst case outcome for this portfolio is a GLW token price of roughly 13.92
USDC tokens. At this price, the portfolio has no value at all and the trader
has effectively lost $500 plus interest. Above that price, the portfolio
actually starts to gain value again, because the portfolio is exposed to
roughly 67 GLW tokens. At a price of roughly $41.77 per GLW token, the
portfolio reaches its original value of $500, and at a price of $55.69 per GLW
token the portfolio value rises above $933, meaning the best case outcome for
this portfolio is actually that the GLW token massively increases in value.

One major difference between Glowswap shorts and traditional shorts is the
downside risk. In a traditional short, the trader has unbounded downside risk,
which makes taking short positions on volatile assets incredibly risky. On
Glowswap, the trader has a well defined maximum downside risk, which makes
Glowswap shorts a much safer platform for shorting assets where truly anything
is possible.

## Implementation
