// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IPancakeV3Helper {
    function tokenToPool(uint256 _tokenId) external view returns (address);

    function harvestRewardAndFeeFor(address _for, uint256[] memory _tokenId) external;
}
