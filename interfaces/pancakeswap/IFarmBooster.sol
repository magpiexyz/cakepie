// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFarmBooster {
    struct DelegatorConfig {
        address VECakeUser;
        address delegator;
    }

    function updateBoostMultiplier(address user) external returns (uint256 _multiplier);

    function approveToVECakeUser(address veCakeUser) external;

    function setDelegators(DelegatorConfig[] calldata _delegatorConfigs) external;
}