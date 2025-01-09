// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IICake {
    struct DelegatorConfig {
        address VECakeUser;
        address delegator;
    }

    function getUserCreditWithIfoAddr(address _user, address _ifo) external view returns (uint256);

    function approveToVECakeUser(address _VECakeUser) external;

    function setDelegators(DelegatorConfig[] calldata _delegatorConfigs) external;
}
