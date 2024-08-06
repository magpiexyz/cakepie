// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISmartCakeConvertor {
    function smartConvert(uint256 _amountIn, uint256 _mode) external returns (uint256);

    function cake() external view returns (address);

    function mCake() external view returns (address);

    function estimateTotalConversion(
        uint256 _amountIn,
        uint256 _convertRatio
    ) external view returns (uint256);

    function convert(
        uint256 _amountIn,
        uint256 _convertRatio,
        uint256 _minRec,
        uint256 _mode
    ) external returns (uint256 obtainedMCakeAmount);
}
