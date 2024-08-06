// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ICakeRush {
    struct UserInfo {
        uint256 converted; 
        uint256 factor;
        uint256 weightedConverted; 
        uint256 weightedFactor; 
    }

    function userInfos(address _user) external view returns(UserInfo memory); 
    function claimedMCake(address _user) external view returns(uint256);
}

interface IVlmgp
{
    function totalLocked() external view returns (uint256);
    function getUserTotalLocked(address _user) external view returns (uint256);
}

interface IBurnEventManager
{
    function eventInfos(uint256 _eventId) external view returns( uint256, string memory, uint256, uint256, bool); 
    function userMgpBurnAmountForEvent(address _user, uint256 evntId) external view returns(uint256);
}

interface ImCakeSV
{
    function totalLocked() external view returns (uint256);
    function getUserTotalLocked(address _user) external view returns (uint256 _lockAmount); 
    function balanceOf(address _user) external view returns (uint256);
}



