// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "../pancakeswap/IMasterChefV3.sol";

interface IPancakeStaking {
    function increaseLock(uint256 amount) external;

    function veCake() external returns (address);

    function pools(
        address _poolAddress
    )
        external
        view
        returns (
            address poolAddress,
            address depositToken,
            address rewarder,
            address receiptToken,
            uint256 lastHarvestTime,
            uint256 poolType,
            uint256 v3Liquidity,
            bool isAmount0,
            bool isNative,
            bool isActive
        );

    function depositV3For(address _for, address _v3Pool, uint256 _tokenId) external;

    function withdrawV3For(address _for, address _v3Pool, uint256 _tokenId) external;

    function increaseLiquidityV3For(
        address _for,
        address _v3Pool,
        IMasterChefV3.IncreaseLiquidityParams calldata params
    ) external;

    function decreaseLiquidityV3For(
        address _for,
        address _v3Pool,
        IMasterChefV3.DecreaseLiquidityParams calldata params
    ) external;

    function harvestV3(address _for, uint256[] memory tokenIds) external;

    function harvestV3PoolFees(address _for, uint256[] memory tokenIds) external payable;

    function depositV2LPFor(address _for, address _poolAddress, uint256 _amount) external;

    function withdrawV2LPFor(address _for, address _poolAddress, uint256 _amount) external;

    function harvestV2LP(address[] memory poolAddress) external;

    function depositAMLFor(address _for, address _poolAddress, uint256 _amount0, uint256 _amount1) external;

    function withdrawAMLFor(address _for, address _poolAddress, uint256 _amount) external;

    function harvestAMLV3(address[] memory poolAddress) external;

    function castVote(
        address[] memory _pools,
        uint256[] memory _weights,
        uint256[] memory _chainIds
    ) external;

    function harvestAML(address[] memory poolAddress) external;

    function genericHarvest(address poolAddress) external;

    function poolLength() external returns (uint256);

    function depositIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        uint8 _pid,
        address _depsoitToken,
        address _for,
        uint256 _amount
    ) external;

    function harvestIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        uint8 _pid,
        address _depositToken,
        address _rewardToken
    ) external;

    function releaseIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        bytes32 _vestingScheduleId,
        address _rewardToken
    ) external;

    function allowedOperator(address _account) external returns (bool);
}
