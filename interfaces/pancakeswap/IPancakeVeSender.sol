// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IPancakeVeSender {
    
    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    function sendSyncMsg(
        uint32 _dstChainId,
        address _user,
        bool _syncVeCake,
        bool _syncProfile,
        uint128 _gasForDest
    ) external payable;

    function getEstimateGasFees(
        uint32 _dstChainId,
        uint128 _gasForDest
    ) external view returns (MessagingFee memory fee);
}
