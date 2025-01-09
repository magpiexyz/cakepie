// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/cakepie/IPancakeStaking.sol";
import "../../interfaces/cakepie/IBaseRewardPool.sol";
import "../../interfaces/cakepie/IMasterCakepie.sol";

/// @title PancakeAMLHelper
/// @author Magpie Team
/// @notice This contract is the main contract that user will intreact with in order to depoist Wrapper Lp token on Cakepie. This
///         Helper will be shared among all wrapper pools on Pancake to deposit on Cakepie.

contract PancakeV2LPHelper is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    IPancakeStaking public pancakeStaking;
    IMasterCakepie public masterCakepie;

    /* ============ Events ============ */

    event NewDeposit(address indexed _user, address indexed _pool, uint256 _amount);
    event NewWithdraw(address indexed _user, address indexed _pool, uint256 _amount);

    /* ============ Errors ============ */

    error DeactivatePool();
    error AlreadyExist();
    error InvalidTokenId();
    error InvalidAmount();
    error AddressZero();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __PancakeV2LPHelper_init(address _pancakeStaking) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pancakeStaking = IPancakeStaking(_pancakeStaking);
    }

    /* ============ Modifiers ============ */

    modifier onlyActivePool(address _pool) {
        (, , , , , , , ,, bool isActive) = pancakeStaking.pools(_pool);
        if (!isActive) revert DeactivatePool();
        _;
    }

    /* ============ External Getters ============ */

    /// notice get the amount of total staked LP token in master cakepie
    function totalStaked(address _pool) external view returns (uint256) {
        (, , address rewarder, , ,, , , , ) = pancakeStaking.pools(_pool);
        return IBaseRewardPool(rewarder).totalStaked();
    }

    /// @notice get the total amount of shares of a user
    /// @param _pool the pancakeswap pool token
    /// @param _address the user
    /// @return the amount of shares
    function balance(address _pool, address _address) external view returns (uint256) {
        (, , address rewarder, , , ,, , , ) = pancakeStaking.pools(_pool);
        return IBaseRewardPool(rewarder).balanceOf(_address);
    }

    /* ============ External Functions ============ */

    function deposit(address _pool, uint256 _amount) external onlyActivePool(_pool) {
        IPancakeStaking(pancakeStaking).depositV2LPFor(msg.sender, _pool, _amount);

        emit NewDeposit(msg.sender, _pool, _amount);
    }

    function withdrawAndClaim(address _pool, uint256 _amount, bool _isClaim) external {
        (address pool, , , , , , , ,, ) = pancakeStaking.pools(_pool);
        IPancakeStaking(pancakeStaking).withdrawV2LPFor(msg.sender, _pool, _amount);

        if (_isClaim) _claimRewards(msg.sender, pool, 0);

        emit NewWithdraw(msg.sender, _pool, _amount);
    }

    function withdrawAndClaimMCake(address _pool, uint256 _amount, bool _isClaim, uint256 _minRecMCake) external {
        (address pool, , , , , , , ,, ) = pancakeStaking.pools(_pool);
        IPancakeStaking(pancakeStaking).withdrawV2LPFor(msg.sender, _pool, _amount);

        if (_isClaim) _claimRewards(msg.sender, pool, _minRecMCake);

        emit NewWithdraw(msg.sender, _pool, _amount);
    }

    function harvest(address _pool) external onlyActivePool(_pool) {
        address[] memory pool = new address[](1);
        pool[0] = _pool;
        IPancakeStaking(pancakeStaking).harvestV2LP(pool);
    }

    /* ============ Internal Functions ============ */

    function _claimRewards(address _for, address _pool, uint256 _minRecMCake) internal {
        address[] memory stakingTokens = new address[](1);
        stakingTokens[0] = _pool;
        address[][] memory rewardTokens = new address[][](1);
        if (address(masterCakepie) != address(0)) {
            if (_minRecMCake > 0) {
                IMasterCakepie(masterCakepie).multiclaimMCake(stakingTokens, rewardTokens, _for, _minRecMCake);
            } else {
                IMasterCakepie(masterCakepie).multiclaimFor(stakingTokens, rewardTokens, _for);
            }
        }
    }

    /* ============ Admin Functions ============ */

    function setMasterCakepie(address _masterCakepie) external onlyOwner {
        if (_masterCakepie == address(0)) revert AddressZero();
        masterCakepie = IMasterCakepie(_masterCakepie);
    }
}
