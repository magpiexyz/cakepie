// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IFarmBoosterReader {
    function whiteList(uint256) external view returns ( bool );
}
