// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICakeMCakeRewardPool {
    function stakingDecimals() external view returns (uint256);

    function totalStaked() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function rewardPerToken(address token) external view returns (uint256);

    function rewardTokenInfos()
        external
        view
        returns (address[] memory bonusTokenAddresses, string[] memory bonusTokenSymbols);

    function earned(address account, address token) external view returns (uint256);

    function allEarned(
        address account
    ) external view returns (uint256[] memory pendingBonusRewards);

    function queueNewRewards(uint256 _rewards, address token) external returns (bool);

    function getReward(address _account, address _receiver, uint256 _minRecMCake) external returns (bool);

    function getRewards(
        address _account,
        address _receiver,
        address[] memory _rewardTokens,
        uint256 _minRecMCake
    ) external;

    function updateFor(address account) external;

    function updateRewardQueuer(address _rewardManager, bool _allowed) external;

    function config(address _cakeToken, address _mCakeToken, address _smartCakeConvertor, address _mCakeConvertor ) external;
}
