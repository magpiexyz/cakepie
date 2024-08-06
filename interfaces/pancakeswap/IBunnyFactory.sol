// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBunnyFactory {
    function mintNFT(uint8 _bunnyId) external;

    function tokenPrice() external view returns (uint256);
}

interface IPancakeBunnies {
    function approve(address to, uint256 tokenId) external;

    function balanceOf(address _user) external view returns (uint256);

    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256 tokenId);

    function mint(
        address _to,
        string calldata _tokenURI,
        uint8 _bunnyId
    ) external returns (uint256);
}
