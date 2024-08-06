// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IDelegator } from "../../interfaces/pancakeswap/IDelegator.sol";
import { IVeCake } from "../../interfaces/pancakeswap/IVeCake.sol";
import { PancakeStakingBaseUpg } from "../baseupgs/PancakeStakingBaseUpg.sol";
import { IMintableERC20 } from "../../interfaces/common/IMintableERC20.sol";

import { IRevenueSharingPool } from "../../interfaces/pancakeswap/IRevenueSharingPool.sol";
import { IGaugeVoting } from "../../interfaces/pancakeswap/IGaugeVoting.sol";
import { IMCakeConvertorBNBChain } from "../../interfaces/cakepie/IMCakeConvertorBNBChain.sol";

import "../../interfaces/pancakeswap/IIFOV8.sol";
import "../../interfaces/cakepie/IPancakeIFOHelper.sol";
import "../../interfaces/pancakeswap/IBunnyFactory.sol";
import "../../interfaces/pancakeswap/IPancakeProfile.sol";
import "../../interfaces/cakepie/ICakeRush.sol";
import "../../interfaces/pancakeswap/IPancakeVeSender.sol";

import { PancakeStakingLib } from "../../libraries/cakepie/PancakeStakingLib.sol";

/// @title PancakeStaking
/// @notice PancakeStaking is the main contract that holds veCake position on behalf on user to get boosted yield and vote.
///         PancakeStaking is the main contract interacting with pancakeswap side
/// @author Magpie Team

