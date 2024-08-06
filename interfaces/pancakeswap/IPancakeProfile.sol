// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPancakeProfile {
    function createProfile(uint256 _teamId, address _nftAddress, uint256 _tokenId) external;

    function getUserProfile(
        address _userAddress
    )
        external
        view
        returns (
            uint256 userId,
            uint256 numberPoints,
            uint256 teamId,
            address nftAddress,
            uint256 tokenId,
            bool isActive
        );

    function getUserStatus(address _userAddress) external view returns (bool);

    function numberCakeToRegister() external view returns (uint256);
}
