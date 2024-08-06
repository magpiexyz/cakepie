// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../interfaces/cakepie/ILocker.sol";
import "../../interfaces/cakepie/IConvertor.sol";
import "../../interfaces/cakepie/IMasterCakepie.sol";
import "../../interfaces/pancakeswap/ISmartCakeConvertor.sol";

/// @title CakeRushV2
/// @notice Contract for calculating incentive deposits and rewards points with the Cake token
contract CakeRushV2 is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct UserInfo {
        uint256 converted;
        uint256 rewardClaimed;
        uint256 convertedTimes;
        bool isBlacklisted;
    }

    IERC20 public Cake; // Cake token
    address public mCake; // mCake Token
    ILocker public mCakeSV;
    IERC20 public CKP; // CKP token
    address public smartConvert;
    address public mCakeConvertor;
    address public pancakeStaking;
    address public masterCakepie;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public tierLength;
    uint256 public totalAccumulated;

    uint256[] public rewardMultiplier;
    uint256[] public rewardTier;

    mapping(address => UserInfo) public userInfos; // Total conversion amount per user

    uint256 public convertedTimesThreshold;

    uint256 public smartConvertProportion;
    uint256 public lockMCakeProportion;

    ILocker public vlCKP;

    /* ============ Events ============ */

    event CKPRewarded(address indexed _beneficiary, uint256 _CKPAmount);
    event CakeConverted(
        address indexed _account,
        uint256 _CakeAmount,
        uint256 _mCakeAmount,
        uint256 _smartConvertProportion,
        uint256 _directConvertProportion
    );
    event mCakeLocked(address indexed _account, uint256 _amount);
    event PancakeStakingSet(address indexed _cakeStaking);
    event smartConvertProportionSet(uint256 _smartConvertProportion);
    event lockMCakeProportionSet(uint256 _lockMCakeProportion);
    event convertedTimesThresholdSet(uint256 _threshold);
    event userBlacklistUpdate(address indexed _user, bool _isBlacklisted);
    event mCakeConvertorSet(address indexed _mCake, address indexed _mCakeConvertor);
    event DelegationConvert(
        address indexed _user,
        uint256 _amount,
        uint256 _reward,
        uint256 timestamp
    );
    event smartConvertorSet(address _smartConvertor);

    /* ============ Errors ============ */

    error InvalidAmount();
    error LengthMismatch();
    error IsNotSmartContractAddress();
    error InvalidConvertor();
    error RewardTierNotSet();
    error OnlyPancakeStaking();

    /* ============ Constructor ============ */
    constructor() {
        _disableInitializers();
    }

    /* ============ Modifier ============ */

    modifier _onlyPancakeStaking() {
        if (pancakeStaking == address(0) || msg.sender != pancakeStaking)
            revert OnlyPancakeStaking();
        _;
    }

    /* ============ Initialization ============ */

    function _CakeRushV2_init(
        address _Cake,
        address _smartConvert,
        address _CKP,
        address _mCakeSV,
        address _pancakeStaking,
        address _vlCKP,
        address _masterCakepie
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        Cake = IERC20(_Cake);
        CKP = IERC20(_CKP);
        mCakeSV = ILocker(_mCakeSV);
        smartConvert = _smartConvert;
        pancakeStaking = _pancakeStaking;
        vlCKP = ILocker(_vlCKP);
        masterCakepie = _masterCakepie;
    }

    /* ============ External Read Functions ============ */

    function quoteConvert(
        uint256 _amountToConvert,
        address _account
    ) external view returns (uint256 rewardToSend) {
        if (rewardTier.length == 0) revert RewardTierNotSet();
        UserInfo memory userInfo = userInfos[_account];
        uint256 ckpReward = 0;

        uint256 accumulatedRewards = _amountToConvert + userInfo.converted;
        uint256 i = 1;

        while (i < rewardTier.length && accumulatedRewards > rewardTier[i]) {
            ckpReward += (rewardTier[i] - rewardTier[i - 1]) * rewardMultiplier[i - 1];
            ++i;
        }
        ckpReward += (accumulatedRewards - rewardTier[i - 1]) * rewardMultiplier[i - 1];
        ckpReward = (ckpReward / DENOMINATOR) - userInfo.rewardClaimed;

        uint256 ckpleft = CKP.balanceOf(address(this));

        uint256 finalReward = ckpReward > ckpleft ? ckpleft : ckpReward;
        return finalReward;
    }

    function getUserTier(address _account) public view returns (uint256) {
        if (rewardTier.length == 0) revert RewardTierNotSet();
        uint256 userconverted = userInfos[_account].converted;
        for (uint256 i = tierLength - 1; i >= 1; --i) {
            if (userconverted >= rewardTier[i]) {
                return i;
            }
        }
        return 0;
    }

    function amountToNextTier(address _account) external view returns (uint256) {
        uint256 userTier = this.getUserTier(_account);
        if (userTier == tierLength - 1) return 0;

        return rewardTier[userTier + 1] - userInfos[_account].converted;
    }

    function validConvertor(address _user) external view returns (bool) {
        UserInfo storage userInfo = userInfos[_user];

        if (userInfo.isBlacklisted || userInfo.convertedTimes >= convertedTimesThreshold)
            return false;

        return true;
    }

    /* ============ External Write Functions ============ */

    function convert(address _for, uint256 _amount) external whenNotPaused nonReentrant {
        if (!this.validConvertor(_for)) revert InvalidConvertor();
        if (_amount == 0) revert InvalidAmount();

        uint256 rewardToSend = this.quoteConvert(_amount, _for);

        _convert(_for, _amount);
        _lockAndReward(_for, _amount, rewardToSend);

        emit CKPRewarded(_for, rewardToSend);
    }

    function convertWithCakePool(address _for, uint256 _amount) external _onlyPancakeStaking {
        if (!this.validConvertor(_for)) revert InvalidConvertor();
        if (_amount == 0) revert InvalidAmount();

        uint256 rewardToSend = this.quoteConvert(_amount, _for);

        _lockAndReward(_for, _amount, rewardToSend);

        emit DelegationConvert(_for, _amount, rewardToSend, block.timestamp);
    }

    /* ============ Internal Functions ============ */

    function _convert(address _account, uint256 _amount) internal {
        Cake.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 smartAmount = (_amount * smartConvertProportion) / DENOMINATOR;
        uint256 directAmount = _amount - smartAmount;

        if (directAmount > 0) {
            Cake.safeApprove(mCakeConvertor, directAmount);
            IConvertor(mCakeConvertor).convert(address(this), directAmount, 0);
        }

        if (smartAmount > 0) {
            Cake.safeApprove(smartConvert, smartAmount);
            ISmartCakeConvertor(smartConvert).smartConvert(smartAmount, 0);
        }

        emit CakeConverted(
            _account,
            _amount,
            IERC20(mCake).balanceOf(address(this)),
            smartConvertProportion,
            DENOMINATOR - smartConvertProportion
        );
    }

    function _lockAndReward(address _for, uint256 _amount, uint256 _rewardToSend) internal {
        uint256 mCakeToStake = _mCakeStakeAndLock(_for, IERC20(mCake).balanceOf(address(this)));

        if (mCakeToStake > 0) {
            IERC20(mCake).safeApprove(masterCakepie, mCakeToStake);
            IMasterCakepie(masterCakepie).depositFor(mCake, _for, mCakeToStake);
        }

        UserInfo storage userInfo = userInfos[_for];
        userInfo.converted += _amount;
        userInfo.rewardClaimed += _rewardToSend;
        totalAccumulated += _amount;
        userInfo.convertedTimes += 1;

        // Lock the rewarded vlCKP
        CKP.safeApprove(address(vlCKP), _rewardToSend);
        vlCKP.lockFor(_rewardToSend, _for);
    }

    function _lock(address _account, uint256 _amount) internal {
        IERC20(mCake).safeApprove(address(mCakeSV), _amount);
        mCakeSV.lockFor(_amount, _account);

        emit mCakeLocked(_account, _amount);
    }

    /* ============ Private Functions ============ */

    function _mCakeStakeAndLock(address _for, uint256 mcake) private returns (uint256) {
        uint256 mCakeToLock = (mcake * lockMCakeProportion) / DENOMINATOR;
        uint256 mCakeToStake = mcake - mCakeToLock;

        if (mCakeToLock > 0) {
            _lock(_for, mCakeToLock);
        }

        return mCakeToStake;
    }

    /* ============ Admin Functions ============ */

    function setConvertedTimesThreshold(uint256 _threshold) external onlyOwner {
        convertedTimesThreshold = _threshold;
        emit convertedTimesThresholdSet(_threshold);
    }

    function updateUserBlacklist(address _user, bool _isBlacklisted) external onlyOwner {
        UserInfo storage userInfo = userInfos[_user];

        userInfo.isBlacklisted = _isBlacklisted;
        emit userBlacklistUpdate(_user, _isBlacklisted);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMCakeConvertor(address _mCake, address _mCakeConvertor) external onlyOwner {
        mCake = _mCake;
        mCakeConvertor = _mCakeConvertor;
        emit mCakeConvertorSet(_mCake, _mCakeConvertor);
    }

    function setSmartConvertor(address _smartConvertor) external onlyOwner {
        smartConvert = _smartConvertor;
        emit smartConvertorSet(_smartConvertor);
    }

    function setPancakeStaking(address _pancakeStaking) external onlyOwner {
        if (!Address.isContract(_pancakeStaking)) revert IsNotSmartContractAddress();

        pancakeStaking = _pancakeStaking;
        emit PancakeStakingSet(pancakeStaking);
    }

    function setSmartConvertProportion(uint256 _smartConvertProportion) external onlyOwner {
        require(
            _smartConvertProportion <= DENOMINATOR,
            "Smart convert Proportion cannot be greater than 100%."
        );
        smartConvertProportion = _smartConvertProportion;
        emit smartConvertProportionSet(_smartConvertProportion);
    }

    function setLockMCakeProportion(uint256 _lockMCakeProportion) external onlyOwner {
        require(
            _lockMCakeProportion <= DENOMINATOR,
            "Lock mCake Proportion cannot be greater than 100%."
        );
        lockMCakeProportion = _lockMCakeProportion;
        emit lockMCakeProportionSet(_lockMCakeProportion);
    }

    function setMultiplier(
        uint256[] calldata _multiplier,
        uint256[] calldata _tier
    ) external onlyOwner {
        if (_multiplier.length == 0 || _tier.length == 0 || (_multiplier.length != _tier.length))
            revert LengthMismatch();

        for (uint8 i; i < _multiplier.length; ++i) {
            if (_multiplier[i] == 0) revert InvalidAmount();
            if (i > 0) {
                require(_tier[i] > _tier[i - 1], "Reward tier values must be in increasing order.");
            }
            rewardMultiplier.push(_multiplier[i]);
            rewardTier.push(_tier[i]);
            tierLength += 1;
        }
    }

    function resetMultiplier() external onlyOwner {
        uint256 len = rewardMultiplier.length;
        for (uint8 i = 0; i < len; ++i) {
            rewardMultiplier.pop();
            rewardTier.pop();
        }

        tierLength = 0;
    }

    function adminWithdrawTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}
