// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPancakeStakingReader {
    struct PancakeStakingPoolInfo {
        address poolAddress; // For V2, V3, it's Lp address, for AML it's wrapper addresss
        address depositToken; // For V2, it's Lp address, For V3 it's single side token
        address rewarder; // only for V2 and AML,
        address receiptToken; // only for V2 and AML,
        uint256 lastHarvestTime; // only for V2 and AML,
        uint256 poolType; // specifying V2, V3 or AML pool
        uint256 v3Liquidity; // tracker for totla v3 liquidity
        bool isAmount0; // only applicable for AML pool
        bool isNative;
        bool isActive;
    }

    function veCake() external view returns (address);

    function pools(address) external view returns (PancakeStakingPoolInfo memory);

    function CAKE() external view returns (address);

    function mCakeOFT() external view returns (address);

    function voteManager() external view returns (address);

    function masterCakepie() external view returns (address);

    function rewardDistributor() external view returns (address);

    function pancakeV3Helper() external view returns (address);

    function pancakeV2LPHelper() external view returns (address);

    function pancakeAMLHelper() external view returns (address);

    function poolLength() external view returns (uint256);

    function poolList(uint256 _pid) external view returns (address);
}
