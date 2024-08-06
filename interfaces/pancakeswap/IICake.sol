// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IICake {
    function getUserCreditWithIfoAddr(address _user, address _ifo) external view returns (uint256);
}
