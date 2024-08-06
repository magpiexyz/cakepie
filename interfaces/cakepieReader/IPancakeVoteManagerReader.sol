// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPancakeVoteManagerReader {
    function getPoolLength() external view returns (uint256);

    function getAllPools() external view returns (address[] memory);

    function lastCastTime() external view returns (uint256);

    function totalVlCakepieInVote() external view returns (uint256);

    function poolInfo(
        address
    ) external view returns (bytes32, address, uint256, uint256, bool, uint256);

    function userVotedForPoolInVlCakepie(address, address) external view returns (uint256);

    function totalVotes() external view returns (uint256);

    function veCake() external view returns (address);

    function pools(uint256) external view returns (address);

    function getCurrentPeriodEndTime() external view returns (uint256 endTime);

    function userTotalVotedInVlCakepie(address _user) external view returns (uint256);

    function getUserVotable(address _user) external view returns (uint256);

    function getUserVoteForPoolsInVlCakepie(
        address[] calldata lps,
        address _user
    ) external view returns (uint256[] memory votes);
}
