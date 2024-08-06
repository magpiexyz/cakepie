// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IPancakeVoteManager {
    struct UserVote {
        address pool;
        int256 weight;
    }

    function totalVotes() external view returns (uint256);

    function veCakePerLockedCakepie() external view returns (uint256);

    function getVoteForPool(address pool) external view returns (uint256 poolVoted);

    function getVoteForPools(
        address[] calldata pools
    ) external view returns (uint256[] memory votes);

    function getUserVoteForMarketsInVlCakepie(
        address[] calldata _pools,
        address _user
    ) external view returns (uint256[] memory votes);

    function getUserVotable(address _user) external view returns (uint256);

    function getUserVoteForPoolsInVlCakepie(
        address[] calldata _pools,
        address _user
    ) external view returns (uint256[] memory votes);

    function userTotalVotedInVlCakepie(address _user) external view returns (uint256);

    function getVlCakepieVoteForPools(
        address[] calldata _pools
    ) external view returns (uint256[] memory vlCakepieVotes);

    function vote(UserVote[] memory _votes) external;

    function castVote(
        address[] memory _pools,
        uint256[] memory _weights,
        uint256[] memory _chainIds
    ) external;

    /* ============ Admin Functions ============ */

    function pause() external;

    function unpause() external;

    function setBribeManager(address _bribeManager) external;

    function addPool(address _pool, uint256 _gaugeType, uint256 _chainId) external;

    function deactivatePool(address _pool) external;

    function updatePool(address _pool, uint256 _chainId, uint256 _gaugeType, bool _active) external;

    function updateAllowedOperator(address _user, bool _allowed) external;
}
