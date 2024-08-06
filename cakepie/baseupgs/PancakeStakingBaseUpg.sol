// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IERC721ReceiverUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

import { IMasterCakepie } from "../../interfaces/cakepie/IMasterCakepie.sol";

import { INonfungiblePositionManager } from "../../interfaces/pancakeswap/INonfungiblePositionManager.sol";
import { IMasterChefV3 } from "../../interfaces/pancakeswap/IMasterChefV3.sol";
import { IALMWrapper } from "../../interfaces/pancakeswap/IALMWrapper.sol";
import { IAdapter } from "../../interfaces/pancakeswap/IAdapter.sol";
import { IV2Wrapper } from "../../interfaces/pancakeswap/IV2Wrapper.sol";

import { ERC20FactoryLib } from "../../libraries/cakepie/ERC20FactoryLib.sol";
import { PancakeStakingLib } from "../../libraries/cakepie/PancakeStakingLib.sol";
import { IMintableERC20 } from "../../interfaces/common/IMintableERC20.sol";
import { IRewardDistributor } from "../../interfaces/cakepie/IRewardDistributor.sol";
import { IPancakeV3Helper } from "../../interfaces/cakepie/IPancakeV3Helper.sol";
import "../../interfaces/cakepie/IBaseRewardPool.sol";

/// @title PancakeStakingBaseUpg
/// @notice PancakeStakingBaseUpg is the base contract that holds cakepie common features across all supported chains (BNB, ETH, ARB)
///         PancakeStakingBaseUpg is the main contract interacting with pancakeswap
/// @author Magpie Team

