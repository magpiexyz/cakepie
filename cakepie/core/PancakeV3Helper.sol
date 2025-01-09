// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/cakepie/IPancakeStaking.sol";

import "../../interfaces/pancakeswap/INonfungiblePositionManager.sol";
import "../../interfaces/pancakeswap/IPancakeV3PoolImmutables.sol";
import "../../interfaces/pancakeswap/INonfungiblePositionManagerStruct.sol";
import "../../interfaces/common/IWETH.sol";

import "../misc/Enumerable.sol";

/// @title PancakeV3Helper
/// @author Magpie Team
/// @notice This contract is the main contract that user will intreact with in order to depoist Lp token on Cakepie. This
///         Helper will be shared among all v3 pools on Pancake to deposit on Cakepie.

contract PancakeV3Helper is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Enumerable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public WETH;

    IPancakeStaking public pancakeStaking;
    INonfungiblePositionManager public nonfungiblePositionManager; // For V3 pool
    address public masterCakepie;

    mapping(uint256 => address) public tokenOwner;

    /* ============ Events ============ */

    event NewDeposit(address indexed _user, address indexed _pool, uint256 _tokenId);
    event NewWithdraw(address indexed _user, address indexed _pool, uint256 _tokenId);

    /* ============ Errors ============ */

    error DeactivatePool();
    error InvalidAmount();
    error InvalidPool();
    error TokenNotOwned();
    error OnlyMasterCakepie();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __PancakeV3Helper_init(
        address _WETH,
        address _pancakeStaking,
        address _nonfungiblePositionManager
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        WETH = _WETH;
        pancakeStaking = IPancakeStaking(_pancakeStaking);
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
    }

    /* ============ Modifiers ============ */

    modifier onlyActivePool(address _pool) {
        (, , , , , , , , , bool isActive) = pancakeStaking.pools(_pool);
        if (!isActive) revert DeactivatePool();
        _;
    }

    /* ============ External Functions ============ */

    function depositNFT(
        address _pool,
        uint256 _tokenId
    ) external nonReentrant onlyActivePool(_pool) {
        _checkForValidPool(_pool, _tokenId);

        addToken(msg.sender, _tokenId);
        tokenOwner[_tokenId] = msg.sender;

        IPancakeStaking(pancakeStaking).depositV3For(msg.sender, _pool, _tokenId);

        emit NewDeposit(msg.sender, _pool, _tokenId);
    }

    function withdrawNFT(address _pool, uint256 _tokenId) external nonReentrant {
        uint256[] memory tokenId = toArray(_tokenId);

        _checkForValidPool(_pool, _tokenId);

        if (!_isTokenOwner(msg.sender, tokenId)) revert TokenNotOwned();

        IPancakeStaking(pancakeStaking).withdrawV3For(msg.sender, _pool, _tokenId);

        delete tokenOwner[_tokenId];
        removeToken(msg.sender, _tokenId);

        emit NewWithdraw(msg.sender, _pool, _tokenId);
    }

    function increaseLiquidity(
        address _pool,
        uint256 _tokenId,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external payable nonReentrant onlyActivePool(_pool) {
        uint256[] memory tokenId = toArray(_tokenId);

        _checkForValidPool(_pool, _tokenId);

        if (!_isTokenOwner(msg.sender, tokenId)) revert TokenNotOwned();

        address token0 = IPancakeV3PoolImmutables(_pool).token0();
        address token1 = IPancakeV3PoolImmutables(_pool).token1();

        INonfungiblePositionManagerStruct.IncreaseLiquidityParams
            memory params = INonfungiblePositionManagerStruct.IncreaseLiquidityParams({
                tokenId: _tokenId,
                amount0Desired: _amount0Desired,
                amount1Desired: _amount1Desired,
                amount0Min: _amount0Min,
                amount1Min: _amount1Min,
                deadline: block.timestamp + 1200
            });

        pay(token0, _amount0Desired);
        pay(token1, _amount1Desired);

        if (token0 != WETH && token1 != WETH && msg.value > 0) revert InvalidAmount();

        IPancakeStaking(pancakeStaking).increaseLiquidityV3For(msg.sender, _pool, params);
    }

    function decreaseLiquidity(
        address _pool,
        uint256 _tokenId,
        uint128 _liquidity,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external nonReentrant onlyActivePool(_pool) {
        uint256[] memory tokenId = toArray(_tokenId);

        _checkForValidPool(_pool, _tokenId);

        if (!_isTokenOwner(msg.sender, tokenId)) revert TokenNotOwned();

        INonfungiblePositionManagerStruct.DecreaseLiquidityParams
            memory params = INonfungiblePositionManagerStruct.DecreaseLiquidityParams({
                tokenId: _tokenId,
                liquidity: _liquidity,
                amount0Min: _amount0Min,
                amount1Min: _amount1Min,
                deadline: block.timestamp + 1200
            });
        IPancakeStaking(pancakeStaking).decreaseLiquidityV3For(msg.sender, _pool, params);
    }

    function harvestReward(uint256[] memory tokenIds) external {
        if (!_isTokenOwner(msg.sender, tokenIds)) revert TokenNotOwned();

        IPancakeStaking(pancakeStaking).harvestV3(msg.sender, tokenIds);
    }

    function harvestFees(uint256[] memory tokenIds) external {
        if (!_isTokenOwner(msg.sender, tokenIds)) revert TokenNotOwned();

        IPancakeStaking(pancakeStaking).harvestV3PoolFees(msg.sender, tokenIds);
    }

    function harvestRewardAndFeeFor(address _for, uint256[] memory _tokenIds) external {
        if (msg.sender != masterCakepie) revert OnlyMasterCakepie();

        if (!_isTokenOwner(_for, _tokenIds)) revert TokenNotOwned();

        IPancakeStaking(pancakeStaking).harvestV3(_for, _tokenIds);

        IPancakeStaking(pancakeStaking).harvestV3PoolFees(_for, _tokenIds);
    }

    /* ============ Internal Functions ============ */

    function _checkForValidPool(address _pool, uint256 _tokenId) internal view {
        (
            ,
            ,
            address token0,
            address token1,
            uint256 fee,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(nonfungiblePositionManager).positions(_tokenId);

        address token0Pool = IPancakeV3PoolImmutables(_pool).token0();
        address token1Pool = IPancakeV3PoolImmutables(_pool).token1();
        uint256 feePool = IPancakeV3PoolImmutables(_pool).fee();

        if (token0Pool != token0 || token1Pool != token1) revert InvalidPool();
        if (feePool != fee) revert InvalidPool();
    }

    function _isTokenOwner(
        address _owner,
        uint256[] memory _tokenIds
    ) internal view returns (bool) {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (tokenOwner[_tokenIds[i]] != _owner) return false;
        }

        return true; // Owner owns all the tokens
    }

    function pay(address _token, uint256 _amount) internal {
        if (_token == WETH && msg.value > 0) {
            if (msg.value != _amount) revert InvalidAmount();
            _wrapNative(_token);
        } else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).safeIncreaseAllowance(address(pancakeStaking), _amount);
        }
    }

    function _wrapNative(address NATIVE) internal {
        IWETH(NATIVE).deposit{ value: msg.value }();
        IWETH(NATIVE).approve(address(pancakeStaking), msg.value);
    }

    function toArray(uint256 _tokenId) internal pure returns (uint256[] memory tokenId) {
        tokenId = new uint256[](1);
        tokenId[0] = _tokenId;
    }

    /* ============ Admin Functions ============ */

    function setMasterCakepie(address _masterCakepie) external onlyOwner {
        masterCakepie = _masterCakepie;
    }
}