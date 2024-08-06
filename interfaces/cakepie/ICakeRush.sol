// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface ICakeRush {
    function convertWithCakePool(address _for, uint256 _amount) external;
    function paused() external view returns (bool);
}
