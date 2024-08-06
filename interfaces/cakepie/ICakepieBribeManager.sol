// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface ICakepieBribeManager {
    struct Pool {
        address _market;
        bool _active;
        uint256 _chainId;
    }

    function pools(uint256) external view returns (Pool memory);

    function poolToPid(address _pool) external view returns (uint256);

    function exactCurrentVotingEpoch() external view returns (uint256);

    function getCurrentEpochEndTime(uint256 _epoch) external view returns (uint256 endTime);

    function addBribeERC20(uint256 _batch, uint256 _pid, address _token, uint256 _amount) external;

    function addBribeNative(uint256 _batch, uint256 _pid) external payable;
}
