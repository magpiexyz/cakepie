// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IMasterCakepie } from "../../interfaces/cakepie/IMasterCakepie.sol";
import { ILocker } from "../../interfaces/cakepie/ILocker.sol";
import { IMintableERC20 } from "../../interfaces/common/IMintableERC20.sol";

/// @title mCakeConvertor simply mints 1 mCake for each CAKE convert with cakepie
/// @author Magpie Team
/// @notice mCAKE is a token minted when 1 CAKE deposit on cakepie, the convert is irreversible, user will get mCAKE instead.

abstract contract mCakeConvertorBaseUpg is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public pancakeStaking;
    address public mCake;
    address public CAKE;
    address public masterCakepie;
    address public mCakeSV;

    uint256 public constant DENOMINATOR = 10000;

    uint256 immutable stakeMode = 1;
    uint256 immutable lockMode = 2;

    uint256[50] private __gap; // reserve for upgrade

    /* ============ Events ============ */

    event mCakeConverted(address indexed user, uint256 amount, uint256 mode);
    event PancakeStakingSet(address indexed _cakeStaking);
    event CakeConverted(uint256 _cakeAmount, uint256 _veCakeAmount);
    event CakeWithdrawToAdmin(address indexed user, uint256 amount);
    event mCakeSVUpdated(address indexed _mCakeSV);
    event MasterCakepieSet(address indexed _masterCakepie);

    /* ============ Errors ============ */

    error MasterCakepieNotSet();
    error PancakeStakingNotSet();
    error AddressZero();
    error MCakeSVNotSet();

    /* ============ External Functions ============ */

    /// @notice convert CAKE through cakepie and get mCAKE at a 1:1 rate
    /// @param _amount the amount of cake
    /// @param _mode 0 doing nothing but caller receive mCAKE, 1 is convert and stake
    function convert(
        address _for,
        uint256 _amount,
        uint256 _mode
    ) external whenNotPaused nonReentrant {
        IERC20(CAKE).safeTransferFrom(msg.sender, address(this), _amount);

        if (_mode == stakeMode) {
            if (masterCakepie == address(0)) revert MasterCakepieNotSet();

            IMintableERC20(mCake).mint(address(this), _amount);
            IERC20(mCake).safeApprove(address(masterCakepie), _amount);
            IMasterCakepie(masterCakepie).depositFor(address(mCake), _for, _amount);
        } else if (_mode == lockMode) {
            if (mCakeSV == address(0)) revert MCakeSVNotSet();

            IMintableERC20(mCake).mint(address(this), _amount);
            IERC20(mCake).safeApprove(address(mCakeSV), _amount);
            ILocker(mCakeSV).lockFor(_amount, _for);
        } else {
            _mode = 0; // if not recognized, default to 0, which is caller receives mCAKE
            IMintableERC20(mCake).mint(_for, _amount);
        }

        emit mCakeConverted(_for, _amount, _mode);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setCakeStaking(address _pancakeStaking) external onlyOwner {
        if (_pancakeStaking == address(0)) revert AddressZero();
        pancakeStaking = _pancakeStaking;

        emit PancakeStakingSet(pancakeStaking);
    }

    function setmCakeSV(address _mCakeSV) external onlyOwner {
        if (_mCakeSV == address(0)) revert AddressZero();
        mCakeSV = _mCakeSV;

        emit mCakeSVUpdated(mCakeSV);
    }

    function setMasterCakepie(address _masterCakepie) external onlyOwner {
        if (_masterCakepie == address(0)) revert AddressZero();
        masterCakepie = _masterCakepie;

        emit MasterCakepieSet(masterCakepie);
    }
}
