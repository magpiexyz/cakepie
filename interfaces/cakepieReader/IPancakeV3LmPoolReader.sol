// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPancakeV3LmPoolReader {
    function lmLiquidity() external view returns ( uint128 );
}
