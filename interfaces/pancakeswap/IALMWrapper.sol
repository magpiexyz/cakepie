// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IALMWrapper {
    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to deposit (in stakeToken)
     */
    function deposit(uint256 _amount, bool _noHarvest) external;

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _amount) external;

    /*
     * @notice Mint then deposit staked tokens and collect reward tokens (if any)
     * @param _amount0: token0 amount to deposit (in token0)
     * @param _amount1: token0 amount to deposit (in token1)
     * @param _data: payload data from FE side
     */
    function mintThenDeposit(uint256 _amount0, uint _amount1, bool _noHarvest, bytes calldata _data) external;

    /*
     * @notice Withdraw then burn staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     * @param _data: payload data from FE side
     */
    function withdrawThenBurn(uint256 _amount, bool _noHarvest, bytes calldata _data) external;

    function pendingReward(address _user) external view returns (uint256);

    // TODO will have to update userInfo struct when new AMLWrapper deployed
    function userInfo(
        address userAddress
    ) external view returns (
        uint256 amount, // How many staked tokens the user has provided
        uint256 rewardDebt
        // uint256 boostMultiplier, // currently active multiplier
        // uint256 boostedAmount, // combined boosted amount
        // uint256 unsettledRewards // rewards haven't been transferred to users but already accounted in rewardDebt        
    );

    function adapterAddr() external view returns (address);
}
