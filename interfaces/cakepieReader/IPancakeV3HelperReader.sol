// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPancakeV3HelperReader {
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function nonfungiblePositionManager() external returns (address);
}