abstract contract PancakeStakingBaseUpg is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IERC721ReceiverUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct Pool {
        address poolAddress; // For V2, V3, it's Lp address, for AML it's wrapper addresss
        address depositToken; // For V2, it's Lp address, For V3 it's single side token, For AML pools it's single side token address else Address(0)
        address rewarder; // only for V2 and AML,
        address receiptToken; // only for V2 and AML,
        uint256 lastHarvestTime; // only for V2 and AML,
        uint256 poolType; // specifying V2, V3 or AML pool
        uint256 v3Liquidity; // tracker for totla v3 liquidity
        bool isAmount0; // only applicable for AML pool, if the deposit token is token0 or token1 then true or false correspondingly , if the deposit token is Address(0) then false
        bool isNative;
        bool isActive;
    }

    /* ============ State Variables ============ */
    // Cakepie core addresses
    IERC20 public CAKE;
    IERC20 public mCake;
    address public voteManager;

    // IMasterCakepie public marketDepositHelper;
    IMasterCakepie public masterCakepie;
    IRewardDistributor public rewardDistributor;

    address public pancakeV3Helper;
    address public pancakeV2LPHelper;
    address public pancakeAMLHelper;

    // Pancake address to interact
    INonfungiblePositionManager public nonfungiblePositionManager; // For V3 pool
    IMasterChefV3 public masterChefV3; // For V3 pool

    mapping(address => Pool) public pools;
    address[] public poolList;
    uint256 public poolLength;

    uint256 public harvestTimeGap;

    mapping(address => bool) public allowedOperator;

    // 1st upgrade
    uint256 public V3Type;
    uint256 public V2Type;
    uint256 public AMLType;

    // 2nd upgrade
    uint256 public StableSwapType;

    uint256[46] private __gap;

    /* ============ Events ============ */

    event PoolAdded(address _poolAddress, address _rewarder, address _receiptToken);
    event NewTokenStaked(
        address indexed _user,
        address indexed _poolAddress,
        uint256 _tokenID,
        uint256 _liquidity
    );
    event NewTokenUnstaked(
        address indexed _user,
        address indexed _poolAddress,
        uint256 _tokenID,
        uint256 _liquidity
    );

    event NewV2Deposit(
        address indexed _user,
        address indexed _pool,
        uint256 _amount,
        address indexed _receptToken,
        uint256 _receptAmount
    );
    event NewAMLV2Withdraw(
        address indexed _user,
        address indexed _pool,
        uint256 _amount,
        address indexed _receptToken,
        uint256 _receptAmount
    );

    event NewAMLV3Deposit(
        address indexed _user,
        address indexed _pool,
        uint256 _amount0,
        uint256 _amount1,
        address indexed _receptToken,
        uint256 _receptAmount
    );

    event NewAMLV3Withdraw(
        address indexed _user,
        address indexed _pool,
        uint256 _amount,
        address indexed _receptToken,
        uint256 _receptAmount
    );

    event AllowedOperatorSet(address _operator, bool _active);
    event VoteManagerSet(address _oldVoteManager, address _newVoteManager);
    event V3PoolFeesPaidTo(
        address indexed _user,
        uint256 _positionId,
        address _token,
        uint256 _feeAmount
    );

    /* ============ Errors ============ */

    error OnlyFarmHelper();
    error OnlyActivePool();
    error PoolOccupied();
    error TimeGapTooMuch();
    error OnlyAMLHelper();
    error OnlyVoteManager();
    error LengthMismatch();
    error OnlyAllowedOperator();
    error InvalidPoolType();
    /* ============ Constructor ============ */

    function __PancakeStakingBaseUpg_init(
        address _CAKE,
        address _mCake,
        address _masterCakepie
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        CAKE = IERC20(_CAKE);
        mCake = IERC20(_mCake);
        masterCakepie = IMasterCakepie(_masterCakepie);
    }

    /* ============ Modifiers ============ */

    modifier _onlyPoolHelper(address _helper) {
        if (msg.sender != _helper) {
            revert("OnlyHelper");
        }
        _;
    }

    modifier _onlyAllowedOperator() {
        if (!allowedOperator[msg.sender]) revert OnlyAllowedOperator();
        _;
    }

    /* ============ External Functions ============ */

    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function depositV3For(
        address _for,
        address _v3Pool,
        uint256 _tokenId
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeV3Helper) {
        PancakeStakingLib.depositV3For(_for, _v3Pool, _tokenId, masterChefV3, nonfungiblePositionManager);
     }

    function withdrawV3For(
        address _for,
        address _v3Pool,
        uint256 _tokenId
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeV3Helper) {
        PancakeStakingLib.withdrawV3For(_for, _v3Pool, _tokenId, address(CAKE), masterChefV3, rewardDistributor, nonfungiblePositionManager);
    }

    function increaseLiquidityV3For(
        address _for,
        address _v3Pool,
        IMasterChefV3.IncreaseLiquidityParams calldata params
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeV3Helper) {
        PancakeStakingLib.increaseLiquidityV3For(_for, _v3Pool, masterChefV3, params);
    }

    function decreaseLiquidityV3For(
        address _for,
        address _v3Pool,
        IMasterChefV3.DecreaseLiquidityParams calldata params
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeV3Helper) {
        PancakeStakingLib.decreaseLiquidityV3For(_for, masterChefV3, nonfungiblePositionManager, params);
    }

    function depositV2LPFor(
        address _for,
        address _pool,
        uint256 _amount
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeV2LPHelper) {
        Pool storage poolInfo = pools[_pool];

        IERC20(poolInfo.depositToken).safeTransferFrom(_for, address(this), _amount);
        IERC20(poolInfo.depositToken).safeIncreaseAllowance(poolInfo.poolAddress, _amount);

        uint256 balBefore = IERC20(CAKE).balanceOf(address(this));

        if (poolInfo.lastHarvestTime + harvestTimeGap > block.timestamp){
            IV2Wrapper(poolInfo.poolAddress).deposit(_amount, true);
        }
        else {
            IV2Wrapper(poolInfo.poolAddress).deposit(_amount, false);
            poolInfo.lastHarvestTime = block.timestamp;
        }

        PancakeStakingLib.handleRewards(rewardDistributor, poolInfo.poolAddress, address(CAKE), balBefore, poolInfo.rewarder, true);

        IMintableERC20(poolInfo.receiptToken).mint(_for, _amount);

        emit NewV2Deposit(_for, poolInfo.poolAddress, _amount, poolInfo.receiptToken, _amount);
    }

    function withdrawV2LPFor(
        address _for,
        address _pool,
        uint256 _amount
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeV2LPHelper) {
        Pool storage poolInfo = pools[_pool];

        uint256 balBefore = IERC20(CAKE).balanceOf(address(this));

        if (poolInfo.lastHarvestTime + harvestTimeGap > block.timestamp){
            IV2Wrapper(poolInfo.poolAddress).withdraw(_amount, true);
        }
        else {
            IV2Wrapper(poolInfo.poolAddress).withdraw(_amount, false);
            poolInfo.lastHarvestTime = block.timestamp;
        }

        PancakeStakingLib.handleRewards(rewardDistributor, poolInfo.poolAddress, address(CAKE), balBefore, poolInfo.rewarder, true);

        IMintableERC20(poolInfo.receiptToken).burn(_for, _amount);

        IERC20(poolInfo.depositToken).safeTransfer(_for, _amount);

        emit NewAMLV2Withdraw(_for, poolInfo.poolAddress, _amount, poolInfo.receiptToken, _amount);
    }

    function depositAMLFor(
        address _for,
        address _pool,
        uint256 _amount0,
        uint256 _amount1
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeAMLHelper) {
        Pool memory poolInfo = pools[_pool];
        uint256 balBefore = IERC20(CAKE).balanceOf(address(this));
        (uint256 _liquidityBefore, ) = IALMWrapper(poolInfo.poolAddress).userInfo(address(this));

        _depositTokens(_for, poolInfo, _amount0, _amount1);

        (uint256 _liquidityAfter, ) = IALMWrapper(poolInfo.poolAddress).userInfo(address(this));
        PancakeStakingLib.handleRewards(rewardDistributor, poolInfo.poolAddress, address(CAKE), balBefore, poolInfo.rewarder, true);
        IMintableERC20(poolInfo.receiptToken).mint(_for, _liquidityAfter - _liquidityBefore);

        emit NewAMLV3Deposit(
            _for,
            _pool,
            _amount0,
            _amount1,
            poolInfo.receiptToken,
            _liquidityAfter - _liquidityBefore
        );
    }

    function withdrawAMLFor(
        address _for,
        address _pool,
        uint256 _amount
    ) external nonReentrant whenNotPaused _onlyPoolHelper(pancakeAMLHelper) {
        Pool memory poolInfo = pools[_pool];

        address _adpaterAddress = IALMWrapper(poolInfo.poolAddress).adapterAddr();

        address token0 = IAdapter(_adpaterAddress).token0();
        address token1 = IAdapter(_adpaterAddress).token1();

        (, address[] memory poolAddressed) = PancakeStakingLib.toArray(0, address(poolInfo.poolAddress));
        // We have to harvest first since CAKE token can be reward or liquidity
        _harvestLP(poolAddressed, false);

        PancakeStakingLib.handleWithdrawAML(_for, poolInfo.poolAddress, _amount, token0, token1, poolInfo.rewarder, address(CAKE), rewardDistributor);

        IMintableERC20(poolInfo.receiptToken).burn(_for, _amount);

        emit NewAMLV3Withdraw(_for, poolInfo.poolAddress, _amount, poolInfo.receiptToken, _amount);
    }

    function harvestV3(
        address _for,
        uint256[] memory _tokenIds
    ) external nonReentrant _onlyPoolHelper(pancakeV3Helper) {
        PancakeStakingLib.harvestV3(_for, _tokenIds, address(CAKE), masterChefV3, rewardDistributor);
    }

    function harvestV3PoolFees(
        address _for,
        uint256[] memory _tokenIds
    ) external nonReentrant _onlyPoolHelper(pancakeV3Helper) {
        PancakeStakingLib.harvestV3PoolFees(_for, _tokenIds, masterChefV3, nonfungiblePositionManager);
    }

    function harvestV2LP(address[] memory _pool) external nonReentrant {
        _harvestLP(_pool, true);
    }

    function harvestAML(address[] memory _pool) external nonReentrant {
        _harvestLP(_pool, false);
    }

    function genericHarvest(address _pool) external nonReentrant {
        Pool memory poolInfo = pools[_pool];

        address[] memory poolsToHarvest = new address[](1);
        poolsToHarvest[0] = _pool;

        if (poolInfo.poolType == V3Type) revert InvalidPoolType();
        else if (poolInfo.poolType == V2Type || poolInfo.poolType == StableSwapType) _harvestLP(poolsToHarvest, true);
        else if (poolInfo.poolType == AMLType) _harvestLP(poolsToHarvest, false);
        else revert InvalidPoolType();
    }

    /* ============ Admin Functions ============ */

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function registerPool(
        address _poolAddress, // can be V3, V2 or AML Wrapper
        uint256 _allocPoints, // only for V2 and AML
        address _depositToken, // for V2, it's LP, for AML it's single side token, not applicable for V3
        uint256 _poolType,
        string memory _name,
        string memory _symbol,
        bool _isAmount0, // only applicable for AML
        bool _isNative
    ) external onlyOwner {
        if (pools[_poolAddress].isActive != false) revert PoolOccupied();

        if (_poolType != V3Type && _poolType != V2Type && _poolType != AMLType && _poolType != StableSwapType)
            revert InvalidPoolType();

        IERC20 newToken;
        address rewarder;

        if (_poolType != V3Type) {
            newToken = IERC20(
                ERC20FactoryLib.createReceipt(
                    _poolAddress,
                    address(masterCakepie),
                    address(this),
                    _name,
                    _symbol
                )
            );

            rewarder = masterCakepie.createRewarder(
                address(newToken),
                address(CAKE),
                address(rewardDistributor)
            );
        }

        // for v3 pool, we just registered the token address
        IMasterCakepie(masterCakepie).add(
            _poolType == V3Type ? 0 : _allocPoints,
            address(_poolAddress),
            address(newToken),
            address(rewarder),
            _poolType == V3Type ? true : false
        );

        pools[_poolAddress] = Pool({
            poolAddress: _poolAddress,
            depositToken: _poolType == V3Type ? address(0) : _depositToken,
            rewarder: address(rewarder),
            receiptToken: address(newToken),
            lastHarvestTime: block.timestamp,
            v3Liquidity: 0,
            poolType: _poolType,
            isAmount0: _isAmount0,
            isNative: _isNative,
            isActive: true
        });

        poolList.push(_poolAddress);
        poolLength += 1;

        emit PoolAdded(_poolAddress, address(rewarder), address(newToken));
    }

    function setPool(
        address _poolAddress, // can be V3, V2 or AML Wrapper
        uint256 _allocPoints, // only for V2 and AML
        address _depositToken, // for V2, it's LP, for AML it's single side token, not applicable for V3
        uint256 _poolType,
        bool _isAmount0, // only applicable for AML
        bool _isNative,
        address _rewarder
    ) external onlyOwner {
        Pool storage pool = pools[_poolAddress];

        pool.depositToken = _depositToken;
        pool.poolType = _poolType;
        pool.isAmount0 = _isAmount0;
        pool.isNative = _isNative;
        pool.rewarder = _rewarder;

        IMasterCakepie(masterCakepie).set(
            _poolAddress,
            _allocPoints,
            _rewarder
        );
    }

    function setHarvestTimeGap(uint256 _period) external onlyOwner {
        if (_period > 4 hours) revert TimeGapTooMuch();

        harvestTimeGap = _period;
    }

    function config(
        address _masterChefV3,
        address _masterCakepie,
        address _nonfungiblePositionManager,
        address _rewardDistributor,
        address _pancakeV3Helper,
        address _pancakeV2LPHelper,
        address _pancakeAMLHelper
    ) external onlyOwner {
        masterChefV3 = IMasterChefV3(_masterChefV3);
        masterCakepie = IMasterCakepie(_masterCakepie);
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        rewardDistributor = IRewardDistributor(_rewardDistributor);
        pancakeV3Helper = _pancakeV3Helper;
        pancakeV2LPHelper = _pancakeV2LPHelper;
        pancakeAMLHelper = _pancakeAMLHelper;

        V3Type = 1;
        V2Type = 2;
        AMLType = 3;
        StableSwapType = 0;
    }

    function setVoteManager(address _newVoteManager) external onlyOwner {
        address oldVoteManager = voteManager;
        voteManager = _newVoteManager;

        emit VoteManagerSet(oldVoteManager, _newVoteManager);
    }

    function setAllowedOperator(address _operator, bool _active) external onlyOwner {
        allowedOperator[_operator] = _active;
        emit AllowedOperatorSet(_operator, _active);
    }

    /* ============ Internal Functions ============ */

    // this function is shared by V2,StableSwap and AML pools
    function _harvestLP(address[] memory poolAddresses, bool _isV2) internal {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            Pool storage poolInfo = pools[poolAddresses[i]];
            if (!poolInfo.isActive) continue;

            if (poolInfo.lastHarvestTime + harvestTimeGap > block.timestamp) return;

            poolInfo.lastHarvestTime = block.timestamp;

            uint256 balBefore = IERC20(CAKE).balanceOf(address(this));

            if (_isV2) IV2Wrapper(poolInfo.poolAddress).deposit(0, false);
            else IALMWrapper(poolInfo.poolAddress).deposit(0, false);

            PancakeStakingLib.handleRewards(rewardDistributor, poolInfo.poolAddress, address(CAKE), balBefore, poolInfo.rewarder, true);
        }
    }

    function _depositTokens(
        address _for,
        Pool memory _poolInfo,
        uint256 _amount0,
        uint256 _amount1
    ) internal {

        address adapterAddress = IALMWrapper(_poolInfo.poolAddress).adapterAddr();

        if (_amount0 > 0) {
            address token0 = IAdapter(adapterAddress).token0();
            IERC20(token0).safeTransferFrom(_for, address(this), _amount0);
            IERC20(token0).safeIncreaseAllowance(_poolInfo.poolAddress, _amount0);
        }

        if (_amount1 > 0) {
            address token1 = IAdapter(adapterAddress).token1();
            IERC20(token1).safeTransferFrom(_for, address(this), _amount1);
            IERC20(token1).safeIncreaseAllowance(_poolInfo.poolAddress, _amount1);
        }

        if (_poolInfo.lastHarvestTime + harvestTimeGap > block.timestamp){
            IALMWrapper(_poolInfo.poolAddress).mintThenDeposit(_amount0, _amount1, true, "");
        }
        else {
            IALMWrapper(_poolInfo.poolAddress).mintThenDeposit(_amount0, _amount1, false, "");
            _poolInfo.lastHarvestTime = block.timestamp;
        }
    }
}