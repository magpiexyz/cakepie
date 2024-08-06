// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../../interfaces/cakepie/IBaseRewardPool.sol";
import "../../interfaces/cakepie/IConvertor.sol";
import "../../interfaces/cakepie/IMasterCakepie.sol";
import "../../interfaces/pancakeswap/ISmartCakeConvertor.sol";

/// @title RewardHelper
/// @dev RewardHelper is the helper contract that help Pancakestaking contract to send user rewards into baseRewarder
/// @author Magpie Team

contract RewardDistributor is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct Fees {
        uint256 value; // allocation denominated by DENOMINATOR
        address to;
        bool isMCAKE;
        bool isAddress;
        bool isActive;
    }

    /* ============ State Variables ============ */
    address public CAKE;
    address public pancakeStaking;
    address public cakepie;
    IMasterCakepie public masterCakepie;
    IConvertor public mCakeConvertor;

    // Lp Fees
    uint256 public totalPancakePoolFee;
    uint256 public totalVeCakePoolFee;
    uint256 public totalRevenueFees;
    uint256 public totalCKPFees;

    Fees[] public pancakeFeeInfos; // reward distribution setting for reward from pancake
    Fees[] public veCakeFeeInfos; // reward distribution setting for veCAKE rewards from pancake
    Fees[] public revenueShareFeeInfo; // revenue distribution setting for veCAKE revenue from pancake

    // cakepie tokens emit for pancake V3 pool
    uint256 public CKPRatio;
    uint32 public constant DENOMINATOR = 10000;

    address public mCake;
    address public smartCakeConvert;

    /* ============ Errors ============ */

    error InvalidFee();
    error InvalidIndex();
    error OnlyRewardQeuer();
    error ExceedsDenominator();
    error AddressZero();
    error InvalidAddress();
    error minReceivedNotMet();
    /* ============ Events ============ */

    // Fee
    event AddVeCakeFees(address _to, uint256 _value, bool _isForVeCake, bool _isAddress);
    event AddPancakeFees(address _to, uint256 _value, bool _isAddress);
    event SetVeCakeOrRevenueFee(address _to, uint256 _value, bool _isForVeCake);
    event SetPancakeFee(address _to, uint256 _value);
    event RemoveVeCakeOrRevenueFee(uint256 value, address to, bool _isAddress, bool _isForVeCake);
    event RemoveCKPOrPancakeFee(uint256 value, address to, bool _isAddress);

    event RewardPaidTo(
        address _rewardSource,
        address _to,
        address _rewardToken,
        uint256 _feeAmount
    );

    event VeRewardPaidTo(
        address _rewardSource,
        address _to,
        address _rewardToken,
        uint256 _feeAmount
    );

    event RewardFeeDustTo(address _reward, address _to, uint256 _amount);

    event SmartCakeConvertUpdated(address _OldSmartCakeConvert, address _smartCakeConvert);
    /* ============ Modifiers ============ */

    modifier _onlyRewardQeuer() {
        if (msg.sender != pancakeStaking) revert OnlyRewardQeuer();
        _;
    }

    /* ============ Constructor ============ */

    function __RewardDistributor_init(
        address _cake,
        address _pancakeStaking,
        address _mCakeConvertor
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        CAKE = _cake;
        pancakeStaking = _pancakeStaking;
        mCakeConvertor = IConvertor(_mCakeConvertor);
    }

    /* ============ External Read Function ============ */

    /// @dev Send revenue Shares rewards to the rewarders
    /// @param _rewardToken the address of the reward token to send
    /// @param _amount total reward amount to distribute
    function sendVeReward(
        address _rewardSource,
        address _rewardToken,
        uint256 _amount,
        bool _isVeCake,
        uint256 _minRec
    ) external nonReentrant _onlyRewardQeuer {
        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _leftRewardAmount = _amount;
        uint256 totalMCake = 0;
        Fees[] memory feeInfo;

        if (_isVeCake) feeInfo = veCakeFeeInfos;
        else feeInfo = revenueShareFeeInfo;

        for (uint256 i = 0; i < feeInfo.length; i++) {
            if (feeInfo[i].isActive) {
                address rewardToken = _rewardToken;
                uint256 feeAmount = (_amount * feeInfo[i].value) / DENOMINATOR;
                uint256 feeToSend = feeAmount;
                _leftRewardAmount -= feeToSend;

                if(feeInfo[i].isMCAKE) {
                    if (feeAmount > 0){
                        feeToSend = _convertToMCake(feeAmount);
                    }
                    rewardToken = mCake;
                    totalMCake += feeToSend;
                }
                if (feeToSend > 0){
                    _distributeReward(feeInfo[i], rewardToken, feeToSend, _rewardSource, true);
                }
            }
        }

        if(totalMCake < _minRec) {
           revert minReceivedNotMet();
        }

        if (_leftRewardAmount > 0) {
            IERC20(_rewardToken).safeTransfer(owner(), _leftRewardAmount);
            emit RewardFeeDustTo(_rewardToken, owner(), _leftRewardAmount);
        }
    }

    /// @dev Send rewards to the rewarders. This should only be called for rewards from pancake for Lps (not revenue share nor reward for VeCake)
    /// @param _poolAddress the address reward come from harvesting
    /// @param _rewardToken the address of the reward token to send
    /// @param _finalDestination the final destintation after fee is charged and distributed
    /// @param _amount total reward amount to distribute
    /// @param _isRewarder address _to is user ot rewarder address
    function sendRewards(
        address _poolAddress,
        address _rewardToken,
        address _finalDestination,
        uint256 _amount,
        bool _isRewarder
    ) external nonReentrant _onlyRewardQeuer {
        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 _leftRewardAmount = _amount;

        for (uint256 i = 0; i < pancakeFeeInfos.length; i++) {
            if (pancakeFeeInfos[i].isActive) {
                address rewardToken = _rewardToken;
                uint256 feeAmount = (_amount * pancakeFeeInfos[i].value) / DENOMINATOR;
                _leftRewardAmount -= feeAmount;
                uint256 feeTosend = feeAmount;

                
                if(pancakeFeeInfos[i].isMCAKE) {
                    if (feeAmount > 0) {
                        feeTosend = _convertToMCake(feeAmount);
                    }
                    rewardToken = mCake;
                }
                if (feeTosend > 0){
                    _distributeReward(pancakeFeeInfos[i], rewardToken, feeTosend, _poolAddress, false);
                }
            }
        }

        _handleTransfer(
            _poolAddress,
            _finalDestination,
            _rewardToken,
            _leftRewardAmount,
            _isRewarder
        );

        emit RewardPaidTo(_poolAddress, _finalDestination, _rewardToken, _leftRewardAmount);
    }

    /* ============ Admin Functions ============ */

    function setCakepieRatio(uint256 _ckpRatio) external onlyOwner {
        CKPRatio = _ckpRatio;
    }

    /// @dev This function adds a fee to the Radpie protocol
    /// @param _value the initial value for that fee
    /// @param _to the address or contract that receives the fee
    /// @param _isMCAKE true if the fee is sent as MCAKE, otherwise it will be false
    /// @param _isAddress true if the receiver is an address, otherwise it's a BaseRewarder
    /// @param _isVeCakeFee true if it's a VeCake fee, false if it's a revenue fee
    function addVeCakeFees(
        uint256 _value,
        address _to,
        bool _isMCAKE,
        bool _isAddress,
        bool _isVeCakeFee
    ) external onlyOwner {
        if (_isVeCakeFee && totalVeCakePoolFee + _value > DENOMINATOR) revert ExceedsDenominator();
        if (!_isVeCakeFee && totalRevenueFees + _value > DENOMINATOR) revert ExceedsDenominator();

        Fees[] storage targetFeeInfos = _isVeCakeFee ? veCakeFeeInfos : revenueShareFeeInfo;

        _addfee(targetFeeInfos, _value, _isMCAKE, _to, _isAddress);

        if (_isVeCakeFee) {
            totalVeCakePoolFee += _value;
        } else {
            totalRevenueFees += _value;
        }

        emit AddVeCakeFees(_to, _value, _isVeCakeFee, _isAddress);
    }

    /// @dev This function adds a fee to the Radpie protocol
    /// @param _value the initial value for that fee
    /// @param _to the address or contract that receives the fee
    /// @param _isMCAKE true if the fee is sent as MCAKE, otherwise it will be false
    /// @param _isAddress true if the receiver is an address, otherwise it's a BaseRewarder
    function addPancakeFees(uint256 _value, address _to, bool _isMCAKE , bool _isAddress) external onlyOwner {
        if (totalPancakePoolFee + _value > DENOMINATOR) revert ExceedsDenominator();

        _addfee(pancakeFeeInfos, _value, _isMCAKE , _to, _isAddress);

        totalPancakePoolFee += _value;
        emit AddPancakeFees(_to, _value, _isAddress);
    }

    /// @dev This function changes the value of a VeCake or Revenue fee
    /// @param _index the index of the fee in the fee list
    /// @param _value the new value of the fee
    /// @param _to the address or contract that receives the fee
    /// @param _isVeCakeFee true if it's a VeCake fee, false if it's a Revenue fee
    /// @param _isAddress true if the receiver is an address, otherwise it's a BaseRewarder
    /// @param _isActive true if the fee is active, false if inactive
    function setVeCakeOrRevenueFee(
        uint256 _index,
        uint256 _value,
        address _to,
        bool _isVeCakeFee,
        bool _isAddress,
        bool _isActive,
        bool isMCake
    ) external onlyOwner {
        Fees[] storage feeInfo = _isVeCakeFee ? veCakeFeeInfos : revenueShareFeeInfo;

        uint256 currentTotalFee;
        uint256 updatedTotalFee;

        if (_isVeCakeFee) {
            currentTotalFee = totalVeCakePoolFee;
            updatedTotalFee = currentTotalFee - feeInfo[_index].value + _value;
        } else {
            currentTotalFee = totalRevenueFees;
            updatedTotalFee = currentTotalFee - feeInfo[_index].value + _value;
        }

        if (updatedTotalFee > DENOMINATOR) {
            revert ExceedsDenominator();
        }
        if (_isVeCakeFee) totalVeCakePoolFee = updatedTotalFee;
        else totalRevenueFees = updatedTotalFee;

        _setFee(_index, _value, _to, _isAddress, _isActive, isMCake, feeInfo);

        emit SetVeCakeOrRevenueFee(_to, _value, _isVeCakeFee);
    }

    /// @dev This function changes the value of a CKP or Pancake fee
    /// @param _index the index of the fee in the fee list
    /// @param _value the new value of the fee
    /// @param _to the address or contract that receives the fee
    /// @param _isAddress true if the receiver is an address, otherwise it's a BaseRewarder
    /// @param _isActive true if the fee is active, false if inactive
    function setPancakeFee(
        uint256 _index,
        uint256 _value,
        address _to,
        bool _isAddress,
        bool _isActive,
        bool isMcake
    ) external onlyOwner {
        uint256 currentTotalFee = totalPancakePoolFee;
        uint256 updatedTotalFee = currentTotalFee - pancakeFeeInfos[_index].value + _value;

        if (updatedTotalFee > DENOMINATOR) {
            revert ExceedsDenominator();
        }

        totalPancakePoolFee = updatedTotalFee;

        _setFee(_index, _value, _to, _isAddress, _isActive, isMcake, pancakeFeeInfos);

        emit SetPancakeFee(_to, _value);
    }

    function config(address _setMCake, address _mCakeConvertor, address _smartCakeConvert) external onlyOwner {
        mCake = _setMCake;
        mCakeConvertor = IConvertor(_mCakeConvertor);
        if (_smartCakeConvert != address(0)) {
            address oldSmartCakeConvert = smartCakeConvert;
            smartCakeConvert = _smartCakeConvert;

            emit SmartCakeConvertUpdated(oldSmartCakeConvert, smartCakeConvert);
        }
    }

    /// @dev Remove a VeCake or Revenue fee
    /// @param _index the index of the fee in the fee list
    function removeVeCakeOrRevenueFee(uint256 _index, bool _isVeCakeFee) external onlyOwner {
        Fees[] storage feeInfo = _isVeCakeFee ? veCakeFeeInfos : revenueShareFeeInfo;

        if (_index >= feeInfo.length) revert InvalidIndex();

        if (_isVeCakeFee) totalVeCakePoolFee = totalVeCakePoolFee - feeInfo[_index].value;
        else totalRevenueFees = totalRevenueFees - feeInfo[_index].value;

        Fees memory feeToRemove = feeInfo[_index];

        _removeFee(_index, feeInfo);

        emit RemoveVeCakeOrRevenueFee(
            feeToRemove.value,
            feeToRemove.to,
            feeToRemove.isAddress,
            _isVeCakeFee
        );
    }

    /// @dev Remove a CKP or Pancake fee
    /// @param _index the index of the fee in the fee list
    function removePancakeFee(uint256 _index) external onlyOwner {
        if (_index >= pancakeFeeInfos.length) revert InvalidIndex();

        totalPancakePoolFee = totalPancakePoolFee - pancakeFeeInfos[_index].value;

        Fees memory feeToRemove = pancakeFeeInfos[_index];

        _removeFee(_index, pancakeFeeInfos);

        emit RemoveCKPOrPancakeFee(feeToRemove.value, feeToRemove.to, feeToRemove.isAddress);
    }

    /* ============ Internal Functions ============ */

    function _addfee(
        Fees[] storage feeInfos,
        uint256 _value,
        bool _isMCAKE,
        address _to,
        bool _isAddress
    ) internal {
        if (_value > DENOMINATOR) revert InvalidFee();
        feeInfos.push(Fees({ value: _value, to: _to, isMCAKE: _isMCAKE , isAddress: _isAddress, isActive: true }));
    }

    // Internal function to change the value of a fee
    function _setFee(
        uint256 _index,
        uint256 _value,
        address _to,
        bool _isAddress,
        bool _isActive,
        bool isMcake,
        Fees[] storage feeInfo
    ) internal {
        if (_value > DENOMINATOR) {
            revert InvalidFee();
        }

        if (_index >= feeInfo.length) {
            revert InvalidIndex();
        }

        Fees storage fee = feeInfo[_index];
        fee.to = _to;
        fee.isAddress = _isAddress;
        fee.isActive = _isActive;
        fee.value = _value;
        fee.isMCAKE = isMcake;
    }

    // Internal function to remove a fee
    function _removeFee(uint256 _index, Fees[] storage feeInfos) internal {
        for (uint256 i = _index; i < feeInfos.length - 1; i++) {
            feeInfos[i] = feeInfos[i + 1];
        }
        feeInfos.pop();
    }

    function _handleTransfer(
        address _pool,
        address _finalDestination,
        address _rewardToken,
        uint256 _amount,
        bool _isRewarder
    ) internal {
        // For V2 and AML pools
        if (_isRewarder) {
            IERC20(_rewardToken).safeIncreaseAllowance(_finalDestination, _amount);
            IBaseRewardPool(_finalDestination).queueNewRewards(_amount, _rewardToken);
        } else {
            IERC20(_rewardToken).safeTransfer(_finalDestination, _amount);

            if (cakepie != address(0)) {
                // assuming only reward from V3 pool type does not go through rewarder
                uint256 CKPrewardAmount = (_amount * CKPRatio) / DENOMINATOR;

                IERC20(cakepie).safeTransfer(_finalDestination, CKPrewardAmount);

                emit RewardPaidTo(_pool, _finalDestination, address(cakepie), CKPrewardAmount);
            }
        }
    }

    function _convertToMCake(uint256 _feeAmount) internal returns (uint256) {
        uint256 beforeBalance = IERC20(mCake).balanceOf(address(this));

        if (smartCakeConvert != address(0)) {
            IERC20(CAKE).safeApprove(smartCakeConvert,_feeAmount);
            ISmartCakeConvertor(smartCakeConvert).smartConvert(_feeAmount, 0);
        } else {
            IERC20(CAKE).safeApprove(address(mCakeConvertor), _feeAmount);
            mCakeConvertor.convert(address(this), _feeAmount, 0);
        }

        return IERC20(mCake).balanceOf(address(this)) - beforeBalance;
    }

    function _distributeReward(Fees memory _fee, address _rewardToken, uint256 _feeToSend, address _rewardSource, bool _isVeReward) internal {
        if (!_fee.isAddress) {
            IERC20(_rewardToken).safeApprove(_fee.to, _feeToSend);
            IBaseRewardPool(_fee.to).queueNewRewards(_feeToSend, _rewardToken);
        } else {
            IERC20(_rewardToken).safeTransfer(_fee.to, _feeToSend);
        }

        if(_isVeReward){
            emit VeRewardPaidTo(_rewardSource, _fee.to, _rewardToken, _feeToSend);
        }
        else{
            emit RewardPaidTo(_rewardSource, _fee.to, _rewardToken, _feeToSend);
        }
    }
}
