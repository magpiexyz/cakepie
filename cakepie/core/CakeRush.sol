// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IMasterCakepie } from "../../interfaces/cakepie/IMasterCakepie.sol";

/// @title CakeRush
/// @author Cakepie Team, an incentive program to accumulate cake
/// @notice cake will be transfered to admin and lock forever

contract CakeRush is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct UserInfo {
        uint256 converted; // orignial amount of Cake a user converted.
        uint256 factor; // accumulated factor received without considering weighting
        uint256 weightedConverted; // not in use, keep upgradable happy
        uint256 weightedFactor; // accumulated factor received after considering weighting
    }

    uint256 public constant DENOMINATOR = 10000;

    address public cake;
    address public mCakeOFT;
    address public masterCakepie;

    uint256 public totalFactor;
    uint256 public totalConverted;
    uint256 public weightedTotalFactor;
    uint256 public weightedTotalConverted; // not in use, keep upgradable happy

    uint256 public tierLength;
    uint256 public weightLength;

    mapping(address => uint256) public claimedMCake;
    mapping(address => UserInfo) public userInfos;

    uint256[] public rewardMultiplier;
    uint256[] public rewardTier;
    uint256[] public weighting; // factor multiplier
    uint256[] public weightedTime; //  timestamp for users get multiplier of their receiving factor

    //1st upgrade
    address public pancakeStaking;

    /* ============ Events ============ */

    event Convert(
        address indexed _user,
        uint256 _amount,
        uint256 _factorReceived,
        uint256 _weightedFactorRec,
        uint256 timestamp,
        uint256 weighting
    );

    event DelegationConvert(
        address indexed _user,
        uint256 _amount,
        uint256 _factorReceived,
        uint256 _weightedFactorRec,
        uint256 timestamp,
        uint256 weighting
    );

    event Claim(address indexed _user, uint256 _amount);

    event SetAddresses(
        address _oldMCakeOFT,
        address _newMCakeOFT,
        address _oldMasterCakepie,
        address _newMasterCakepie
    );
    event OwnerWithdraw(address indexed _owner, uint256 _amount);
    event PancakeStakingSet(address indexed _cakeStaking);

    /* ============ Errors ============ */

    error ZeroAddress();
    error InvalidAmount();
    error LengthInvalid();
    error MasterCakepieNotSet();
    error AlreadyClaimed();
    error OnlyPancakeStaking();
    error AddressZero();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __CakeRush_init(
        address _cake,
        address _mCakeOFT,
        address _masterCakepie
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        cake = _cake;
        mCakeOFT = _mCakeOFT;
        masterCakepie = _masterCakepie;
    }

    /* ============ Modifier ============ */

    modifier _onlyPancakeStaking() {
        if (pancakeStaking == address(0) || msg.sender != pancakeStaking)
            revert OnlyPancakeStaking();
        _;
    }

    /* ============ External Read Functions ============ */
    function quoteConvert(
        uint256 _amountToConvert,
        address _account
    )
        external
        view
        returns (
            uint256 newUserFactor,
            uint256 newTotalFactor,
            uint256 newUserWeightedFactor,
            uint256 newWeightedTotalFactor
        )
    {
        if (_amountToConvert == 0 || rewardMultiplier.length == 0 || weighting.length == 0)
            return (
                userInfos[_account].factor,
                totalFactor,
                userInfos[_account].weightedFactor,
                weightedTotalFactor
            );

        UserInfo storage userInfo = userInfos[_account];
        uint256 accumulated = _amountToConvert + userInfo.converted;

        uint256 factorAccuNoWeighting = 0;
        uint256 i = 1;
        while (i < rewardTier.length && accumulated > rewardTier[i]) {
            factorAccuNoWeighting += (rewardTier[i] - rewardTier[i - 1]) * rewardMultiplier[i - 1];
            i++;
        }
        factorAccuNoWeighting += (accumulated - rewardTier[i - 1]) * rewardMultiplier[i - 1];

        uint256 factorToEarnNoWeighting = (factorAccuNoWeighting / DENOMINATOR) - userInfo.factor;

        newUserFactor = factorAccuNoWeighting / DENOMINATOR;
        newTotalFactor = totalFactor + factorToEarnNoWeighting;
        newUserWeightedFactor =
            (this.currentWeighting() * factorToEarnNoWeighting) /
            DENOMINATOR +
            userInfo.weightedFactor;
        newWeightedTotalFactor =
            weightedTotalFactor +
            (this.currentWeighting() * factorToEarnNoWeighting) /
            DENOMINATOR;
    }

    function getUserTier(address _account) public view returns (uint256) {
        uint256 userConverted = userInfos[_account].converted;
        for (uint256 i = tierLength - 1; i >= 1; i--) {
            if (userConverted >= rewardTier[i]) {
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

    function currentWeighting() external view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        for (uint256 i = 0; i < weightLength; i++) {
            if (currentTimestamp <= weightedTime[i]) {
                return (weighting[i]);
            }
        }

        return DENOMINATOR; // no multiplier effect if time passed last timestamp
    }

    function tiers()
        external
        view
        returns (uint256[] memory _rewardMultiplier, uint256[] memory _rewardTier)
    {
        _rewardMultiplier = rewardMultiplier;
        _rewardTier = rewardTier;
    }

    function weightings()
        external
        view
        returns (uint256[] memory _weighting, uint256[] memory _weightedTime)
    {
        _weighting = weighting;
        _weightedTime = weightedTime;
    }

    /* ============ External Write Functions ============ */

    function convert(uint256 _amount) external whenNotPaused nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];
        uint256 originalFactor = userInfo.factor;
        uint256 originalWeightedFactor = userInfo.weightedFactor;
        if (_amount == 0) revert InvalidAmount();

        IERC20(cake).safeTransferFrom(msg.sender, address(this), _amount);

        (userInfo.factor, totalFactor, userInfo.weightedFactor, weightedTotalFactor) = this
            .quoteConvert(_amount, msg.sender);

        userInfo.converted += _amount;
        totalConverted += _amount;

        emit Convert(
            msg.sender,
            _amount,
            userInfo.factor - originalFactor,
            userInfo.weightedFactor - originalWeightedFactor,
            block.timestamp,
            this.currentWeighting()
        );
    }

    function convertWithCakePool(address _for, uint256 _amount) external _onlyPancakeStaking {
        if (_amount == 0) revert InvalidAmount();

        UserInfo storage userInfo = userInfos[_for];
        uint256 originalFactor = userInfo.factor;
        uint256 originalWeightedFactor = userInfo.weightedFactor;

        (userInfo.factor, totalFactor, userInfo.weightedFactor, weightedTotalFactor) = this
            .quoteConvert(_amount, _for);

        userInfo.converted += _amount;
        totalConverted += _amount;

        emit DelegationConvert(
            _for,
            _amount,
            userInfo.factor - originalFactor,
            userInfo.weightedFactor - originalWeightedFactor,
            block.timestamp,
            this.currentWeighting()
        );
    }

    // Claim function will ba opend up when mCake token lanched. No need to be paused to claim.
    function claim(bool _isStake) external nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];
        if (claimedMCake[msg.sender] >= userInfo.converted) revert AlreadyClaimed();

        uint256 amountoClaim = userInfo.converted - claimedMCake[msg.sender];
        if (_isStake && userInfo.converted > 0) {
            if (masterCakepie == address(0)) revert MasterCakepieNotSet();
            IERC20(mCakeOFT).safeApprove(address(masterCakepie), amountoClaim);
            IMasterCakepie(masterCakepie).depositFor(
                address(mCakeOFT),
                address(msg.sender),
                amountoClaim
            );
        } else if (userInfo.converted > 0) {
            IERC20(mCakeOFT).transfer(msg.sender, amountoClaim);
            emit Claim(msg.sender, amountoClaim);
        }

        claimedMCake[msg.sender] += amountoClaim;
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMultiplier(
        uint256[] calldata _multiplier,
        uint256[] calldata _tier
    ) external onlyOwner {
        if (_multiplier.length == 0 || (_multiplier.length != _tier.length)) revert LengthInvalid();

        for (uint8 i = 0; i < _multiplier.length; ++i) {
            if (i > 0 && _multiplier[i - 1] >= _multiplier[i]) revert InvalidAmount();
            if (_multiplier[i] == 0) revert InvalidAmount();

            rewardMultiplier.push(_multiplier[i]);
            rewardTier.push(_tier[i]);
            tierLength += 1;
        }
    }

    function setTimeWeighting(
        uint256[] calldata _weightings,
        uint256[] calldata _weightedTimes
    ) external onlyOwner {
        if (_weightedTimes.length == 0 || (_weightedTimes.length != _weightings.length))
            revert LengthInvalid();

        for (uint8 i = 0; i < _weightedTimes.length; ++i) {
            if (i > 0 && _weightedTimes[i - 1] >= _weightedTimes[i]) revert InvalidAmount();
            if (_weightings[i] < DENOMINATOR || _weightedTimes[i] == 0) revert InvalidAmount();

            weightedTime.push(_weightedTimes[i]);
            weighting.push(_weightings[i]);
            weightLength += 1;
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

    function resetTimeWeighting() external onlyOwner {
        uint256 len = weightedTime.length;
        for (uint8 i = 0; i < len; ++i) {
            weightedTime.pop();
            weighting.pop();
        }

        weightLength = 0;
    }

    function setAddresses(address _mCakeOFT, address _masterCakepie) external onlyOwner {
        if (_mCakeOFT == address(0)) {
            revert ZeroAddress();
        }
        if (_masterCakepie == address(0)) {
            revert ZeroAddress();
        }
        address oldMCakeOFT = mCakeOFT;
        address oldMasterCakepie = masterCakepie;
        mCakeOFT = _mCakeOFT;
        masterCakepie = _masterCakepie;

        emit SetAddresses(oldMCakeOFT, _mCakeOFT, oldMasterCakepie, _masterCakepie);
    }

    function setCakeStaking(address _pancakeStaking) external onlyOwner {
        if (_pancakeStaking == address(0)) revert AddressZero();
        pancakeStaking = _pancakeStaking;

        emit PancakeStakingSet(pancakeStaking);
    }

    function adminWithdrawCake() external onlyOwner {
        uint256 cakeBalance = IERC20(cake).balanceOf(address(this));
        IERC20(cake).safeTransfer(owner(), cakeBalance);
        emit OwnerWithdraw(owner(), cakeBalance);
    }
}