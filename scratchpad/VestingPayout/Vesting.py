
"""
Flow:
A GCA will have a vesting object dedicated for each rotation.
A rotation is an election cycle.
AKA the rotation starts when they get chosen to be a GCA and ends when they are no longer a GCA.
If they get reelected, a new rotation starts.
This is done purposefully as to not mess up the math for vesting.

The below flow is a per rotation basis.

1. GCA gets elected
2. GCA works x amount of time
3. GCA claims a payout for the first time for their rotation
    3a) The GCA receives some amount now and the rest is vested in "slashable" balance
    3b) The vesting object is created and stored in the GCA object
4. GCA works x amount of time
5. GCA claims a payout for the second time for their rotation
    5a) The GCA receives some amount now and we mutate the vesting object
        -   This combines the vesting object with the previous vesting object
        -   The goal of mutating the objects together is to essentially combine their vesting positions so we can have one vesting object per rotation
        -   This reduces gas and storage costs
6. Continue steps 4 and 5 until the rotation ends


Cons:
Can GCA's manipulate the time at which the claim to get more money or accelerate their vesting?

--TBD
"""


def weeks_in_seconds(weeks):
    return weeks * (86400 * 7)

#100 Weeks
total_vesting_time = weeks_in_seconds(100)


def min(a, b):
    if a < b:
        return a
    return b


"""
This corresponds to the manual array of vesting objects as defined in the notion doc.
We use this class to compare to the mutated object to make sure the math is correct.
"""
class VestingWithManualArrays:
    def __init__(self):
        self.vestingObjects = []
    
    def pushVestingObject(self, vestingObject):
        self.vestingObjects.append(vestingObject)
    
    def claimAllObjects(self):
        for vestingObject in self.vestingObjects:
            vestingObject.claimPayout()
    
    def sumOfAmountClaimed(self):
        sum = 0
        for vestingObject in self.vestingObjects:
            sum += vestingObject.amountClaimed
        return sum
    
    def warpForward(self, amount):
        for vestingObject in self.vestingObjects:
            vestingObject.warpForward(amount)


    

# TODO: make sure to think about having a nonce for when a gca starts a rotation
"""
The vesting object class that incorporates the additional logic of mutating the vesting object
"""
class Vesting:
    def __init__(self):
        self.rotationStart = 0
        self.timestamp = 0
        self.lastClaimedTimestamp = 0
        self.amountClaimed = 0
        self.totalAmount = 0
        self.vestStartTimestamp = 0

    def currentTimestamp(self):
        return self.timestamp
    
    def warpForward(self, amount):
        self.timestamp += amount


    def setTotalAmount(self, amount):
        self.totalAmount = amount

    def claimPayout(self):
        timeDiff = self.timestamp - self.lastClaimedTimestamp
        #1 % Per Week
        amount = min(self.totalAmount * min(1,(timeDiff / total_vesting_time)), self.totalAmount - self.amountClaimed)
        self.amountClaimed += amount
        self.lastClaimedTimestamp = self.timestamp

    def combineVestingObject(self, vestingObject):
        self.claimPayout()
        self.lastClaimedTimestamp = vestingObject.lastClaimedTimestamp + self.lastClaimedTimestamp
        self.amountClaimed = vestingObject.amountClaimed + self.amountClaimed
        self.totalAmount = vestingObject.totalAmount + self.totalAmount
        self.vestStartTimestamp = vestingObject.vestStartTimestamp


    def addVestingPosition(self, amount, vestStartTimestamp):
        self.totalAmount += amount
        self.vestStartTimestamp = vestStartTimestamp


    
    def setVesting(self, rotationStart, timestamp, lastClaimedTimestamp, amountClaimed, totalAmount, vestStartTimestamp):
        self.rotationStart = rotationStart
        self.timestamp = timestamp
        self.lastClaimedTimestamp = lastClaimedTimestamp
        self.amountClaimed = amountClaimed
        self.totalAmount = totalAmount
        self.vestStartTimestamp = vestStartTimestamp


    def __str__(self):
        return "timestamp: " + str(self.timestamp) + "\n" + \
            "lastClaimedTimestamp: " + str(self.lastClaimedTimestamp) + "\n" + \
            "amountClaimed: " + str(self.amountClaimed) + "\n" + \
            "totalAmount: " + str(self.totalAmount) + "\n" + \
            "vestStartTimestamp: " + str(self.vestStartTimestamp) + "\n"
    


def test_mutatedObject():

    vesting = Vesting()
    vesting.setTotalAmount(100)
    vesting.warpForward(weeks_in_seconds(10))

    otherVesting = Vesting()
    #{rotationStart: 0, timestamp: vesting.timestamp, lastClaimedTimestamp: 0, amountClaimed: 0, totalAmount: 40, vestStartTimestamp: 86400}
    otherVesting.setVesting(vesting.rotationStart, vesting.timestamp, 0, 0, 40, 86400)
    vesting.combineVestingObject(otherVesting)
    vesting.warpForward(weeks_in_seconds(10))
    vesting.claimPayout()
    print(f"[mutated] amountClaimed: {vesting.amountClaimed}")
    # vesting.warpForward(weeks_in_seconds(90))
    # vesting.claimPayout()
    # print(vesting)
    return vesting.amountClaimed

def test_manual():
    vesting = Vesting()
    vesting.setTotalAmount(100)
    vesting.warpForward(weeks_in_seconds(10))
    vestingArrayManual = VestingWithManualArrays()
    vestingArrayManual.pushVestingObject(vesting)

    vestingArrayManual.claimAllObjects()
    print(vestingArrayManual.sumOfAmountClaimed())
   

    vesting2 = Vesting()
    vesting2.setVesting(vesting.rotationStart, vesting.timestamp, vesting.timestamp, 0, 40, 86400)
    vestingArrayManual.pushVestingObject(vesting2)

    vestingArrayManual.warpForward(weeks_in_seconds(10))
    vestingArrayManual.claimAllObjects()
    print(f"[manual] amountClaimed: {vestingArrayManual.sumOfAmountClaimed()}")

    return vestingArrayManual.sumOfAmountClaimed()
    # print(vestingArrayManual.vestingObjects[0])
    # print(vestingArrayManual.vestingObjects[1])




manual_amount_claimed = test_manual()
mutated_amount_claimed = test_mutatedObject()
assert(manual_amount_claimed == mutated_amount_claimed)
