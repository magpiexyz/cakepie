// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import { IPancakeStaking } from "../../interfaces/cakepie/IPancakeStaking.sol";
import { IVLCakepie } from "../../interfaces/cakepie/IVLCakepie.sol";
import { ICakepieBribeManager } from "../../interfaces/cakepie/ICakepieBribeManager.sol";
import { IGaugeVoting } from "../../interfaces/pancakeswap/IGaugeVoting.sol";
import { IVeCake } from "../../interfaces/pancakeswap/IVeCake.sol";

/// @title PancakeVoteManager contract, which include common functions for pancake voter on BSC and side chains
/// @notice Pancake Vote manager is designed with cross chain implication. veCake only lives on main chain, but vlCkp which controls
///         Cakepie's veCake voting power live on BSC and Arbitrum, vlCkp voting status has to be cast back to BSC from Arbitrum.
///
///         Bribe is designed as only lives on 1 chain, determined by which chain the corresponding liqudity is host on Pancake, for example, bribe for
///         GLP will be on Arbitrum while bribe for anrkETH, stETH will be on Ethereum.
///
///         The pool information PoolInfos stored HAS TO BE exact the same across all chains, except the bribe only lives on the chain
///         Where the underlying liquidity on pancake (ex: on arb for GLP, on eth for anrkETH) is host. The bribe address should be zero if for chains
///         That underlying liquidity is not on that chain. (ex: GLP will have pool on both Arbitrum and Ethereum, but arb pool will have bribe while eth pool bribe address should be zero)
///
/// @author Cakepie Team

