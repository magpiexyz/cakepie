// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPancakeIFOHelper {
    function queueNewTokens(uint256 _amountReward, address _rewardToken) external returns (bool);

    function getDepositNOfferingToken()
        external
        view
        returns (address _depositToken, address _offeredToken);

    function isHarvestFromPancake() external view returns (bool);

    function pid() external view returns (uint8);

    function setMultiplier(uint256 _multiplier, uint256 _lpMultiplier) external;

    function setlpContributionLimit(uint256 _lpDepositLimit) external;

    function updateStatus() external;

    function pause() external;

    function unpause() external;

    error DepositExceed();
    error UserMaxCapReached();
    error IFOMaxCapReached();
}
