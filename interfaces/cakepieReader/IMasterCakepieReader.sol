// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IMasterCakepieReader {
    function poolLength() external view returns (uint256);

    function cakepieOFT() external view returns (address);

    function registeredToken(uint256) external view returns (address);

    struct CakepiePoolInfo {
        address stakingToken; // Address of staking token contract to be staked.
        address receiptToken; // Address of receipt token contract represent a staking position
        uint256 allocPoint; // How many allocation points assigned to this pool. Penpies to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that Penpies distribution occurs.
        uint256 accPenpiePerShare; // Accumulated Penpies per share, times 1e12. See below.
        uint256 totalStaked;
        address rewarder;
        bool isActive;
    }

    function tokenToPoolInfo(address) external view returns (CakepiePoolInfo memory);

    function getPoolInfo(address) external view returns (uint256, uint256, uint256, uint256);

    function allPendingTokens(
        address _stakingToken,
        address _user
    )
        external
        view
        returns (
            uint256 pendingPenpie,
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        );

    function stakingInfo(
        address _stakingToken,
        address _user
    ) external view returns (uint256 stakedAmount, uint256 availableAmount);

    function allPendingLegacyTokens(
        address _stakingToken,
        address _user
    )
        external
        view
        returns (
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        );
    
}
