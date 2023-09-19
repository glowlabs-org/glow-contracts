week_in_seconds = 604800

def between(bottom,value,top):
    return bottom <= value and value < top

# class Report:
#     def __init__(self,)
def WCEIL_SubmissionStartTimestamp(timestampOfSlash:int):
    t = ((timestampOfSlash //  week_in_seconds) * week_in_seconds) + (week_in_seconds * 2)
    return t

class Bucket:
    def __init__(self, id,bucketOriginNonce:int):
        self.id = id
        self.bucketOriginNonce = bucketOriginNonce
        self.lastUpdatedNonce = bucketOriginNonce
        self.submissionStartTimestamp = 0
        self.submissionEndTimestamp = 604800
        self.finalizationTimestamp = 604800 * 2
        self.reports = []
        self.currentTimestamp = 0
        self.globalNonce = bucketOriginNonce
        self.slashNonceToSlashTimestamp = {}
        self.genesisTimestamp = 0
    
    def print(self):
        print(f"id: {self.id}, bucketOriginNonce: {self.bucketOriginNonce}")
        print(f"lastUpdatedNonce: {self.lastUpdatedNonce}")
        print(f"submissionStartTimestamp: {self.submissionStartTimestamp}")
        print(f"submissionEndTimestamp: {self.submissionEndTimestamp}")
        print(f"finalizationTimestamp: {self.finalizationTimestamp}")
        print(f"reports: {self.reports}")
        print(f"currentTimestamp: {self.currentTimestamp}")
        print(f"globalNonce: {self.globalNonce}")
        print(f"slashNonceToSlashTimestamp: {self.slashNonceToSlashTimestamp}")
        print(f"genesisTimestamp: {self.genesisTimestamp}")
        print(f"finalized: {self.isFinalized()}")
    
    def executeSlashEvent(self):
        self.slashNonceToSlashTimestamp[self.globalNonce] = self.currentTimestamp
        self.globalNonce += 1
    
    def warpForward(self,timeToWarp:int):
        self.currentTimestamp += timeToWarp

    def isFinalized(self):
        if self.lastUpdatedNonce != self.globalNonce:
            if self.slashNonceToSlashTimestamp[self.lastUpdatedNonce] >= self.finalizationTimestamp and self.currentTimestamp >= self.finalizationTimestamp:
                return True
        if self.lastUpdatedNonce == self.globalNonce:
            return self.currentTimestamp >= self.finalizationTimestamp
        return False
    

    def pushReport(self,reportData):
        if self.currentTimestamp > self.calculateBucketSubmissionStartTimestamp():
            raise Exception("Current Timestamp > Last Possible Submission Timestamp")
        if self.lastUpdatedNonce != self.globalNonce:
            self.reports.clear()
            self.lastUpdatedNonce = self.globalNonce
        self.reports.append(reportData)
        return True

    
    def calculateBucketSubmissionStartTimestamp(self):
        if self.bucketOriginNonce == self.globalNonce:
            return self.submissionEndTimestamp
        
        if self.lastUpdatedNonce == self.globalNonce:
            return WCEIL_SubmissionStartTimestamp(self.slashNonceToSlashTimestamp[self.lastUpdatedNonce])
        
        latestSubmissionStartTimestamp = self.submissionStartTimestamp
        finalizationTimestamp = self.finalizationTimestamp
        for i in range(self.lastUpdatedNonce,self.globalNonce):
            if between(latestSubmissionStartTimestamp,self.slashNonceToSlashTimestamp[i],finalizationTimestamp):
                latestSubmissionStartTimestamp = WCEIL_SubmissionStartTimestamp(self.slashNonceToSlashTimestamp[i])
                finalizationTimestamp = max(latestSubmissionStartTimestamp + ( week_in_seconds*1), finalizationTimestamp)
            else:
                break

        self.finalizationTimestamp = finalizationTimestamp
        self.submissionEndTimestamp = latestSubmissionStartTimestamp
        return latestSubmissionStartTimestamp
    



            
def test_bucketMultipleSlashes():
    bucket = Bucket(0,0)
    bucket.warpForward(week_in_seconds * 2 - 10)
    bucket.executeSlashEvent()
    latestSubmissionTimestampAfterSlash = bucket.calculateBucketSubmissionStartTimestamp()
    bucket.print()
    assert(latestSubmissionTimestampAfterSlash == week_in_seconds * 3)
    assert(bucket.isFinalized() == False)

    #No we are 9 seconds away from the original finalization timestamp
    bucket.warpForward(1)
    bucket.executeSlashEvent()
    latestSubmissionTimestampAfterSlash = bucket.calculateBucketSubmissionStartTimestamp()
    # bucket.print()
    # print("-----------------")
    assert(latestSubmissionTimestampAfterSlash == week_in_seconds * 3)
    assert(bucket.isFinalized() == False)

    #--------------------------------------------# 
    bucket.warpForward(50)
    bucket.executeSlashEvent()
    latestSubmissionTimestampAfterSlash = bucket.calculateBucketSubmissionStartTimestamp()
    bucket.pushReport(32)
    bucket.warpForward(week_in_seconds * 4)
    # Should be true since we now pushed
    # the bucket can;t be finalized if not
    assert(bucket.isFinalized() == True)



#------------BUCKET 2-----------------#
def test_bucketNormalShouldFinalizeNormally():
    bucket = Bucket(0,0)
    #Since we haven't reached finaization timestamp it should be false
    bucket.warpForward(week_in_seconds)
    assert(bucket.isFinalized() == False)
    bucket.warpForward(week_in_seconds)
    # #Since we have reached the finalization timestamp it should be finalized
    assert(bucket.isFinalized() == True)
    bucket.executeSlashEvent()
    # # #Slash Event Happens after so it should still be finalized
    # bucket.print()
    assert(bucket.isFinalized() == True)


def test_pushReportDataShouldUpdateNonceAndClearOldDataIfNotInSync():
    bucket = Bucket(0,0)
    bucket.pushReport(10)
    bucket.pushReport(20)
    assert(len(bucket.reports) == 2)
    
    bucket.warpForward(week_in_seconds)
    bucket.executeSlashEvent()

    #Old reports should be gone since there was a slash event
    bucket.pushReport(10)
    assert(len(bucket.reports) == 1)

    assert(bucket.lastUpdatedNonce == bucket.globalNonce)

    #Let's sanity check and make sure the bucket isn't finalized
    assert(bucket.isFinalized() == False)

    ##Let's Try this two more times to see if it can handle multiple rounds
    bucket.warpForward(100)
    bucket.executeSlashEvent()
    bucket.warpForward(100)
    bucket.executeSlashEvent()

    assert(bucket.isFinalized() == False)
    assert(bucket.lastUpdatedNonce != bucket.globalNonce)
    assert(len(bucket.reports) == 1)

    bucket.pushReport(4000)

    assert(bucket.isFinalized() == False)
    assert(bucket.lastUpdatedNonce == bucket.globalNonce)
    assert(len(bucket.reports) == 1)
    assert(bucket.reports[0] == 4000)

    #Since all the slash events happened inside the original submission window,
    #our latest submission timestamp should be one week after our original finalization
    #since our original finalization was week_in_seconds * 2, this should be week_in_seconds * 3
    assert(bucket.submissionEndTimestamp == week_in_seconds * 3)

    #our finalization timestamp should be one week after the end of submission (unless the bucket's been delayed -- but that is another case)
    assert(bucket.finalizationTimestamp == week_in_seconds*4)





print("-----------------")

# if __name__ == "main":
test_bucketMultipleSlashes()
test_bucketNormalShouldFinalizeNormally()
test_pushReportDataShouldUpdateNonceAndClearOldDataIfNotInSync()