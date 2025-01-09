// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PancakeStakingBaseUpg } from "../baseupgs/PancakeStakingBaseUpg.sol";
import "../../interfaces/pancakeswap/IAngelMerkl.sol";

import "../../interfaces/pancakeswap/IIFOV8.sol";
import "../../interfaces/pancakeswap/IICake.sol";
import "../../interfaces/cakepie/IPancakeIFOHelper.sol";

import { PancakeStakingLib } from "../../libraries/cakepie/PancakeStakingLib.sol";


/// @title PancakeStaking
/// @notice PancakeStaking is the main contract interacting with pancakeswap side.
/// @author Magpie Team

contract PancakeStakingSideChain is PancakeStakingBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public mCakeConvertorSideChain;
    address public cakepieIFOManager;

    /* ============ Events ============ */

    event mCakeConvertorSet(address _mCakeConvertor);
    event CakepieIFOManagerSet(address indexed cakepieIFOManager);
    event ApproveToLocker(address indexed _veCakeUser);
    event ArbRewardSentToDistributor(address indexed _receiver, uint256 _amount);

    /* ============ Errors ============ */

    error AddressZero();
    error OnlyIFOManager();
    error InvalidAddress();
    error InvalidLengths();

    /* ============ Constructor ============ */

    receive() external payable {}

    constructor() {
        _disableInitializers();
    }

    function __PancakeStakingSideChain_init(
        address _CAKE,
        address _mCake,
        address _masterCakepie
    ) public initializer {
        __PancakeStakingBaseUpg_init(_CAKE, _mCake, _masterCakepie);
    }

    /* ============ Modifiers ============ */
    
    modifier _onlyIFOManager() {
        if (msg.sender != cakepieIFOManager) revert OnlyIFOManager();
        _;
    }

    /* ============ External Functions ============== */

    function claimArbFromMerkl(
        uint256[] calldata _amount, 
        bytes32[][] calldata _proofs, 
        address _rewardToken,
        address _angleMerkleDistributor,
        address _arbRewardDistributor
    ) external whenNotPaused nonReentrant _onlyAllowedOperator {

        if (_angleMerkleDistributor == address(0)) revert InvalidAddress();
        if (_amount.length != _proofs.length ) revert InvalidLengths();
        
        address[] memory receiver = new address[](1);
        address[] memory arbTokenAddress = new address[](1);

        receiver[0] = address(this);
        arbTokenAddress[0] = _rewardToken;

        uint256 balBefore = IERC20(_rewardToken).balanceOf(address(this)); 

        IAngelMerkl(_angleMerkleDistributor).claim(
            receiver,
            arbTokenAddress,
            _amount,
            _proofs
        );

        uint256 balAfter = IERC20(_rewardToken).balanceOf(address(this)); 
        uint256 amountClaimed = balAfter - balBefore;

        if (amountClaimed > 0) {
            IERC20(_rewardToken).safeTransfer(_arbRewardDistributor, amountClaimed);
            emit ArbRewardSentToDistributor(_arbRewardDistributor, amountClaimed);
        }
    }

    

    /* ============ Admin Functions ============ */

    function setMCakeConvertorSideChain(address _mCakeConvertoSideChain) external onlyOwner {
        if (_mCakeConvertoSideChain == address(0)) revert AddressZero();
        mCakeConvertorSideChain = _mCakeConvertoSideChain;
        emit mCakeConvertorSet(mCakeConvertorSideChain);
    }

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

    function setCakepieIFOManager(address _cakepieIFOManager) external onlyOwner {
        if (_cakepieIFOManager == address(0)) revert AddressZero();
        cakepieIFOManager = _cakepieIFOManager;
        emit CakepieIFOManagerSet(_cakepieIFOManager);
    }

    function approveToLocker(
        address _iCake,
        address _veCakeUser
    ) external nonReentrant onlyOwner {
        if (_veCakeUser == address(0)) revert AddressZero();
        if (_iCake == address(0)) revert AddressZero();
        IICake(_iCake).approveToVECakeUser(_veCakeUser);
        emit ApproveToLocker(_veCakeUser);
    }
}