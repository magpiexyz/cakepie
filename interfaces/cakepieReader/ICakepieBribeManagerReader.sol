// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;


interface ICakepieBribeManagerReader {
    function voteManager() external view returns(address);
    struct IBribe {
        address _token;
        uint256 _amount;
    } 
    function getBribesInAllPools(uint256 _epoch) external view returns (IBribe[][] memory);
    function getBribesInAllPoolsForVePendle(uint256 _epoch) external view returns (IBribe[][] memory);
    function getCurrentPeriodEndTime() external view returns(uint256 endTime);
    function getApprovedTokens() external view returns(address[] memory);
    function getPoolLength() external view returns(uint256);
}