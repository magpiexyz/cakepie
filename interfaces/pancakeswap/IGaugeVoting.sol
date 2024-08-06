// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IGaugeVoting {
    struct VotedSlope {
        uint256 slope;
        uint256 power;
        uint256 end;
    }

    function voteUserSlopes(
        address _stakingAddress,
        bytes32 _gaugeHash
    ) external view returns (VotedSlope memory);

    function voteUserPower(address) external view returns (uint256);

    function voteForGaugeWeightsBulk(
        address[] memory _gauge_addrs,
        uint256[] memory _user_weights,
        uint256[] memory _chainIds,
        bool _skipNative,
        bool _skipProxy
    ) external;
}
