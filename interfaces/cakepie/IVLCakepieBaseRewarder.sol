// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "./IBaseRewardPool.sol";

interface IVLCakepieBaseRewarder is IBaseRewardPool {
    function queueCakepie(
        uint256 _amount,
        address _user,
        address _receiver
    ) external returns (bool);
}