contract PancakeStakingBNBChain is PancakeStakingBaseUpg, IDelegator {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    IVeCake public veCake;
    IRevenueSharingPool public veRevenueShare;
    IGaugeVoting public gaugeVoting; // Pancakeswap gauge contract

    uint256 public lastHarvestTimeVe;
    address public mCakeConvertorBNBChain;

    //1st upgrade
    IRevenueSharingPool public veCakeShare;
    uint256 public lastHarvestTimeVeRevenueShare;

    address public cakepieIFOManager;

    address public cakeRush;
    uint256 public veCakeRewards;
    uint256 public veRevenueShareRewards;

    /* ============ Events ============ */
    event VeCakeRewarderSet(address indexed veCakeShare, address indexed veRevenueShare);
    event GaugeVotingSet(address indexed gaugeVoting);
    event CakepieIFOManagerSet(address indexed cakepieIFOManager);
    event CakeDelegate(address indexed _user, uint256 _amount);
    event InitVeCake(uint256 _amount, uint256 _unlockTime);
    event IncreaseVeCakeAmount(uint256 _amount);
    event DepositedIntoIFO(address indexed pancakeIFOHelper, uint8 pid, uint256 amount);
    event VestedIFORewardClaimed(
        address indexed pancakeIFOHelper,
        address _for,
        uint256 claimedAmount,
        address rewardToken
    );
    event IFORewardHarvested(
        address indexed pancakeIFOHelper,
        address _for,
        address rewardToken,
        uint256 harvestedAmount,
        address refundToken,
        uint256 refundAmount
    );
    event NFTMinted();
    event PancakeProfileCreated(uint256 _teamId, address _nftAddress, uint256 _tokenId);
    event CakeRushSet(address _cakeRush);
    event BroadcastedVeCakeToChain(uint32 indexed _destChainId);
        /* ============ Errors ============ */

    error OnlyVeCake();
    error AddressZero();
    error OnlyIFOManager();
    error TransferFailed();

    
    /* ============ Constructor ============ */

    receive() external payable {}

    constructor() {
        _disableInitializers();
    }

    function __PancakeStakingBNBChain_init(
        address _CAKE,
        address _veCake,
        address _veRevenueShare,
        address _mCake,
        address _masterCakepie
    ) public initializer {
        veCake = IVeCake(_veCake);
        veRevenueShare = IRevenueSharingPool(_veRevenueShare);
        __PancakeStakingBaseUpg_init(_CAKE, _mCake, _masterCakepie);
    }

    /* ============ Modifiers ============ */

    modifier _onlyVeCake() {
        if (msg.sender != address(veCake)) revert OnlyVeCake();
        _;
    }

    modifier _onlyIFOManager() {
        if (msg.sender != cakepieIFOManager) revert OnlyIFOManager();
        _;
    }

    modifier _onlyVoteManager() {
        if (msg.sender != address(voteManager)) revert OnlyVoteManager();
        _;
    }

    /* ============ VeCake Related Functions ============ */

    function increaseLock(uint256 _amount) external nonReentrant {
        IERC20(CAKE).safeTransferFrom(msg.sender, address(this), _amount);

        IERC20(CAKE).safeIncreaseAllowance(address(veCake), _amount);
        veCake.increaseLockAmount(_amount);

        emit IncreaseVeCakeAmount(_amount);
    }

    function harvestVeCakeReward(bool toAdmin) external _onlyAllowedOperator nonReentrant {
        _harvestVeCake(veCakeShare, lastHarvestTimeVe, true, toAdmin);
    }

    function harvestVeRevenueShare(bool toAdmin) external _onlyAllowedOperator nonReentrant {
        _harvestVeCake(veRevenueShare, lastHarvestTimeVeRevenueShare, false, toAdmin);
    }

    function _harvestVeCake(
        IRevenueSharingPool _shareRewarder,
        uint256 _lastHarvestTime,
        bool _isVeCake,
        bool _toAdmin
    ) internal {
        if (_lastHarvestTime + harvestTimeGap <= block.timestamp) {
            if (_isVeCake) lastHarvestTimeVe = block.timestamp;
            else lastHarvestTimeVeRevenueShare = block.timestamp;

            uint256 balBefore = IERC20(CAKE).balanceOf(address(this));

            IRevenueSharingPool(_shareRewarder).claim(address(this));

            uint256 harvestReward = IERC20(CAKE).balanceOf(address(this)) - balBefore;

            if (harvestReward > 0) {
                if (_toAdmin) {
                    IERC20(CAKE).safeTransfer(owner(), harvestReward);
                } else {
                    if(_isVeCake) veCakeRewards += harvestReward;
                    else veRevenueShareRewards += harvestReward;
                }
            }
        }
    }

    function sendVeRewards(bool _isVeCakeRewards, uint256 _minMCakeRec) external _onlyAllowedOperator nonReentrant {
        uint256 rewards = _isVeCakeRewards ? veCakeRewards : veRevenueShareRewards;
        address rewardAddress = _isVeCakeRewards ? address(veCakeShare) : address(veRevenueShare);

        if (rewards > 0) {
            IERC20(CAKE).safeIncreaseAllowance(address(rewardDistributor), rewards);
            rewardDistributor.sendVeReward(
                rewardAddress,
                address(CAKE),
                rewards,
                _isVeCakeRewards,
                _minMCakeRec
            );
            if (_isVeCakeRewards) {
                veCakeRewards = 0;
            } else {
                veRevenueShareRewards = 0;
            }
        }
    }

    /* ============ External Authorize Functions ============ */

    function depositIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        uint8 _pid,
        address _depositToken,
        address _for,
        uint256 _amount
    ) external nonReentrant _onlyIFOManager {
        PancakeStakingLib.depositIFO(_pancakeIFOHelper, _pancakeIFO, _pid, _depositToken, _for, _amount);
    }

    function harvestIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        uint8 _pid,
        address _depositToken,
        address _rewardToken
    ) external nonReentrant _onlyIFOManager {
        PancakeStakingLib.harvestIFO(_pancakeIFOHelper, _pancakeIFO, _pid, _depositToken, _rewardToken);
    }

    function releaseIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        bytes32 _vestingScheduleId,
        address _rewardToken
    ) external nonReentrant _onlyIFOManager {
        PancakeStakingLib.releaseIFO(_pancakeIFOHelper, _pancakeIFO, _vestingScheduleId, _rewardToken);
    }

    // call back when CAKE is delegated to Cakepie through veCAKE
    function delegate(
        address user,
        uint256 amount,
        uint256 lockEndTime
    ) external override nonReentrant _onlyVeCake {
        if (cakeRush != address(0) && !ICakeRush(cakeRush).paused()) {
            IMCakeConvertorBNBChain(mCakeConvertorBNBChain).mintFor(cakeRush, amount);
            ICakeRush(cakeRush).convertWithCakePool(user, amount);
        } else {
            IMCakeConvertorBNBChain(mCakeConvertorBNBChain).mintFor(user, amount);
        }
        emit CakeDelegate(user, amount);
    }

    /// @dev since this operation may cause heavy cost,
    ///      don't cast too many pools in once
    function castVote(
        address[] memory _pools,
        uint256[] memory _weights,
        uint256[] memory _chainIds
    ) external nonReentrant _onlyVoteManager {
        if (_pools.length != _weights.length || _pools.length != _chainIds.length)
            revert LengthMismatch();

        gaugeVoting.voteForGaugeWeightsBulk(_pools, _weights, _chainIds, false, false);
    }

    /* ============ Admin Functions ============ */

    function broadcastVeCake(
        address _pancakeVeSender,
        uint32 _dstChainId,
        uint128 _gasForDest
    ) external payable nonReentrant _onlyAllowedOperator {
        PancakeStakingLib.broadcastVeCake(_pancakeVeSender, _dstChainId, _gasForDest, owner());
    }

    function getEstimateGasFees(
        address _pancakeVeSender,
        uint32 _dstChainId,
        uint128 _gasForDest
    ) external view returns (IPancakeVeSender.MessagingFee memory messagingFee) {
        messagingFee  = IPancakeVeSender(_pancakeVeSender).getEstimateGasFees(_dstChainId, _gasForDest);
    }

    function initLockPosition(uint256 _unlockTime) external nonReentrant onlyOwner {
        uint256 allCake = IERC20(CAKE).balanceOf(address(this));

        IERC20(CAKE).safeIncreaseAllowance(address(veCake), allCake);
        veCake.createLock(allCake, _unlockTime);

        emit InitVeCake(allCake, _unlockTime);
    }

    function extendLock(uint256 _unlockTime) external nonReentrant _onlyAllowedOperator {
        veCake.increaseUnlockTime(_unlockTime);
    }

    function setMCakeConvertorBNBChain(address _mCakeConvertorBNBChain) external onlyOwner {
        if (_mCakeConvertorBNBChain == address(0)) revert AddressZero();
        mCakeConvertorBNBChain = _mCakeConvertorBNBChain;
    }

    function setVeCakeRewarder(address _veCakeShare, address _veRevenueShare) external onlyOwner {
        if (_veCakeShare == address(0) || _veRevenueShare == address(0)) revert AddressZero();
        veCakeShare = IRevenueSharingPool(_veCakeShare);
        veRevenueShare = IRevenueSharingPool(_veRevenueShare);
        emit VeCakeRewarderSet(_veCakeShare, _veRevenueShare);
    }

    function setGaugeVoting(address _gaugeVoting) external onlyOwner {
        if (_gaugeVoting == address(0)) revert AddressZero();
        gaugeVoting = IGaugeVoting(_gaugeVoting);
        emit GaugeVotingSet(_gaugeVoting);
    }

    function setCakepieIFOManager(address _cakepieIFOManager) external onlyOwner {
        if (_cakepieIFOManager == address(0)) revert AddressZero();
        cakepieIFOManager = _cakepieIFOManager;
        emit CakepieIFOManagerSet(_cakepieIFOManager);
    }

    function setCakeRush(address _cakeRush) external onlyOwner {
        if (_cakeRush == address(0)) revert AddressZero();
        cakeRush = _cakeRush;
        emit CakeRushSet(_cakeRush);
    }
}