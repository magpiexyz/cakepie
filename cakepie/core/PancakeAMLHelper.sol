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

contract PancakeAMLHelper is
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

    event NewDeposit(address indexed _user, address indexed _pool, uint256 _amount0, uint256 _amount1);
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

    function __PancakeAMLHelper_init(address _pancakeStaking) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pancakeStaking = IPancakeStaking(_pancakeStaking);
    }

    /* ============ Modifiers ============ */

    modifier onlyActivePool(address _pool) {
        (, , , , , , , , , bool isActive) = pancakeStaking.pools(_pool);
        if (!isActive) revert DeactivatePool();
        _;
    }

    /* ============ External Getters ============ */

    /// notice get the amount of total staked LP token in master cakepie
    function totalStaked(address _pool) external view returns (uint256) {
        (, , address rewarder, , , , , , , ) = pancakeStaking.pools(_pool);
        return IBaseRewardPool(rewarder).totalStaked();
    }

    /// @notice get the total amount of shares of a user
    /// @param _pool the Pendle Market token
    /// @param _address the user
    /// @return the amount of shares
    function balance(address _pool, address _address) external view returns (uint256) {
        (, , address rewarder, , , , , , , ) = pancakeStaking.pools(_pool);
        return IBaseRewardPool(rewarder).balanceOf(_address);
    }

    /* ============ External Functions ============ */

    function deposit(address _pool, uint256 _amount0, uint256 _amount1) external onlyActivePool(_pool) {
        IPancakeStaking(pancakeStaking).depositAMLFor(msg.sender, _pool, _amount0, _amount1);

        emit NewDeposit(msg.sender, _pool, _amount0, _amount1);
    }

    function withdrawAndClaim(address _pool, uint256 _amount, bool _isClaim) external {
        (address pool, , , , , , , , , ) = pancakeStaking.pools(_pool);
        IPancakeStaking(pancakeStaking).withdrawAMLFor(msg.sender, _pool, _amount);

        if (_isClaim) _claimRewards(msg.sender, pool);

        emit NewWithdraw(msg.sender, _pool, _amount);
    }

    function harvest(address _pool) external onlyActivePool(_pool) {
        address[] memory pool = new address[](1);
        pool[0] = _pool;
        IPancakeStaking(pancakeStaking).harvestAML(pool);
    }

    /* ============ Internal Functions ============ */

    function _claimRewards(address _for, address _pool) internal {
        address[] memory stakingTokens = new address[](1);
        stakingTokens[0] = _pool;
        address[][] memory rewardTokens = new address[][](1);
        if (address(masterCakepie) != address(0))
            IMasterCakepie(masterCakepie).multiclaimFor(stakingTokens, rewardTokens, _for);
    }

    /* ============ Admin Functions ============ */

    function setMasterCakepie(address _masterCakepie) external onlyOwner {
        if (_masterCakepie == address(0)) revert AddressZero();
        masterCakepie = IMasterCakepie(_masterCakepie);
    }
}
