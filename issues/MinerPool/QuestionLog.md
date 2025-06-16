# Miner Pool And GCA Question Log

## Bucket Finalization Questions

1. If a bucket is is delayed, and then a slash happens, can it then be delayed it a GCA hasn't resubmit a report?

Setting:
* Week 0 (n) - Bucket Is Submit (Finality = n+2)
* Week 1.9 - Bucket is Finalized
* Bucket finalization pushed to n+15
* Week 6 - Slash Happens
* GCA Submission period now open from (Week 6 - Week 8)
    * Side Question: Should we keep it like this, or should we make it so that endSubmissionTimestamp is always (finalizationTimestamp - 1 week)
    * The first implementation (week 6 - week 8) makes sure that GCAs have at least one week to submit a new report, but it doesen't finalize until that n+15 finalization timestamp. The idea is that if there is a backlog of reports, the Veto council should have enough time to review everything.
* Week 7 - 

We are not in Week 7 where we know the bucket can be resubmit by GCAs. The question is, if the GCA doesn't resubmit the report, can the bucket be delayed again? (Currently , it can)



2. Salary Slashing Mechanic For Resubmission

If a GCA decides to resubmit their report during a `resubmission` period, they are to be slashed 20,000 GLOW from their payouts. Should this apply to all GCAs that resubmit in the resubmission period?

If there are 5 GCAs, and they all feel like they should resubmit their reports, should the total slash amount be 100,000 (20,000 / GCA), or a lump sum of 20,000 GLOW?

For implementation purposes, the former is more simple since there is no balancing algorithm. The latter would require a balancing algorithm to make sure that the total slash amount is 20,000 GLOW.


3. Sent to david via telegram `On the topic of implementation bias and v1:

I wanted to confirm this with you.
`

Based on David's response, we need to check 2 things.
* make sure that a bucket where `nweSlashNonce` != bucket.lastUpdatedNonce either overrides bucket() and sets the report and bucket tracker to zero, or, we make sure that `isFinalized` returns false. I don't have a preference towards netiher.4