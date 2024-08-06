// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IAdapter {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function deposit(
        uint256 _amount0,
        uint256 _amount1,
        address _user,
        bytes calldata _data
    ) external returns (uint256 _share);

    function withdraw(
        uint256 _share,
        address _user,
        bytes calldata _data
    ) external returns (uint256 _amount0, uint256 _amount1);

    function initialize(
        address _wrapper,
        address _vault,
        address _token0,
        address _token1,
        address _lpToken,
        address _admin
    ) external;

    function wrapper() external returns (address);
}
