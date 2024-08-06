// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./BaseRewardPoolV3.sol";
import "../../interfaces/cakepie/IBaseRewardPool.sol";
import "../../libraries/cakepie/ERC20FactoryLib.sol";
import "../../interfaces/common/IMintableERC20.sol";
import "../../interfaces/cakepie/IVLCakepie.sol";
import "../../interfaces/cakepie/IVLCakepieBaseRewarder.sol";
import { IPancakeV3Helper } from "../../interfaces/cakepie/IPancakeV3Helper.sol";

/// @title A contract for managing all reward pools
/// @author Magpie Team
/// @notice Mater Cakepie emit `CKP` reward token based on Time. For a pool,

contract MasterCakepie is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many staking tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 available; // in case of locking
        uint256 unClaimedCakepie;
        //
        // We do some fancy math here. Basically, any point in time, the amount of Cakepies
        // entitled to a user but is pending to be distributed is:
        //
        // pending reward = (user.amount * pool.accCakepiePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws staking tokens to a pool. Here's what happens:
        //   1. The pool's `accCakepiePerShare` (and `lastRewardTimestamp`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        address stakingToken; // Address of staking token contract to be staked.
        address receiptToken; // Address of receipt token contract represent a staking position
        uint256 allocPoint; // How many allocation points assigned to this pool. Cakepies to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that Cakepies distribution occurs.
        uint256 accCakepiePerShare; // Accumulated Cakepies per share, times 1e12. See below.
        uint256 totalStaked;
        address rewarder; // address zero for cakepie pancake V3 Lp
        bool isActive; // if the pool is active
    }

    /* ============ State Variables ============ */

    // The Cakepie TOKEN!
    IERC20 public cakepie;
    IVLCakepie public vlCakepie;
    IPancakeV3Helper public pancakeV3Helper;

    // cakepie tokens created per second.
    uint256 public cakepiePerSec;

    // Registered staking tokens
    address[] public registeredToken;
    // Info of each pool.
    mapping(address => PoolInfo) public tokenToPoolInfo;
    // mapping of staking -> receipt Token
    mapping(address => address) public receiptToStakeToken;
    // Info of each user that stakes staking tokens [_staking][_account]
    mapping(address => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when Cakepie mining starts.
    uint256 public startTimestamp;

    mapping(address => bool) public PoolManagers;
    mapping(address => bool) public AllocationManagers;

    address public mCakeSV;

    /* ======== mapping added for legacy rewarders ======= */
    mapping(address => address) public legacyRewarders;

    /* ============ Events ============ */

    event Add(
        uint256 _allocPoint,
        address indexed _stakingToken,
        address indexed _receiptToken,
        IBaseRewardPool indexed _rewarder
    );
    event Set(
        address indexed _stakingToken,
        uint256 _allocPoint,
        IBaseRewardPool indexed _rewarder
    );
    event Deposit(
        address indexed _user,
        address indexed _stakingToken,
        address indexed _receiptToken,
        uint256 _amount
    );
    event Withdraw(
        address indexed _user,
        address indexed _stakingToken,
        address indexed _receiptToken,
        uint256 _amount
    );
    event UpdatePool(
        address indexed _stakingToken,
        uint256 _lastRewardTimestamp,
        uint256 _lpSupply,
        uint256 _accCakepiePerShare
    );
    event HarvestCakepie(
        address indexed _account,
        address indexed _receiver,
        uint256 _amount,
        bool isLock
    );
    event UpdateEmissionRate(
        address indexed _user,
        uint256 _oldCakepiePerSec,
        uint256 _newCakepiePerSec
    );
    event UpdatePoolAlloc(address _stakingToken, uint256 _oldAllocPoint, uint256 _newAllocPoint);
    event PoolManagerStatus(address _account, bool _status);
    event VlCakepieUpdated(address _newvlCakepie, address _oldvlCakepie);
    event DepositNotAvailable(
        address indexed _user,
        address indexed _stakingToken,
        uint256 _amount
    );
    event CakepieSet(address _cakepie);
    event mCakeSVUpdated(address _newMCakeSV, address _oldMCakeSV);
    event LegacyRewarderSet(address _stakingToken, address _legacyRewarder);
    event PancakeV3HelperSet(address _pancakeV3Helper);

    /* ============ Errors ============ */

    error OnlyPoolManager();
    error OnlyReceiptToken();
    error OnlyStakingToken();
    error OnlyActivePool();
    error PoolExisted();
    error InvalidStakingToken();
    error WithdrawAmountExceedsStaked();
    error UnlockAmountExceedsLocked();
    error MustBeContractOrZero();
    error OnlyVlCakepie();
    error CakepieSetAlready();
    error MustBeContract();
    error LengthMismatch();
    error OnlyWhiteListedAllocaUpdator();
    error OnlyMCakeSV();
    error InvalidToken();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __MasterCakepie_init(
        address _cakepieOFT,
        uint256 _cakepiePerSec,
        uint256 _startTimestamp
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        cakepie = IERC20(_cakepieOFT);
        cakepiePerSec = _cakepiePerSec;
        startTimestamp = _startTimestamp;
        totalAllocPoint = 0;
        PoolManagers[owner()] = true;
    }

    /* ============ Modifiers ============ */

    modifier _onlyPoolManager() {
        if (!PoolManagers[msg.sender] && msg.sender != address(this)) revert OnlyPoolManager();
        _;
    }

    modifier _onlyWhiteListed() {
        if (AllocationManagers[msg.sender] || PoolManagers[msg.sender] || msg.sender == owner()) {
            _;
        } else {
            revert OnlyWhiteListedAllocaUpdator();
        }
    }

    modifier _onlyReceiptToken() {
        address stakingToken = receiptToStakeToken[msg.sender];
        if (msg.sender != address(tokenToPoolInfo[stakingToken].receiptToken))
            revert OnlyReceiptToken();
        _;
    }

    modifier _onlyVlCakepie() {
        if (msg.sender != address(vlCakepie)) revert OnlyVlCakepie();
        _;
    }

    modifier _onlyMCakeSV() {
        if (msg.sender != address(mCakeSV)) revert OnlyMCakeSV();
        _;
    }

    /* ============ External Getters ============ */

    /// @notice Returns number of registered tokens, tokens having a registered pool.
    /// @return Returns number of registered tokens
    function poolLength() external view returns (uint256) {
        return registeredToken.length;
    }

    /// @notice Gives information about a Pool. Used for APR calculation and Front-End
    /// @param _stakingToken Staking token of the pool we want to get information from
    /// @return emission - Emissions of Cakepie from the contract, allocpoint - Allocated emissions of Cakepie to the pool,sizeOfPool - size of Pool, totalPoint total allocation points

    function getPoolInfo(
        address _stakingToken
    )
        external
        view
        returns (uint256 emission, uint256 allocpoint, uint256 sizeOfPool, uint256 totalPoint)
    {
        PoolInfo memory pool = tokenToPoolInfo[_stakingToken];
        return (
            (totalAllocPoint == 0 ? 0 : (cakepiePerSec * pool.allocPoint) / totalAllocPoint),
            pool.allocPoint,
            pool.totalStaked,
            totalAllocPoint
        );
    }

    /**
     * @dev Get staking information for a user.
     * @param _stakingToken The address of the staking token.
     * @param _user The address of the user.
     * @return stakedAmount The amount of tokens staked by the user.
     * @return availableAmount The available amount of tokens for the user to withdraw.
     */
    function stakingInfo(
        address _stakingToken,
        address _user
    ) public view returns (uint256 stakedAmount, uint256 availableAmount) {
        return (userInfo[_stakingToken][_user].amount, userInfo[_stakingToken][_user].available);
    }

    /// @notice View function to see pending reward tokens on frontend.
    /// @param _stakingToken Staking token of the pool
    /// @param _user Address of the user
    /// @param _rewardToken Specific pending reward token, apart from Cakepie
    /// @return pendingCakepie - Expected amount of Cakepie the user can claim, bonusTokenAddress - token, bonusTokenSymbol - token Symbol,  pendingBonusToken - Expected amount of token the user can claim
    function pendingTokens(
        address _stakingToken,
        address _user,
        address _rewardToken
    )
        external
        view
        returns (
            uint256 pendingCakepie,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        pendingCakepie = _calCakepieReward(_stakingToken, _user);

        (bonusTokenAddress, bonusTokenSymbol, pendingBonusToken) = _pendingTokensFrom(pool.rewarder, _user, _rewardToken);
    }


    function allPendingTokens(
        address _stakingToken,
        address _user
    )
        external
        view
        returns (
            uint256 pendingCakepie,
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        )
    {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        pendingCakepie = _calCakepieReward(_stakingToken, _user);

        (bonusTokenAddresses, bonusTokenSymbols, pendingBonusRewards) = _allPendingTokensFrom(pool.rewarder, _user);
    }
    
    function pendingLegacyTokens(
        address _stakingToken,
        address _user,
        address _rewardToken
    )
        external
        view
        returns (
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        address legacyRewarder = legacyRewarders[_stakingToken];
        if(legacyRewarder != address(0))
            (bonusTokenAddress, bonusTokenSymbol, pendingBonusToken) = _pendingTokensFrom(legacyRewarder, _user, _rewardToken);
    }

    function allPendingLegacyTokens(
        address _stakingToken,
        address _user
    )
        external
        view
        returns (
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        )
    {   
        address legacyRewarder = legacyRewarders[_stakingToken];
        if(legacyRewarder != address(0))
            (bonusTokenAddresses, bonusTokenSymbols, pendingBonusRewards) = _allPendingTokensFrom(legacyRewarder, _user);
        
    }

    /* ============ External Functions ============ */

    function depositMCakeSVFor(uint256 _amount, address _for) external whenNotPaused _onlyMCakeSV {
        _deposit(address(mCakeSV), msg.sender, _for, _amount, true);
    }

    function withdrawMCakeSVFor(uint256 _amount, address _for) external whenNotPaused _onlyMCakeSV {
        _withdraw(address(mCakeSV), _for, _amount, true);
    }

    /// @notice Deposits staking token to the pool, updates pool and distributes rewards
    /// @param _stakingToken Staking token of the pool
    /// @param _amount Amount to deposit to the pool
    function deposit(address _stakingToken, uint256 _amount) external whenNotPaused nonReentrant {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        IMintableERC20(pool.receiptToken).mint(msg.sender, _amount);

        IERC20(pool.stakingToken).safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _stakingToken, pool.receiptToken, _amount);
    }

    function depositFor(
        address _stakingToken,
        address _for,
        uint256 _amount
    ) external whenNotPaused nonReentrant {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        IMintableERC20(pool.receiptToken).mint(_for, _amount);

        IERC20(pool.stakingToken).safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(_for, _stakingToken, pool.receiptToken, _amount);
    }

    /// @notice Withdraw staking tokens from Master Cakepie.
    /// @param _stakingToken Staking token of the pool
    /// @param _amount amount to withdraw
    function withdraw(address _stakingToken, uint256 _amount) external whenNotPaused nonReentrant {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        IMintableERC20(pool.receiptToken).burn(msg.sender, _amount);

        IERC20(pool.stakingToken).safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _stakingToken, pool.receiptToken, _amount);
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _stakingToken Staking token of the pool
    function updatePool(address _stakingToken) public whenNotPaused {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        if (block.timestamp <= pool.lastRewardTimestamp || totalAllocPoint == 0) {
            return;
        }
        uint256 lpSupply = pool.totalStaked;
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
        uint256 cakepieReward = (multiplier * cakepiePerSec * pool.allocPoint) / totalAllocPoint;

        pool.accCakepiePerShare = pool.accCakepiePerShare + ((cakepieReward * 1e12) / lpSupply);
        pool.lastRewardTimestamp = block.timestamp;

        emit UpdatePool(_stakingToken, pool.lastRewardTimestamp, lpSupply, pool.accCakepiePerShare);
    }

    /// @notice Update reward variables for all pools. Be mindful of gas costs!
    function massUpdatePools() public whenNotPaused {
        for (uint256 pid = 0; pid < registeredToken.length; ++pid) {
            updatePool(registeredToken[pid]);
        }
    }

    /// @notice Claims for each of the pools with specified rewards to claim for each pool
    function multiclaimSpecCkp(
        address[] calldata _stakingTokens,
        address[][] memory _rewardTokens,
        uint256[] memory _tokenIds,
        bool _withckp
    ) external whenNotPaused {
        _multiClaim(_stakingTokens, msg.sender, msg.sender, _rewardTokens, _tokenIds, _withckp);
    }

    /// @notice Claims for each of the pools with specified rewards to claim for each pool
    function multiclaimFor(
        address[] calldata _stakingTokens,
        address[][] memory _rewardTokens,
        address _account
    ) external whenNotPaused {
        uint256[] memory noTokenid = new uint256[](0);
        _multiClaim(_stakingTokens, _account, _account, _rewardTokens, noTokenid, true);
    }

    /* ============ cakepie receipToken interaction Functions ============ */

    function beforeReceiptTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external _onlyReceiptToken {
        address _stakingToken = receiptToStakeToken[msg.sender];
        updatePool(_stakingToken);

        if (_from != address(0)) _harvestRewards(_stakingToken, _from);

        if (_from != _to) _harvestRewards(_stakingToken, _to);
    }

    function afterReceiptTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external _onlyReceiptToken {
        address _stakingToken = receiptToStakeToken[msg.sender];
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];

        if (_from != address(0)) {
            UserInfo storage from = userInfo[_stakingToken][_from];
            from.amount = from.amount - _amount;
            from.available = from.available - _amount;
            from.rewardDebt = (from.amount * pool.accCakepiePerShare) / 1e12;
        } else {
            // mint
            tokenToPoolInfo[_stakingToken].totalStaked += _amount;
        }

        if (_to != address(0)) {
            UserInfo storage to = userInfo[_stakingToken][_to];
            to.amount = to.amount + _amount;
            to.available = to.available + _amount;
            to.rewardDebt = (to.amount * pool.accCakepiePerShare) / 1e12;
        } else {
            // burn
            tokenToPoolInfo[_stakingToken].totalStaked -= _amount;
        }
    }

    /* ============ vlCakepie interaction Functions ============ */

    function depositVlCakepieFor(
        uint256 _amount,
        address _for
    ) external whenNotPaused nonReentrant _onlyVlCakepie {
        _deposit(address(vlCakepie), msg.sender, _for, _amount, true);
    }

    function withdrawVlCakepieFor(
        uint256 _amount,
        address _for
    ) external whenNotPaused nonReentrant _onlyVlCakepie {
        _withdraw(address(vlCakepie), _for, _amount, true);
    }

    /* ============ Internal Functions ============ */

    /// @notice internal function to deal with deposit staking token
    function _deposit(
        address _stakingToken,
        address _from,
        address _for,
        uint256 _amount,
        bool _isLock
    ) internal {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        UserInfo storage user = userInfo[_stakingToken][_for];

        updatePool(_stakingToken);
        _harvestRewards(_stakingToken, _for);

        user.amount = user.amount + _amount;
        if (!_isLock) {
            user.available = user.available + _amount;
            IERC20(pool.stakingToken).safeTransferFrom(address(_from), address(this), _amount);
        }
        user.rewardDebt = (user.amount * pool.accCakepiePerShare) / 1e12;

        if (_amount > 0) {
            pool.totalStaked += _amount;
            if (!_isLock) emit Deposit(_for, _stakingToken, pool.receiptToken, _amount);
            else emit DepositNotAvailable(_for, _stakingToken, _amount);
        }
    }

    /// @notice internal function to deal with withdraw staking token
    function _withdraw(
        address _stakingToken,
        address _account,
        uint256 _amount,
        bool _isLock
    ) internal {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        UserInfo storage user = userInfo[_stakingToken][_account];

        if (!_isLock && user.available < _amount) revert WithdrawAmountExceedsStaked();
        else if (user.amount < _amount && _isLock) revert UnlockAmountExceedsLocked();

        updatePool(_stakingToken);
        _harvestCakepie(_stakingToken, _account);
        _harvestBaseRewarder(_stakingToken, _account);

        user.amount = user.amount - _amount;
        if (!_isLock) {
            user.available = user.available - _amount;
            IERC20(tokenToPoolInfo[_stakingToken].stakingToken).safeTransfer(
                address(msg.sender),
                _amount
            );
        }
        user.rewardDebt = (user.amount * pool.accCakepiePerShare) / 1e12;

        pool.totalStaked -= _amount;

        emit Withdraw(_account, _stakingToken, pool.receiptToken, _amount);
    }

    function _multiClaim(
        address[] calldata _stakingTokens,
        address _user,
        address _receiver,
        address[][] memory _rewardTokens,
        uint256[] memory _tokenIds,
        bool _withckp
    ) internal nonReentrant {
        uint256 length = _stakingTokens.length;
        if (length != _rewardTokens.length) revert LengthMismatch();

        uint256 vlCakepiePoolAmount;
        uint256 defaultPoolAmount;

        for (uint256 i = 0; i < length; ++i) {
            address _stakingToken = _stakingTokens[i];
            UserInfo storage user = userInfo[_stakingToken][_user];

            updatePool(_stakingToken);
            uint256 claimableCakepie = _calNewCakepie(_stakingToken, _user) + user.unClaimedCakepie;

            // if claim with ckp, then unclaimed is 0
            if (_withckp) {
                if (_stakingToken == address(vlCakepie)) {
                    vlCakepiePoolAmount += claimableCakepie;
                } else {
                    defaultPoolAmount += claimableCakepie;
                }
                user.unClaimedCakepie = 0;
            } else {
                user.unClaimedCakepie = claimableCakepie;
            }

            user.rewardDebt =
                (user.amount * tokenToPoolInfo[_stakingToken].accCakepiePerShare) /
                1e12;
            _claimBaseRewarder(_stakingToken, _user, _receiver, _rewardTokens[i]);
        }

        if (_tokenIds.length > 0) pancakeV3Helper.harvestRewardAndFeeFor(_receiver, _tokenIds);

        // if not claiming ckp, early return
        if (!_withckp) return;

        _sendCakepieForVlCakepiePool(_user, _receiver, vlCakepiePoolAmount);

        _sendCakepie(_user, _receiver, defaultPoolAmount);
    }

    /// @notice calculate Cakepie reward based at current timestamp, for frontend only
    function _calCakepieReward(
        address _stakingToken,
        address _user
    ) internal view returns (uint256 pendingCakepie) {
        PoolInfo storage pool = tokenToPoolInfo[_stakingToken];
        UserInfo storage user = userInfo[_stakingToken][_user];
        uint256 accCakepiePerShare = pool.accCakepiePerShare;

        if (block.timestamp > pool.lastRewardTimestamp && pool.totalStaked != 0 && totalAllocPoint != 0) {
            uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
            uint256 cakepieReward = (multiplier * cakepiePerSec * pool.allocPoint) /
                totalAllocPoint;
            accCakepiePerShare = accCakepiePerShare + (cakepieReward * 1e12) / pool.totalStaked;
        }

        pendingCakepie = (user.amount * accCakepiePerShare) / 1e12 - user.rewardDebt;
        pendingCakepie += user.unClaimedCakepie;
    }

    function _harvestRewards(address _stakingToken, address _account) internal {
        if (userInfo[_stakingToken][_account].amount > 0) {
            _harvestCakepie(_stakingToken, _account);
        }
        _harvestBaseRewarder(_stakingToken, _account);
    }

    /// @notice Harvest Cakepie for an account
    /// only update the reward counting but not sending them to user
    function _harvestCakepie(address _stakingToken, address _account) internal {
        // Harvest Cakepie
        uint256 pending = _calNewCakepie(_stakingToken, _account);
        userInfo[_stakingToken][_account].unClaimedCakepie += pending;
    }

    /// @notice calculate Cakepie reward based on current accCakepiePerShare
    function _calNewCakepie(
        address _stakingToken,
        address _account
    ) internal view returns (uint256) {
        UserInfo storage user = userInfo[_stakingToken][_account];
        uint256 pending = (user.amount * tokenToPoolInfo[_stakingToken].accCakepiePerShare) /
            1e12 -
            user.rewardDebt;
        return pending;
    }

    /// @notice Harvest reward token in BaseRewarder for an account. NOTE: Baserewarder use user staking token balance as source to
    /// calculate reward token amount
    function _claimBaseRewarder(
        address _stakingToken,
        address _account,
        address _receiver,
        address[] memory _rewardTokens
    ) internal {
        IBaseRewardPool rewarder = IBaseRewardPool(tokenToPoolInfo[_stakingToken].rewarder);
        if (address(rewarder) != address(0)) {
            if (_rewardTokens.length > 0) {
                rewarder.getRewards(_account, _receiver, _rewardTokens);
                // if not specifiying any reward token, just claim them all
            } else {
                rewarder.getReward(_account, _receiver);
            }
        }

        IBaseRewardPool legacyRewarder = IBaseRewardPool(legacyRewarders[_stakingToken]);
        if (address(legacyRewarder) != address(0) ) {
            if (_rewardTokens.length > 0)
                legacyRewarder.getRewards(_account, _receiver, _rewardTokens);
            else legacyRewarder.getReward(_account, _receiver);
        }

    }

    /// only update the reward counting on in base rewarder but not sending them to user
    function _harvestBaseRewarder(address _stakingToken, address _account) internal {
        IBaseRewardPool rewarder = IBaseRewardPool(tokenToPoolInfo[_stakingToken].rewarder);
        if (address(rewarder) != address(0)) rewarder.updateFor(_account);

        IBaseRewardPool legacyRewarder = IBaseRewardPool(legacyRewarders[_stakingToken]);
        if (address(legacyRewarder) != address(0))
            legacyRewarder.updateFor(_account);

    }

    function _sendCakepieForVlCakepiePool(
        address _account,
        address _receiver,
        uint256 _amount
    ) internal {
        if (_amount == 0) return;

        address vlCakepieRewarder = tokenToPoolInfo[address(vlCakepie)].rewarder;
        cakepie.safeApprove(vlCakepieRewarder, _amount);
        IVLCakepieBaseRewarder(vlCakepieRewarder).queueCakepie(_amount, _account, _receiver);

        emit HarvestCakepie(_account, _receiver, _amount, false);
    }

    function _sendCakepie(address _account, address _receiver, uint256 _amount) internal {
        if (_amount == 0) return;

        cakepie.safeTransfer(_receiver, _amount);

        emit HarvestCakepie(_account, _receiver, _amount, false);
    }

    function _addPool(
        uint256 _allocPoint,
        address _stakingToken,
        address _receiptToken,
        address _rewarder,
        bool _isV3Pool
    ) internal {
        if (!_isV3Pool) {
            if (
                !Address.isContract(address(_stakingToken)) ||
                !Address.isContract(address(_receiptToken))
            ) revert InvalidStakingToken();

            if (!Address.isContract(address(_rewarder)) && address(_rewarder) != address(0))
                revert MustBeContractOrZero();
        }

        if (tokenToPoolInfo[_stakingToken].isActive) revert PoolExisted();

        massUpdatePools();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp
            ? block.timestamp
            : startTimestamp;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        registeredToken.push(_stakingToken);
        // it's receipt token as the registered token
        tokenToPoolInfo[_stakingToken] = PoolInfo({
            receiptToken: _receiptToken,
            stakingToken: _stakingToken,
            allocPoint: _allocPoint,
            lastRewardTimestamp: lastRewardTimestamp,
            accCakepiePerShare: 0,
            totalStaked: 0,
            rewarder: _rewarder,
            isActive: true
        });

        receiptToStakeToken[_receiptToken] = _stakingToken;

        emit Add(_allocPoint, _stakingToken, _receiptToken, IBaseRewardPool(_rewarder));
    }

    function _pendingTokensFrom(
        address rewarder,
        address _user,
        address _rewardToken
    )
        internal
        view
        returns (
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        // If it's a multiple reward farm, we return info about the specific bonus token
        if (address(rewarder) != address(0) && _rewardToken != address(0)) {
            (bonusTokenAddress, bonusTokenSymbol) = (
                _rewardToken,
                IERC20Metadata(_rewardToken).symbol()
            );
            pendingBonusToken = IBaseRewardPool(rewarder).earned(_user, _rewardToken);
        }
    }

    function _allPendingTokensFrom(
        address _rewarder,
        address _user
    )
        internal
        view
        returns (
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        )
    {
        // If it's a multiple reward farm, we return all info about the bonus tokens
        if (address(_rewarder) != address(0)) {
            (bonusTokenAddresses, bonusTokenSymbols) = IBaseRewardPool(_rewarder)
                .rewardTokenInfos();
            pendingBonusRewards = IBaseRewardPool(_rewarder).allEarned(_user);
        }
    }

    /* ============ Admin Functions ============ */
    /// @notice Used to give edit rights to the pools in this contract to a Pool Manager
    /// @param _account Pool Manager Adress
    /// @param _allowedManager True gives rights, False revokes them
    function setPoolManagerStatus(address _account, bool _allowedManager) external onlyOwner {
        PoolManagers[_account] = _allowedManager;

        emit PoolManagerStatus(_account, PoolManagers[_account]);
    }

    function setCakepie(address _cakepie) external onlyOwner {
        if (address(cakepie) != address(0)) revert CakepieSetAlready();

        if (!Address.isContract(_cakepie)) revert MustBeContract();

        cakepie = IERC20(_cakepie);
        emit CakepieSet(_cakepie);
    }

    function setVlCakepie(address _vlCakepie) external onlyOwner {
        address oldvlCakepie = address(vlCakepie);
        vlCakepie = IVLCakepie(_vlCakepie);
        emit VlCakepieUpdated(address(vlCakepie), oldvlCakepie);
    }

    function setMCakeSV(address _mCakeSV) external onlyOwner {
        address oldMCakeSV = mCakeSV;
        mCakeSV = _mCakeSV;
        emit mCakeSVUpdated(_mCakeSV, oldMCakeSV);
    }

    /**
     * @dev pause pool, restricting certain operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, enabling certain operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Add a new rewarder to the pool. Can only be called by a PoolManager.
    /// @param _receiptToken receipt token of the pool
    /// @param mainRewardToken Token that will be rewarded for staking in the pool
    /// @return address of the rewarder created
    function createRewarder(
        address _receiptToken,
        address mainRewardToken,
        address rewardDistributor
    ) external _onlyPoolManager returns (address) {
        address rewarder = ERC20FactoryLib.createRewarder(
            _receiptToken,
            mainRewardToken,
            address(this),
            rewardDistributor
        );

        return rewarder;
    }

    /// @notice Add a new penlde marekt pool. Explicitly for Pendle Market pools and should be called from Pendle Staking.
    function add(
        uint256 _allocPoint,
        address _stakingToken,
        address _receiptToken,
        address _rewarder,
        bool _isV3Pool
    ) external _onlyPoolManager {
        _addPool(_allocPoint, _stakingToken, _receiptToken, _rewarder, _isV3Pool);
    }

    /// @notice Add a new pool that does not mint receipt token. Mainly for locker pool such as vlckp, mCakeSV
    function createNoReceiptPool(
        uint256 _allocPoint,
        address _stakingToken,
        address _rewarder
    ) external onlyOwner {
        _addPool(_allocPoint, _stakingToken, _stakingToken, _rewarder, false);
    }

    function createPool(
        uint256 _allocPoint,
        address _stakingToken,
        string memory _receiptName,
        string memory _receiptSymbol
    ) external onlyOwner {
        IERC20 newToken = IERC20(
            ERC20FactoryLib.createReceipt(
                address(_stakingToken),
                address(this),
                address(0),
                _receiptName,
                _receiptSymbol
            )
        );

        address rewarder = this.createRewarder(address(newToken), address(0), address(this));

        _addPool(_allocPoint, _stakingToken, address(newToken), rewarder, false);
    }

    /// @notice Updates the given pool's Cakepie allocation point, rewarder address and locker address if overwritten. Can only be called by a Pool Manager.
    /// @param _stakingToken Staking token of the pool
    /// @param _allocPoint Allocation points of Cakepie to the pool
    /// @param _rewarder Address of the rewarder for the pool
    function set(
        address _stakingToken,
        uint256 _allocPoint,
        address _rewarder
    ) external _onlyPoolManager {
        if (!Address.isContract(address(_rewarder)) && address(_rewarder) != address(0))
            revert MustBeContractOrZero();

        if (!tokenToPoolInfo[_stakingToken].isActive) revert OnlyActivePool();

        massUpdatePools();

        totalAllocPoint = totalAllocPoint - tokenToPoolInfo[_stakingToken].allocPoint + _allocPoint;

        tokenToPoolInfo[_stakingToken].allocPoint = _allocPoint;
        tokenToPoolInfo[_stakingToken].rewarder = _rewarder;

        emit Set(
            _stakingToken,
            _allocPoint,
            IBaseRewardPool(tokenToPoolInfo[_stakingToken].rewarder)
        );
    }

    /// @notice Update the emission rate of Cakepie for MasterMagpie
    /// @param _cakepiePerSec new emission per second
    function updateEmissionRate(uint256 _cakepiePerSec) public onlyOwner {
        massUpdatePools();
        uint256 oldEmissionRate = cakepiePerSec;
        cakepiePerSec = _cakepiePerSec;

        emit UpdateEmissionRate(msg.sender, oldEmissionRate, cakepiePerSec);
    }

    function updatePoolsAlloc(
        address[] calldata _stakingTokens,
        uint256[] calldata _allocPoints
    ) external _onlyWhiteListed {
        massUpdatePools();

        if (_stakingTokens.length != _allocPoints.length) revert LengthMismatch();

        for (uint256 i = 0; i < _stakingTokens.length; i++) {
            uint256 oldAllocPoint = tokenToPoolInfo[_stakingTokens[i]].allocPoint;

            totalAllocPoint = totalAllocPoint - oldAllocPoint + _allocPoints[i];

            tokenToPoolInfo[_stakingTokens[i]].allocPoint = _allocPoints[i];

            emit UpdatePoolAlloc(_stakingTokens[i], oldAllocPoint, _allocPoints[i]);
        }
    }

    function updateWhitelistedAllocManager(address _account, bool _allowed) external onlyOwner {
        AllocationManagers[_account] = _allowed;
    }

    function updateRewarderQueuer(
        address _rewarder,
        address _manager,
        bool _allowed
    ) external onlyOwner {
        IBaseRewardPool rewarder = IBaseRewardPool(_rewarder);
        rewarder.updateRewardQueuer(_manager, _allowed);
    }

    function setPancakeV3Helper(address _pancakeV3Helper) external onlyOwner {
        pancakeV3Helper = IPancakeV3Helper(_pancakeV3Helper);

        emit PancakeV3HelperSet(_pancakeV3Helper);
    }

    function setLegacyRewarder(address _stakingToken, address _legacyRewarder) external onlyOwner {
        legacyRewarders[_stakingToken] = _legacyRewarder;

        emit LegacyRewarderSet(_stakingToken, _legacyRewarder);
    }
}
