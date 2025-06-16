# Miner Pool Bucket States
This document gives a brief intro into "glow buckets" and  includes a non-exhaustive lists of possible states buckets in the glow ecosystem can be as it related to:
1. Start Submission Times
2. End Submission Times
3. Finalization Timestamps

The target audience for this do includes
* Auditors
* Core Team 
* Developers

## Preface
Buckets in the glow ecosystem contain information about reward distribution to the miners. Under normal conditions, a bucket is open for exactly one week, is reviewed for exactly one week, and is then finalized past the review.

Three mechanics have been added to ensure that no buckets can pass through.

1. The ability to delay a bucket.
    - This adds 13 weeks to a bucket's finalization timestmap and does not permit for resubmission on its own.
2. The ability to request a bucket for resubmission
    - This adds 2 weeks to the finalization timestamp and to the end submission timestamp.
3. The ability to increment a slash nonce
    - Incrementing a slash nonce invalidates all buckets that have not yet been finalized. This includes buckets that are not delayed, are delayed, are requested for resubmission, or any combination of those above. 
    - Incrementing a slash nonce ensures that all buckets that were invalidated have at least 1 week, and at most 2 weeks to have reports resubmitted.

## High Level Invariants
* Once a bucket is recognized as finalized, it can never be unfinalized.

## Low Level Invariants
* Once a bucket is finalized, its `newNonce` from `getBucketSubmissionRange` can never change.
* Finalization timestamp for each bucket can never be less than the `startSubmissionTimestamp(bucketId) + 2 weeks`
    - This is checking the finalization in `getBucketSubmissionRange(bucketId)`
* A bucket can only be delayed or resubmitted once per slash nonce
* A bucket that has not updated its reports after a slash happened before its finalization cannot be claimed from in `MinerPoolAndGCAV2.claimedRewardFromBucket(....)`
* Finalized buckets should never be affected from a slash
* All unfinalized buckets should be able to be resubmitted if a slash happens before finalization
    - More specifically between `slashNonceToSlashTimestamp[slashNonce]` - WCEIL(slashNonce)`
* A bucket can only be delayed once per slash nonce.
* A bucket can only be requested for resubmission once per slash nonce.
* A bucket that is delayed at a slash nonce cannot be requested for resubmission at the same slash nonce.



### Understanding "WCEIL"
WCEIL is a helper term.


WCEIL is equal to the current bucket + 2. When a slash happens, all buckets that were invalidated have until WCEIL to resubmit their reports. 

In addittion, the finalization of the bucket is pushed to the max(WCEIL+2,finalizationTimestamp), to ensure that there is enough time to resubmit the report. 


### Theory Questions Yet To Be Resolved 
* What happens if a bucket is finalized with empty reports.
    - Roll into the next week ? (Probably a bit complex on engineering side)
    - Should veto council keep delaying the bucket until a report is submitted?
    - Should there be a fallback contract?
    - Can add into a glowswap pool?


## Examples
Full Happy Path
* Submit: n - n+1
* Review: n+1 - n+2
* Finalize: n+2

Delay and no Slash
* Submit: n - n+1
* Delay: n+1 - n+2
* Finalize: n+15

Delay and Slash no WCEIl
* Submit: n - n+1
* Delay: n+1
* Slash: n+6
* Submit: n+6 - n+8 
* Review: n+8 - n+9
* Finalize: n+15


Delay and Slash with WCEIl
* Submit: n - n+1
* Delay: n+1 
* Slash: n+14 
* Submit: n+14 - n+16
* Finalize: n+17


Request Resubmission Happy
* Submit: n - n+1
* Request Resubmission: n+1
* Submit: n+2 - n+3
* Review: n+3 - n+4
* Finalize: n+4

Request Resubmission + Delay
* Submit: n - n+1
* Request Resubmission: n+1
* Submission: n+2 - n+3
* Delay: n+3
* Finalize: n+17

Request Resubmission + Delay + Slash
* Submit: n - n+1
* Request Resubmission: n+1
* Submission: n+2 - n+3
* Delay: n+3
* Slash: n+6
* Submit: n+6 - n+8
* Review: n+8 - n+9
* Finalize: n+17

Request Resubmission + Delay + Slash + WCEIl
* Submit: n - n+1
* Request Resubmission: n+1
* Submission: n+2 - n+3
* Delay: n+3
* Slash: n+16
* Submit: n+16 - n+18
* Review: n+18 - n+19
* Finalize:  n+19


Normal Submission + Slash (Bucket 1 This time)
* Submit: n+1 - n+2
* Review: n+2 - n+3
* Slash: n+2.5
* Submit: n+2.5-n+4
* Review: n+4 - n+5
* Finalize: n+5



Normal Submission + Resubmission + Slash
* Submit: n+1 - n+2
* Request Resubmission: n+2
* Submission: n+3 - n+4
* Review: n+4 - n+5
* Slash: n+4.5
* Submit: n+4.5 - n+6
* Review: n+6 - n+7
* Finalize: n+7



Delay + Slash + Delay ....
* Submit: n - n+1
* Delay: n+1 (finalization now = n+15)
* Slash: n+6  
* Submit: n+6 - n+8
* Slash: n+8
* Submit: n+8 - n+10
* Delay: n+10
* Finalize: n+28 (n+15+13 = n+28)

Delay + Slash + Resubmission no WCEIL
* Submit: n - n+1
* Delay: n+1 (finalization = n+15)
* Slash: n+6
* Submit: n+6 - n+8
* Request Resubmission: n+8
* Submission: n+8 - n+10
* Request for Resubmission: n+10
* Submission: n+10 - n+12
* Review: n+12 - n+13
* Finalize: n+17  (n+15+2)


Delay + Slash + Resubmission + WCEIL
* Submit: n - n+1
* Delay: n+1 (finalization = n+15)
* Slash: n+14 (makes finalization = n+17)
* Submit: n+14 - n+16 
* Request Resubmission: n+16
* Submission: n+16 - n+18
* Review: n+18 - n+19
* Finalize:  n+19 (n+17+2)


