// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPancakeStaking } from "../../interfaces/cakepie/IPancakeStaking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title A contract for managing Merkl rewards for V3 pool
/// @notice You can use this contract for getting information about Merkl rewards for a specific user
contract ARBRewardDistributor is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable 
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct Reward {
        uint256 claimableAmount;
        uint256 claimedAmount;
    }

    mapping(bytes32 => Reward) public userReward;
    mapping(address => uint256[]) public userTokens;

    IERC20 public rewardToken;
    IPancakeStaking public pancakeStaking;

    /* ============ Events ============ */

    event MerklRewardUpdated();
    event RewardSent(address indexed account, uint256 amount);

    /* ============ Errors ============ */

    error TokenNotOwned();
    error LengthMismatch();
    error NotAllowZeroAddress();
    error OnlyAllowedOperator();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __ARBRewardDistributor_init(
        address _rewardToken,
        address _pancakeStaking
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        
        if (_pancakeStaking == address(0) || _rewardToken == address(0))
            revert NotAllowZeroAddress();

        rewardToken = IERC20(_rewardToken);
        pancakeStaking = IPancakeStaking(_pancakeStaking);
    }


    /* ============ Modifiers ============ */

     modifier onlyAllowedOperator() {
        if (!pancakeStaking.allowedOperator(msg.sender)) revert OnlyAllowedOperator();
        _;
    }

    /* ============ External Functions ============ */

    function updateRewards(
        address[] calldata _accounts,
        uint256[][] calldata _tokenIds,
        uint256[][] calldata _amounts
    ) external onlyAllowedOperator {
        uint256 accountsLength = _accounts.length;
        if (accountsLength != _tokenIds.length || accountsLength != _amounts.length)
            revert LengthMismatch();

        for (uint256 i; i < accountsLength; ++i) {
            uint256 tokenIdsLength = _tokenIds[i].length;
            if (tokenIdsLength != _amounts[i].length)
                revert LengthMismatch();

            address account = _accounts[i];
            for (uint256 j = 0; j < tokenIdsLength; ++j) {
                uint256 tokenId = _tokenIds[i][j];
                uint256 amount = _amounts[i][j];
                bytes32 userTokenKey = this.getKey(account, tokenId);
                Reward storage reward = userReward[userTokenKey];

                if (!_isTokenIdAdded(account, tokenId) && amount > 0) {
                    userTokens[account].push(tokenId);
                }
                reward.claimableAmount += amount;
            }
        }
        emit MerklRewardUpdated();
    }

    function claimRewardsUsers(
        address[] calldata _accounts,
        uint256[][] calldata _tokenIds
    ) external nonReentrant onlyAllowedOperator {
        uint256 accountsLength = _accounts.length;
        if (accountsLength != _tokenIds.length)
            revert LengthMismatch();

        for (uint256 i; i < accountsLength; ++i) {
            _claimRewards(_accounts[i], _tokenIds[i]);
        }
    }

    function claimRewards(
        uint256[] calldata _tokenIds
    ) external nonReentrant {
        _claimRewards(msg.sender, _tokenIds);
    }

    function getKey(
        address _account,
        uint256 _tokenId
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _tokenId));
    }

    function getUserRewards(
        address _account
    ) external view returns (uint256[] memory tokenIds, Reward[] memory rewards) {
       tokenIds = userTokens[_account];
       rewards = new Reward[](tokenIds.length);

       for (uint256 i = 0; i < tokenIds.length; i++) {
           uint256 tokenId = tokenIds[i];
           bytes32 userTokenKey = this.getKey(_account, tokenId);
           rewards[i] = userReward[userTokenKey];
       }
   }

    /* ============ Internal Functions ============ */

    function _claimRewards(
        address _account,
        uint256[] calldata _tokenIds
    ) internal {
        uint256 totalClaim;
        uint256 tokenIdsLength = _tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; ++i) {
            uint256 tokenId = _tokenIds[i];
            bytes32 userTokenKey = this.getKey(_account, tokenId);
            Reward storage reward = userReward[userTokenKey];

            uint256 currClaim = reward.claimableAmount - reward.claimedAmount;
            totalClaim += currClaim;
            reward.claimedAmount = reward.claimableAmount;
        }

        if (totalClaim > 0) {
            rewardToken.safeTransfer(_account, totalClaim);
            emit RewardSent(_account, totalClaim);
        }
    }

    function _isTokenIdAdded(
        address _account,
        uint256 _tokenId
    ) internal view returns (bool) {
        bytes32 userTokenKey = this.getKey(_account, _tokenId);
        Reward memory reward = userReward[userTokenKey];
        return (reward.claimableAmount > 0);
    }
}