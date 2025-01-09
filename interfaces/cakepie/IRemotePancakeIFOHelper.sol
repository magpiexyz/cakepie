// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRemotePancakeIFOHelper {
    function queueNewTokens(uint256 _amountReward, address _rewardToken) external returns (bool);

    function getDepositNOfferingToken()
        external
        view
        returns (address _depositToken, address _offeredToken);

    function isHarvestFromPancake() external view returns (bool);

    function pid() external view returns (uint8);

    function setMultipliers(
        uint256[] calldata _multipliers
    ) external;

    function updateStatus() external;

    function pause() external;

    function unpause() external;

    function setUserAmounts(address[] calldata users, uint8 tokenId, uint256[] calldata amounts) external;
}
