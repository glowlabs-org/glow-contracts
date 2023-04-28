## Glow Contracts

We started on the implementation of a simple ERC20
which mocked GCC.

We fork ERC20 and add a few mappings and custom functions.

The first is, we track people's nominations. 

The second is we track Karma.

A user's transferrable balacne should be  ```(TOTAL BALANCE - KARMA)```

Note: When a user retires GCC, it may be better to burn it to deduct balance, karma can then just represent number burned.