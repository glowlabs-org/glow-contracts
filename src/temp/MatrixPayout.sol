// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "forge-std/console.sol";

contract MatrixPayout {
    
    //5x5 matrix array
    address[5] gcas;
    
    uint256 private _packedUint1;
    uint256 private _packedUint2;
    uint public lastRewardTimestamp;
    uint256 private constant UINT16_MASK = (1<<16)-1;
    uint256 private constant GCA_ZERO_MASK_ONE = ~((1<< 6*16) -1 | ((UINT16_MASK) << 5*16) | ((UINT16_MASK) << 10*16));
    uint256 private constant GCA_ZERO_MASK_TWO = ~((UINT16_MASK | ((UINT16_MASK) << 5*16)));

    uint256 private constant GCA_ONE_MASK_ONE = ~((((1<<5*16) -1) << 5) | (UINT16_MASK << 1) | ((UINT16_MASK) << 10));
    uint256 private constant GCA_ONE_MASK_TWO = ~((UINT16_MASK) << 1 | ((UINT16_MASK) << 5));

    uint256 private constant rewardsPerSecond = 1 ether;
    mapping(address => uint) public balance;//mock GLW

    uint256 private constant SHARE_PER_GCA = 50_000;

    constructor() {
        gcas[0] = address(0x1);
        gcas[1] = address(0x2);
        gcas[2] = address(0x3);
        gcas[3] = address(0x4);
        gcas[4] = address(0x5);
        testSetToEqual();
        lastRewardTimestamp = block.timestamp;
    }

    function claimForAll() public {
        uint totalRewardToGiveout = rewardsPerSecond * (block.timestamp - lastRewardTimestamp);
        uint256[5][5] memory matrix = getPayoutMatrix();
        uint _totalShares = totalShares();
        for(uint i; i<5;++i) {
            address _gca = gcas[i];
            if(_gca == address(0)) continue;
            uint shares = _findTotalSharesOfGCA(i, matrix);
            uint reward = totalRewardToGiveout * shares / _totalShares;
            balance[_gca] += reward;
        }

        lastRewardTimestamp = block.timestamp;

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
        uint sharesSupposedToHave = (numActiveGCAs() - 1) * SHARE_PER_GCA;
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
            _packedOne |= (SHARE_PER_GCA/5 << (sizeOfSlot*i));

        /*
            [2000,2000,2000,2000,2000]
            [2000,2000,2000,2000,2000]
            [2000,2000,2000,2000,2000]
        */
        }

        uint _packedTwo;
        for(uint i; i<totalSlotsInsideUint2;++i) {
            if(i == 4 || i ==9) continue;
            _packedTwo |= (SHARE_PER_GCA/4 << (sizeOfSlot*i));
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

    function getAllCurrentBalances() public view returns(uint[5] memory balances) {
        for(uint i; i<5;++i) {
            balances[i] = balance[gcas[i]];
        }
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