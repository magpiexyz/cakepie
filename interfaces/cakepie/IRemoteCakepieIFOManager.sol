// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IRemoteCakepieIFOManager {
    function getPancakeIFOHelpers() external view returns (address[] memory);

    function harvestIFOFromPancake(address _pancakeIFO) external;

    function releaseIFOFromPancake(address _pancakeIFO, uint8 _pid) external;

    function setMultipliersForIFOHelper(
        address _remotePancakeIFOHelper,
        uint256[] calldata _multipliers
    ) external;

    function transferDepositToIFO(
        address pancakeIFO,
        uint8 pid,
        address depsoitToken,
        address account,
        uint256 amount
    ) external;
}
