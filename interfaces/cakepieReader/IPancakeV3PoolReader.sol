// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPancakeV3PoolReader {
    function slot0() external view returns ( uint160, int24,uint16,uint16,uint16,uint32, bool );
    function liquidity() external view returns ( uint128 );
    function fee() external view returns ( uint24 );
    function lmPool() external view returns ( address );
}
