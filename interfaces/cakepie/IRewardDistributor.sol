// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRewardDistributor {

    error minReceivedNotMet();

    struct Fees {
        uint256 value; // allocation denominated by DENOMINATOR
        address to;
        bool isAddress;
        bool isActive;
    }

    function pancakeFeeInfos(uint256 index) external view returns (Fees memory);

    function sendRewards(
        address poolAddress,
        address rewardToken,
        address _to,
        uint256 amount,
        bool isRewarder
    ) external;

    function sendVeReward(
        address _rewardSource,
        address _rewardToken,
        uint256 _amount,
        bool _isVeCake,
        uint256 _minRec
    ) external;

    function CKPRatio() external view returns (uint256);
}
