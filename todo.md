
---- 
## Things that need to be migrated
* USDG Balances
    * LP balances will go to ERC20 LP holders
* Glow Balances
    * LP balances will go to ERC20 LP holders
    * Need to account for faulty weeks in the glow contract
    * Need to account for unclaimed rewards (compare with bitmap)
* GCC Balances
    * LP balances will go to ERC20 LP holders
    * Ensure carbon credit auction has no more GCC in it.
    * Migrate impact power
* Governance    
    * Migrate nominations
    * Migrate proposals ???? 
* MinerPoolAndGCA
    * Payout all the GCAs and no vesting
    * Migrate the members
* Veto Council
    * Payout all the veto council members and no 
        * Make sure to set their last paid timestamp;
    * Migrate the members;

* Allowlist the most popular multisig codehashes
* Fix Carbon Credit Auction Bug
* Find a way to import old state into the guard v2 contract
    * Governance + MinerPoolAndGCA Reports
    * Could import manually into a function ❌
    * Could import into the constructor ❌
    * Can point back to the V1 contract or revert? ✅
    * Etiher way, will need a revert statement on any buckets included in the v1 contract ❌
* Remove the genesis v2 timestamp in places where it does not apply ✅
* Remember to import the correct vesting schedules in glow guarded v2 ✅
* Remove Upgrading USDG From Glow Guarded V2

------
* For early liquidity - make sure it reads balance from the old contract ✅
* We could do the same in the constructor of glow. 
* Buyout the carbon credit auction


---- 
## V2 TODOS 
* Make sure that claim reward function is protected by an approved claimer;

* Inside GCA V1, there was a bug where WCEIL of the slash nonce timestamp is based
on the creation timestamp of the proposal, and not the execution timestamp.
This means that after a slash, we will never be able to resubmit a weekly report,
because it will have been AT LEAST 5 weeks for Governance to kick in.

* Make sure that we switch the delay period to 16 weeks, not 13.


-----
##  Nice To Haves
* Remove sigs and find a better system