contract PancakeVoteManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct Pool {
        bytes32 gaugeHash;
        address pool;
        uint256 gaugeType;
        uint256 chainId;
        bool isActive;
        uint256 totalVoteInVlCakepie;
    }

    struct UserVote {
        address pool;
        int256 weight;
    }

    /* ============ Constants for PCS integration ============ */

    /// @dev 7 * 86400 seconds - all future times are rounded by week
    uint256 constant WEEK = 604800;
    /// @dev Add 2 weeks time to calculate actual 2 weeks epoch
    uint256 constant TWOWEEK = WEEK * 2;

    /* ============ State Variables ============ */

    IGaugeVoting public voter; // Pendle voter interface
    IVeCake public veCake; //main contract interact with from pendle side

    IPancakeStaking public pancakeStaking; //TODO: currently only used for harvesting veCake from Pancake
    address public vlCakepie; // vlCakepie address
    address public bribeManager;
    bool public isMainChain;

    address[] public pools;
    mapping(address => Pool) public poolInfo;

    mapping(address => uint256) public userTotalVotedInVlCakepie; // unit = locked Cakepie
    mapping(address => mapping(address => uint256)) public userVotedForPoolInVlCakepie; // unit = locked Cakepie, key: [_user][_pool]

    uint256 public totalVlCakepieInVote;
    uint256 public lastCastTime;

    mapping(address => bool) public allowedOperator;

    uint256[50] private __gap;

    /* ============ Events ============ */

    event AddPool(address indexed _pool, bytes32 _gauge_hash);
    event DeactivatePool(address indexed _pool, bytes32 _gauge_hash);
    event VoteCasted(address indexed _caster, uint256 _timestamp);
    event Voted(
        uint256 indexed _targetTime,
        address indexed _user,
        address indexed _pool,
        int256 _weight
    );
    event UpdateOperatorStatus(address indexed _user, bool _status);

    /* ============ Errors ============ */

    error PoolNotActive();
    error NotEnoughVote();
    error InvalidPool();
    error ZeroAddressError();
    error OnlyBribeManager();
    error OnlyOperator();
    error OnlyMainChain();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __PancakeVoteManager_init(
        IVeCake _veCake,
        IGaugeVoting _voter,
        IPancakeStaking _pancakeStaking,
        address _vlCakepie,
        bool _isMainChain
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        veCake = _veCake;
        voter = _voter;
        pancakeStaking = _pancakeStaking;
        vlCakepie = _vlCakepie;
        isMainChain = _isMainChain;
    }

    /* ============ Modifiers ============ */

    modifier onlyMainChain() {
        if (!isMainChain) {
            revert OnlyMainChain();
        }
        _;
    }

    modifier onlyBribeManager() {
        if (msg.sender != bribeManager) revert OnlyBribeManager();
        _;
    }

    modifier onlyOperator() {
        if (!allowedOperator[msg.sender]) revert OnlyOperator();
        _;
    }

    /* ============ External Getters ============ */

    function getCurrentPeriodEndTime() public view returns (uint256 endTime) {
        uint256 nextTime = _getNextTime();
        if (block.timestamp >= nextTime - 122400) {
            endTime = nextTime + TWOWEEK - 122400; // if the current time has passed this period's end time, goto next period
        } else {
            endTime = nextTime - 122400; // before 1 day and 10 hours of PancakeSwapEndTime (UTC +8 22:00)
        }
    }

    // veCake getters

    function totalVotes() public view returns (uint256) {
        return veCake.balanceOf(address(pancakeStaking));
    }

    function veCakePerLockedCakepie() public view returns (uint256) {
        if (IVLCakepie(vlCakepie).totalLocked() == 0) return 0;
        return (totalVotes() * 1e18) / IVLCakepie(vlCakepie).totalLocked();
    }

    function getVoteForPool(address _pool) public view returns (uint256 poolVoted) {
        Pool memory _poolInfo = poolInfo[_pool];
        IGaugeVoting.VotedSlope memory votedSlope = voter.voteUserSlopes(
            address(pancakeStaking),
            _poolInfo.gaugeHash
        );
        poolVoted = (votedSlope.power * totalVotes()) / 10000;
    }

    function getVoteForPools(
        address[] calldata _pools
    ) public view returns (uint256[] memory votes) {
        uint256 length = _pools.length;
        votes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            votes[i] = getVoteForPool(_pools[i]);
        }
    }

    // vlCakepie getters

    function isPoolActive(address _pool) external view returns (bool) {
        return poolInfo[_pool].isActive;
    }

    function getPoolLength() external view returns (uint256) {
        return pools.length;
    }

    function getAllPools() public view returns (address[] memory) {
        return pools;
    }

    function getUserVotable(address _user) public view returns (uint256) {
        return IVLCakepie(vlCakepie).getUserTotalLocked(_user);
    }

    function getUserVoteForPoolsInVlCakepie(
        address[] calldata _pools,
        address _user
    ) public view returns (uint256[] memory votes) {
        uint256 length = _pools.length;
        votes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            votes[i] = userVotedForPoolInVlCakepie[_user][_pools[i]];
        }
    }

    function getVlCakepieVoteForPools(
        address[] calldata _pools
    ) public view returns (uint256[] memory vlCakepieVotes) {
        uint256 length = _pools.length;
        vlCakepieVotes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            Pool memory pool = poolInfo[_pools[i]];
            vlCakepieVotes[i] = pool.totalVoteInVlCakepie;
        }
    }

    /* ============ External Functions ============ */

    function vote(UserVote[] memory _votes) external nonReentrant whenNotPaused {
        _updateVoteAndCheck(msg.sender, _votes);
        if (userTotalVotedInVlCakepie[msg.sender] > getUserVotable(msg.sender))
            revert NotEnoughVote();
    }

    /// @notice cast all pending votes
    /// @notice we're casting weights to Pancake Finance
    function castVote(
        address[] memory _pools,
        uint256[] memory _weights,
        uint256[] memory _chainIds
    ) external nonReentrant onlyOperator onlyMainChain {
        lastCastTime = block.timestamp;
        pancakeStaking.castVote(_pools, _weights, _chainIds);
        emit VoteCasted(msg.sender, lastCastTime);
    }

    /* ============ Internal Functions ============ */

    /// @dev this function can get the same end time as Pancake's gauge controller
    function _getNextTime() internal view returns (uint256 nextTime) {
        nextTime = ((block.timestamp + TWOWEEK) / TWOWEEK) * TWOWEEK;
    }

    function _updateVoteAndCheck(address _user, UserVote[] memory _userVotes) internal {
        uint256 targetTime;
        // if the current time is greater than the end time, voting will continue into the next period
        if (block.timestamp >= getCurrentPeriodEndTime()) targetTime = _getNextTime() + TWOWEEK;
        else targetTime = _getNextTime();

        uint256 length = _userVotes.length;
        int256 totalUserVote;

        for (uint256 i; i < length; i++) {
            Pool storage pool = poolInfo[_userVotes[i].pool];

            int256 weight = _userVotes[i].weight;
            totalUserVote += weight;

            if (weight != 0) {
                if (weight > 0) {
                    if (!pool.isActive) revert PoolNotActive(); // do the check here let users can still unvote their votes
                    uint256 absVal = uint256(weight);
                    pool.totalVoteInVlCakepie += absVal;
                    userVotedForPoolInVlCakepie[_user][pool.pool] += absVal;
                } else {
                    uint256 absVal = uint256(-weight);
                    // check there is enough voting can be unvoted
                    if (absVal > userVotedForPoolInVlCakepie[_user][pool.pool])
                        revert NotEnoughVote();
                    pool.totalVoteInVlCakepie -= absVal;
                    userVotedForPoolInVlCakepie[_user][pool.pool] -= absVal;
                }
            }

            emit Voted(targetTime, _user, pool.pool, weight);
        }

        // update user's total vote and all vlCkp vote
        if (totalUserVote > 0) {
            userTotalVotedInVlCakepie[_user] += uint256(totalUserVote);
            totalVlCakepieInVote += uint256(totalUserVote);
        } else {
            userTotalVotedInVlCakepie[_user] -= uint256(-totalUserVote);
            totalVlCakepieInVote -= uint256(-totalUserVote);
        }
    }

    /* ============ Admin Functions ============ */

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setBribeManager(address _bribeManager) external onlyOwner {
        bribeManager = _bribeManager;
    }

    function setVlCakepie(address _vlCakpie) external onlyOwner {
        vlCakepie = _vlCakpie;
    }

    /// @dev since this function only can called
    function addPool(
        address _pool,
        uint256 _gaugeType,
        uint256 _chainId
    ) external onlyBribeManager {
        if (_pool == address(0)) revert ZeroAddressError();
        if (poolInfo[_pool].pool != address(0)) revert InvalidPool();

        Pool memory pool = poolInfo[_pool] = Pool({
            gaugeHash: keccak256(abi.encodePacked(_pool, _chainId)),
            pool: _pool,
            gaugeType: _gaugeType,
            chainId: _chainId,
            isActive: true,
            totalVoteInVlCakepie: 0
        });
        poolInfo[_pool] = pool;
        pools.push(_pool);

        emit AddPool(_pool, pool.gaugeHash);
    }

    function deactivatePool(address _pool) external onlyBribeManager {
        if (!poolInfo[_pool].isActive) revert InvalidPool();
        poolInfo[_pool].isActive = false;

        emit DeactivatePool(_pool, poolInfo[_pool].gaugeHash);
    }

    function updatePool(
        address _pool,
        uint256 _chainId,
        uint256 _gaugeType,
        bool _active
    ) external onlyBribeManager {
        Pool storage pool = poolInfo[_pool];
        if (pool.pool == address(0)) revert InvalidPool();

        pool.gaugeHash = keccak256(abi.encodePacked(_pool, _chainId));
        pool.pool = _pool;
        pool.gaugeType = _gaugeType;
        pool.chainId = _chainId;
        pool.isActive = _active;
    }

    function updateAllowedOperator(address _user, bool _allowed) external onlyOwner {
        allowedOperator[_user] = _allowed;

        emit UpdateOperatorStatus(_user, _allowed);
    }
}
