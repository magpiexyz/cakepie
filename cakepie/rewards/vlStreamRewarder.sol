// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { StreamRewarder } from "./StreamRewarder.sol";
import {IMasterCakepie} from "../../interfaces/cakepie/IMasterCakepie.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../interfaces/cakepie/ILocker.sol";
contract vlStreamRewarder is StreamRewarder, ReentrancyGuardUpgradeable{
    using SafeERC20 for IERC20;
    
    /* ================ State Variables ==================== */
    ILocker public vlToken; 
    address public cakepie;

    /* ============ Events ============ */
    event ForfeitRewardQueued(address rewardToken, uint256 amount);
    event CakepieHarvested(address account, uint256 rewardableAmount, uint256 forfeitAmount);

    /* ============ Errors ============ */
    error InvalidRewardableAmount();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __vlStreamRewarder_init(
        address _masterCakepie,
        address _rewardQueuer,
        address _receiptToken,
        address _cakepie
    ) public initializer {
        __StreamRewarder_init(_masterCakepie, _rewardQueuer, _receiptToken);
        __ReentrancyGuard_init();
        vlToken = ILocker(_receiptToken);
        cakepie = _cakepie;
    }

    /* ============ External Getters ============ */

    function balanceOf(address _account) public view override returns (uint256 ) {
        (uint256 staked, ) = IMasterCakepie(masterCakepie).stakingInfo(
            address(vlToken),
            _account
        );
        return staked;
    }

    function calExpireForfeit(address _account, address _rewardToken) public view returns(uint256) {
        return _calExpireForfeit(_account, earned(_account, _rewardToken));
    }

    function queueCakepie(uint256 _amount, address _account, address _receiver) external onlyMasterCakepie nonReentrant returns (bool) {
        IERC20(cakepie).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 forfeitAmount = _calExpireForfeit(_account, _amount);
        uint256 rewardableAmount = _amount - forfeitAmount;
        
        if (forfeitAmount > 0)
            _queueNewRewardsWithoutTransfer(forfeitAmount, address(cakepie));

        if (rewardableAmount > 0) {
            IERC20(cakepie).safeTransfer(_receiver, rewardableAmount);
            emit CakepieHarvested(_account, rewardableAmount, forfeitAmount);
        }
        return true;
    }
 
    /* ============ Internal Functions ============ */

    function _queueNewRewardsWithoutTransfer(uint256 _rewards, address _rewardToken) internal
    {
        _provisionReward(_rewards, _rewardToken);
        emit ForfeitRewardQueued(_rewardToken, _rewards);
    }

    function _sendReward(address _account, address _receiver, address _rewardToken) internal override{
        uint256 forfeitAmount = _calExpireForfeit(_account, userRewards[_rewardToken][_account].rewards);
        uint256 toSend = userRewards[_rewardToken][_account].rewards - forfeitAmount;
        userRewards[_rewardToken][_account].rewards = 0;
            
        if (toSend > 0) {
            IERC20(_rewardToken).safeTransfer(_receiver, toSend);
            emit RewardPaid(_account, _receiver, toSend, _rewardToken);
        }

        if(forfeitAmount > 0)
            _queueNewRewardsWithoutTransfer(forfeitAmount, _rewardToken);
    }

    function _calExpireForfeit(address _account, uint256 _amount) internal view returns (uint256) {
        uint256 rewardablePercentWAD = vlToken.getRewardablePercentWAD(_account);
        uint256 rewardableAmount = _amount * rewardablePercentWAD / 1e18;
        if (rewardableAmount > _amount)
            revert InvalidRewardableAmount();

        uint256 forfeitAmount = _amount - rewardableAmount;
        
        if (forfeitAmount < (_amount / 1000)) {  // if forfeitAmount is smaller than 0.1% ignore to save gas fee
            forfeitAmount = 0;
            rewardableAmount = _amount;
        }

        return forfeitAmount;
    }
}