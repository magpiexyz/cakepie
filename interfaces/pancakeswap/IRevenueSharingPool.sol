// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IRevenueSharingPool {
    function balanceOfAt(address _user, uint256 _timestamp) external view returns (uint256);

    function checkpointToken() external;

    function checkpointTotalSupply() external;

    function claim(address _user) external returns (uint256);

    function claimMany(address[] calldata _users) external returns (bool);

    function feed(uint256 _amount) external returns (bool);

    function kill() external;

    function setCanCheckpointToken(bool _newCanCheckpointToken) external;

    function _timestampToFloorWeek(uint256 _timestamp) external pure returns (uint256);

    function injectReward(uint256 _timestamp, uint256 _amount) external;

    function setWhitelistedCheckpointCallers(address[] calldata _callers, bool _ok) external;

    function userEpochOf(address _user) external view returns (uint256);
}
