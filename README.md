# Glow Contracts

## Constants

```Decimals = 18;```

```Transferrable Balance = User Balance - Karma Balance```

We started on the implementation of a simple ERC20
which mocked GCC. Should allow users to retire tokens (increasing karma and nominations, while decreasing transferrable balance) and allow some external contracts to use the nominations.


## Nominations and Half Life
Nominations will have a half life function implemented which we did not get to.

That will be a challenge using uint's only (since sol doesen't have floats), but we may be able to pull some fun math to get there.

Maybe we can use taylor series, and if that doesen't work, some sort of step functions.

## Karma
When user retires GCC they will earn Karma.
1 * 1eDECIMALS Karma = 1 Metric Ton of CO2




We fork openzeppelin's ```ERC20``` into ```src/GCCERC20``` and add a few mappings and custom functions.

Our main token lies in ```src/Token.sol```

The first is, we track people's nominations. 

The second is we track Karma.

A user's transferrable balance should be  ```(TOTAL BALANCE - KARMA)```

Note: When a user retires GCC, it may be better to burn it to deduct balance, karma can then just represent number burned. This is outlined
in the Token.sol contract.

## Testing:
We adding very simple tests to make sure that user's couldn't transfer more than their transferrable balance (```balance - karma```)

We definitely will add more tests but only spent around 40 mins working on code.