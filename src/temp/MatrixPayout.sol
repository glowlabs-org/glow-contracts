// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "forge-std/console.sol";

struct GcaRewardTracker {
    uint64 lastUpdateTimestamp;
    // uint64 maxClaimTimestamp;
    uint192 slasheableBalance;
}

contract MatrixPayout {
    
    //5x5 matrix array
    address[5] gcas;
    
    uint256 private _packedUint1;
    uint256 private _packedUint2;
    uint256 private constant UINT16_MASK = (1<<16)-1;
    uint256 private constant GCA_ZERO_MASK_ONE = ~((1<< 6*16) -1 | ((UINT16_MASK) << 5*16) | ((UINT16_MASK) << 10*16));
    uint256 private constant GCA_ZERO_MASK_TWO = ~((UINT16_MASK | ((UINT16_MASK) << 5*16)));

    uint256 private constant GCA_ONE_MASK_ONE = ~((((1<<5*16) -1) << 5) | (UINT16_MASK << 1) | ((UINT16_MASK) << 10));
    uint256 private constant GCA_ONE_MASK_TWO = ~((UINT16_MASK) << 1 | ((UINT16_MASK) << 5));

    //TODO: Add the rest of the masks, this is only a POC.
    uint256 private constant rewardsPerSecond = 1 ether;
    uint256 private constant WEEKLY_PAYOUT_PERCENT_NUMERATOR = 100; //base 10,000
    uint256 private constant VESTING_PERIOD_LENGTH = 365 days;
    mapping(address => uint) public realizedPayout;//mock GLW
    mapping(address => GcaRewardTracker) private gcaRewardTracker;


    uint256 private constant SHARE_ENTRY_PER_PLAN = 50_000;

    constructor() {
        gcas[0] = address(0x1);
        gcas[1] = address(0x2);
        gcas[2] = address(0x3);
        gcas[3] = address(0x4);
        gcas[4] = address(0x5);
        gcaRewardTracker[address(0x1)] = GcaRewardTracker(uint64(block.timestamp),0);
        gcaRewardTracker[address(0x2)] = GcaRewardTracker(uint64(block.timestamp),0);
        gcaRewardTracker[address(0x3)] = GcaRewardTracker(uint64(block.timestamp),0);
        gcaRewardTracker[address(0x4)] = GcaRewardTracker(uint64(block.timestamp),0);
        gcaRewardTracker[address(0x5)] = GcaRewardTracker(uint64(block.timestamp),0);
        testSetToEqual();
       
    }

    function _max(uint64 a, uint64 b) internal pure returns(uint) {
        if(a>b) return a;
        return b;
    }
    function _min(uint64 a, uint64 b) internal pure returns(uint) {
        if(a<b) return a;
        return b;
    }
    function claimForAll() public {
        uint256[5][5] memory matrix = getPayoutMatrix();
        uint _totalShares = totalShares();
        uint _rwp = rewardsPerSecond;
        for(uint i; i<5;++i) {
            GcaRewardTracker memory tracker = gcaRewardTracker[gcas[i]];
            uint timeElapsed = block.timestamp - tracker.lastUpdateTimestamp;
            uint totalRewardToGiveout = _rwp * timeElapsed;
            address _gca = gcas[i];
            if(_gca == address(0)) continue;
            uint shares = _findTotalSharesOfGCA(i, matrix);
            uint totalRewardForGCA = totalRewardToGiveout * shares / _totalShares;
            uint rewardToGive = totalRewardForGCA * timeElapsed / VESTING_PERIOD_LENGTH;
            uint slashableAmount = totalRewardForGCA - rewardToGive; 
            realizedPayout[_gca] += rewardToGive;
            tracker.lastUpdateTimestamp = uint64(block.timestamp);
            tracker.slasheableBalance += uint192(slashableAmount);
            gcaRewardTracker[_gca] = tracker;
        }




    }
    
    function numActiveGCAs() internal view returns(uint n) {
        for(uint i; i<5;++i) {
            if(gcas[i] != address(0)) ++n;
        }
    }
    function removeGCAZero() public {
        claimForAll();
        uint _p1 = _packedUint1;
        uint _p2 = _packedUint2;
        uint sumOfZeroShares =  sumOfAgentInPayoutMatrix(0);
        uint sharesBefore = totalSharesFromP1andP2(_p1,_p2);
        _p1 = _p1 & GCA_ZERO_MASK_ONE;
        _p2 = _p2 & GCA_ZERO_MASK_TWO;
        uint sharesSupposedToHave = (numActiveGCAs() - 1) * SHARE_ENTRY_PER_PLAN;
        gcas[0] = address(0);
        console.log("sumOfZeroShares = %s", sumOfZeroShares);
        uint sharesAfter = sharesBefore - sumOfZeroShares;
    
        //we need to recalibrate the shares to be 10_000 each.
        for(uint i; i<15;++i) {
            uint val = (_p1 >> (16*i)) & (UINT16_MASK);
            if(val == 0) continue;
            uint newShare = val *  sharesSupposedToHave / sharesAfter;
            _p1 = _p1 & ~(UINT16_MASK << (16*i));
            _p1 = _p1 | (newShare << (16*i));
        }

        for(uint i; i<10;++i) {
            uint val = (_p2 >> (16*i)) & (UINT16_MASK);
            if(val == 0) continue;
            uint newShare = val *   sharesSupposedToHave / sharesAfter;
            _p2 = _p2 & ~(UINT16_MASK << (16*i));
            _p2 = _p2 | (newShare << (16*i));
        }
        uint dust = sharesSupposedToHave -  totalSharesFromP1andP2(_p1, _p2);

        //TODO: Give the dust to someone who will actually be able to use it.
        uint valAtP00 = (_p1) & (UINT16_MASK);
        valAtP00 = valAtP00 + dust;
        _p1 = _p1 & ~(UINT16_MASK);
        _p1 = _p1 | valAtP00;
        _packedUint1 = _p1;
        _packedUint2 = _p2;

    }
        
    function testSetToEqual() public {
        uint sizeOfSlot = 16;
        uint totalSlotsInUint1 = 15;
        uint totalSlotsInsideUint2 = 10;

        uint _packedOne;
        for(uint i; i<totalSlotsInUint1;++i) {
            _packedOne |= (SHARE_ENTRY_PER_PLAN/5 << (sizeOfSlot*i));

        /*
            [2000,2000,2000,2000,2000]
            [2000,2000,2000,2000,2000]
            [2000,2000,2000,2000,2000]
        */
        }

        uint _packedTwo;
        for(uint i; i<totalSlotsInsideUint2;++i) {
            if(i == 4 || i ==9) continue;
            _packedTwo |= (SHARE_ENTRY_PER_PLAN/4 << (sizeOfSlot*i));
            /*
            [2500,2500,2500,2500,0]
            [2500,2500,2500,2500,0]
            */
        }
        
        /*

            [2000,2000,2000,2000,2000]
            [2000,2000,2000,2000,2000]
            [2000,2000,2000,2000,2000]
            [2500,2500,2500,2500,0]
            [2500,2500,2500,2500,0]
        */
        _packedUint1 = _packedOne;
        _packedUint2 = _packedTwo;
    }

    function getPayoutMatrix() public view returns(uint256[5][5] memory matrix) {
        unchecked{

            uint _packedOne = _packedUint1;
            for(uint i; i<15;++i) {
            uint _row = i / 5;
            uint _col = i % 5;
            matrix[_row][_col] = (_packedOne >> (16*i)) & (UINT16_MASK);
        }
        
            uint _packedTwo = _packedUint2;
            for(uint i; i<10;++i) {
                uint _row =  i/5 + 3;
                uint _col = i % 5;
                matrix[_row][_col] = (_packedTwo >> (16*i)) & (UINT16_MASK);
            }
        }
    }

    function sumOfAgentInPayoutMatrix(uint gcaNumber) public view returns(uint) {
        uint _p1 = _packedUint1;
        uint _p2 = _packedUint2;

        uint sum;

        for(uint i; i<15;++i) {
            uint _row = i / 5;
            uint _col = i % 5;
            if(_row == gcaNumber|| _col == gcaNumber) {

                sum += (_p1 >> (16*i)) & (UINT16_MASK);
            }
         
        }

        for(uint i; i<10;++i) {
            uint _row =  i/5 + 3;
            uint _col = i % 5;
            if(_row == gcaNumber|| _col == gcaNumber) {
                sum += (_p2 >> (16*i)) & (UINT16_MASK);
            }
        }
        return sum;
    }

    function findTotalSharesOfGCA(uint gcaNumber) public view returns(uint) {
        uint[5][5] memory matrix = getPayoutMatrix();
        uint _totalShares;
        for(uint i; i<5;++i) {
          _totalShares += matrix[i][gcaNumber];
            
        }
        return _totalShares;
    }

    function _findTotalSharesOfGCA(uint gcaNumber,uint256[5][5] memory matrix) internal pure returns(uint) {
        uint _totalShares;
        for(uint i; i<5;++i) {
          _totalShares += matrix[i][gcaNumber];
            
        }
        return _totalShares;
    }
    function findGCATotalSharesByAddress(address _gca) external view returns(uint) {

        uint gcaNumber = findIndexOfGCA(_gca, gcas);
        return findTotalSharesOfGCA(gcaNumber);
    }
    /*
    matrix[0] = [0,0,0,0,0]
    matrix[1] = [0,0,0,0,0]
    matrix[2] = [0,0,0,0,0]
    matrix[3] = [0,0,0,0,0]
    matrix[4] = [0,0,0,0,0]
    we have a 5x5
    */
    // function submitPlan(address[] calldata _gcas, uint[] calldata amounts) external {

    // }


    function findIndexOfGCA(address _gca, address[5] memory _gcas) public pure returns(uint) {
         unchecked{
             for(uint i; i<_gcas.length;++i)  {
                 if(_gca == _gcas[i]) return i;
             }
             revert("Not Found");
         }
    }
    function totalShares() public view returns(uint256) {
        uint _totalShares;
        uint _p1 = _packedUint1;
        uint _p2 = _packedUint2;
        for(uint i; i<15;++i) {
            _totalShares += (_p1 >> (16*i)) & (UINT16_MASK);
        }
        for(uint i; i<10;++i) {
            _totalShares += (_p2 >> (16*i)) & (UINT16_MASK);
        }
        return _totalShares;
    }
    function totalSharesFromP1andP2(uint _p1,uint _p2) internal pure returns(uint256) {
        uint _totalShares;
        for(uint i; i<15;++i) {
            _totalShares += (_p1 >> (16*i)) & (UINT16_MASK);
        }
        for(uint i; i<10;++i) {
            _totalShares += (_p2 >> (16*i)) & (UINT16_MASK);
        }
        return _totalShares;
    }
    function castUintToAddress(uint160 _uint) public pure returns(address) {
        return address(_uint);
    }

    function getAllRealizedPayouts() public view returns(uint[5] memory balances) {
        for(uint i; i<5;++i) {
            balances[i] = realizedPayout[gcas[i]];
        }
    }
    
    function getActiveGcaRewardTrackers() public view returns(GcaRewardTracker[] memory trackers) {
        uint numGCAs;
        GcaRewardTracker[] memory _trackers = new GcaRewardTracker[](5);
        for(uint i; i<5;++i) {
            if(gcas[i] != address(0)) {
                _trackers[numGCAs] = gcaRewardTracker[gcas[i]];
                ++numGCAs;
            }
        }

        assembly{
            mstore(_trackers,numGCAs)
        }
        
        return _trackers;
    }
}



/*
---0----1-----2---3----4---
0-2000,2000,2000,2000,2000,
1-2000,2000,2000,2000,2000,
2-2000,2000,2000,2000,2000,
3-2500,2500,2500,2500,0000
4-2500,2500,2500,2500,0000
*/