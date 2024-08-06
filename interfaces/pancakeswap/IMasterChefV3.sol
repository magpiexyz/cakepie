// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.19;

import { INonfungiblePositionManagerStruct } from "./INonfungiblePositionManagerStruct.sol";

interface IMasterChefV3 is INonfungiblePositionManagerStruct {
    
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    struct UserPositionInfo {
        uint128 liquidity;
        uint128 boostLiquidity;
        int24 tickLower;
        int24 tickUpper;
        uint256 rewardGrowthInside;
        uint256 reward;
        address user;
        uint256 pid;
        uint256 boostMultiplier;
    }

    function userPositionInfos(
        uint256 tokenId
    )
        external
        view
        returns (
            uint128 liquidity,
            uint128 boostLiquidity,
            int24 tickLower,
            int24 tickUpper,
            uint256 rewardGrowthInside,
            uint256 reward,
            address user,
            uint256 pid,
            uint256 boostMultiplier
        );

    function updateLiquidity(uint256 _tokenId) external;

    function updatePools(uint256[] memory _pids) external;

    /// @notice Withdraw LP tokens from pool.
    /// @param _tokenId Token Id of NFT to deposit.
    /// @param _to Address to which NFT token to withdraw.
    /// @return reward Cake reward.
    function withdraw(uint256 _tokenId, address _to) external returns (uint256 reward);

    function balanceOf(address account) external view returns (uint256);

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to acheive resulting liquidity
    /// @return amount1 The amount of token1 to acheive resulting liquidity
    function increaseLiquidity(
        IncreaseLiquidityParams memory params
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(
        DecreaseLiquidityParams memory params
    ) external returns (uint256 amount0, uint256 amount1);

    function pendingCake(uint256 _tokenId) external view returns (uint256 reward);

    /// @notice harvest cake from pool.
    /// @param _tokenId Token Id of NFT.
    /// @param _to Address to.
    /// @return reward Cake reward.
    function harvest(uint256 _tokenId, address _to) external returns (uint256 reward);

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function unwrapWETH9(uint256 amountMinimum, address recipient) external;

    function sweepToken(address token, uint256 amountMinimum, address recipient) external;

    function collect(
        CollectParams memory params
    ) external returns (uint256 amount0, uint256 amount1);

    function poolInfo(
        uint256 poolId
    )
        external
        view
        returns (
            uint256 allocPoint,
            address v3Pool,
            address token0,
            address token1,
            uint24 fee,
            uint256 totalLiquidity,
            uint256 totalBoostLiquidity
        );
    function v3PoolAddressPid(address pool)  external view returns (uint256 pid);
    function WETH()  external view returns (address weth);
    function totalAllocPoint() external view returns (uint256 value);
    function latestPeriodCakePerSecond() external view returns (uint256 value);
    function poolLength() external view returns (uint256);
    function FARM_BOOSTER() external view returns (address);
}
