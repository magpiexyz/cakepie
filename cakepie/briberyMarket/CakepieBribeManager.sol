// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../../interfaces/cakepie/IPancakeVoteManager.sol";
import "../../libraries/math/Math.sol";

/// @title CakepieBribeManager
/// @notice The CakepieBribeManager contract, is designed for managing PancakeSwap pool tokens
///         in voting and bribing systems.It allows the addition and removal of pools, handling
///         bribes by splitting tokens between a distributor contract and a fee collector.
///         To optimize for gas efficiency, the contract uniquely indexes bribe tokens in each pool
///         by targetTime, avoiding complex mappings. After each targetTime, it aggregates total bribes and
///         voting results using subgraph querying, calculates user rewards, and enables reward
///         claiming through a distributor contract. The contract incorporates features like native
///         and ERC20 token support for bribes, and admin functions for pool and token management.
///
/// @author Cakepie Team

contract CakepieBribeManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    struct Pool {
        bytes32 gaugeHash;
        address pool;
        uint256 gaugeType;
        uint256 chainId;
        bool isActive;
    }

    struct Bribe {
        address token;
        uint256 amount;
    }

    struct BribesInPool {
        address pool;
        Bribe[] bribe;
    }

    struct PoolVotes {
        address bribe;
        uint256 votes;
    }

    /* ============ Constants for PCS integration ============ */

    /// @dev 7 * 86400 seconds - all future times are rounded by week
    uint256 constant WEEK = 604800;
    /// @dev Add 2 weeks time to calculate actual 2 weeks targetTime
    uint256 constant TWOWEEK = WEEK * 2;

    /* ============ State Variables ============ */

    address constant NATIVE = address(1);
    uint256 constant DENOMINATOR = 10000;

    address public voteManager;
    address payable public distributor;
    address payable private feeCollector;
    uint256 public feeRatio;
    uint256 public maxBribingBatch;

    address[] public pools;
    mapping(address => Pool) public poolInfo;
    mapping(address => uint256) public unCollectedFee;

    address[] public allowedTokens;
    mapping(address => bool) public allowedToken;
    mapping(bytes32 => Bribe) public bribes; // The index is hashed based on the targetTime, pool and token address
    mapping(bytes32 => bytes32[]) public bribesInPool; // Mapping pool => bribes. The index is hashed based on the targetTime, pool
    mapping(address => bool) public allowedOperator;

    address payable public distributorForVeCake;
    uint256 public ckpBribingRatio;
    mapping(bytes32 => Bribe) public bribesForVeCake;
    mapping(bytes32 => bytes32[]) public bribesInPoolForVeCake;

    /* ============ Events ============ */

    event NewBribe(
        address indexed _user,
        uint256 indexed _targetTime,
        address _pool,
        address _bribeToken,
        uint256 _amount
    );
    event NewBribeForVeCake(
        address indexed _user,
        uint256 indexed _targetTime,
        address _pool,
        address _bribeToken,
        uint256 _amount
    );
    event NewPool(address indexed _pool, uint256 _chainId);
    event PoolUpdated(
        address indexed _pool,
        uint256 _oldGaugeType,
        uint256 _newGaugeType,
        uint256 _oldChainId,
        uint256 _newChainId,
        bool _oldIsActive,
        bool _newIsActive
    );
    event UpdateOperatorStatus(address indexed _user, bool _status);
    event NewPoolBatch(address[] _pools, uint256[] _chainIds);
    event BribeReallocated(
        address indexed _pool,
        address indexed _token,
        uint256 _targetTimeFrom,
        uint256 _targetTimeTo,
        uint256 _amount
    );
    event NewAllowedToken(address indexed _token);
    event RemovedAllowedToken(address indexed _token);

    /* ============ Errors ============ */

    error InvalidPool();
    error InvalidBribeToken();
    error ZeroAddress();
    error ZeroAmount();
    error PoolOccupied();
    error InvalidTargetTime();
    error OnlyNotInTargetTime();
    error OnlyInTargetTime();
    error InvalidTime();
    error InvalidBatch();
    error LengthMismatch();
    error OnlyOperator();
    error MarketExists();
    error ExceedDenomintor();
    error NativeTransferFailed();
    error InsufficientAmount();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __CakepieBribeManager_init(
        address _voteManager,
        uint256 _feeRatio,
        uint256 _ckpBribingRatio,
        uint256 _maxBribingBatch
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        voteManager = _voteManager;
        feeRatio = _feeRatio;
        ckpBribingRatio = _ckpBribingRatio;
        maxBribingBatch = _maxBribingBatch;
        allowedOperator[owner()] = true;
    }

    /* ============ Modifiers ============ */

    modifier onlyOperator() {
        if (!allowedOperator[msg.sender]) revert OnlyOperator();
        _;
    }

    /* ============ External Getters ============ */

    function getCurrentPeriodEndTime() public view returns (uint256 endTime) {
        endTime = _getNextTime(); // align with PancakeSwapEndTime
    }

    function getApprovedTokens() public view returns (address[] memory) {
        return allowedTokens;
    }

    function getPoolLength() public view returns (uint256) {
        return pools.length;
    }

    function getAllPools() public view returns (address[] memory) {
        return pools;
    }

    /// @notice this function could make havey gas cost, please prevent to call this in non-view functions
    function getBribesInPools(
        uint256 _targetTime,
        address[] calldata _pools
    ) external view returns (Bribe[][] memory) {
        Bribe[][] memory _bribesInPool = new Bribe[][](_pools.length);

        for (uint256 i = 0; i < _pools.length; i++) {
            _bribesInPool[i] = getBribesInPool(_targetTime, _pools[i]);
        }

        return _bribesInPool;
    }

    /// @notice this function could make heavy gas cost, please prevent to call this in non-view functions
    function getBribesInAllPools(uint256 _targetTime) external view returns (Bribe[][] memory) {
        Bribe[][] memory rewards = new Bribe[][](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            rewards[i] = getBribesInPool(_targetTime, pools[i]);
        }
        return rewards;
    }

    function getBribesInPool(
        uint256 _targetTime,
        address _pool
    ) public view returns (Bribe[] memory) {
        if (poolInfo[_pool].pool == address(0)) revert InvalidPool();

        bytes32 poolIdentifier = _getPoolIdentifier(_targetTime, _pool);

        bytes32[] memory poolBribes = bribesInPool[poolIdentifier];
        Bribe[] memory rewards = new Bribe[](poolBribes.length);

        for (uint256 i = 0; i < poolBribes.length; i++) {
            rewards[i] = bribes[poolBribes[i]];
        }

        return rewards;
    }

    function getBribesInAllPoolsForVeCake(uint256 _epoch) external view returns (Bribe[][] memory) {
        Bribe[][] memory rewards = new Bribe[][](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            rewards[i] = getBribesInPoolForVeCake(_epoch, pools[i]);
        }
        return rewards;
    }

    function getBribesInPoolForVeCake(
        uint256 _epoch,
        address _pool
    ) public view returns (Bribe[] memory) {
        if (poolInfo[_pool].pool == address(0)) revert InvalidPool();

        bytes32 poolIdentifier = _getPoolIdentifier(_epoch, _pool);

        bytes32[] memory poolBribes = bribesInPoolForVeCake[poolIdentifier];
        Bribe[] memory rewards = new Bribe[](poolBribes.length);

        for (uint256 i = 0; i < poolBribes.length; i++) {
            rewards[i] = bribesForVeCake[poolBribes[i]];
        }

        return rewards;
    }

    /* ============ External Functions ============ */

    function addBribeNative(
        uint256 _batch,
        address _pool,
        bool _forPreviousEpoch,
        bool _forVeCake
    ) external payable nonReentrant whenNotPaused {
        _addBribeNative(_batch, _pool, _forPreviousEpoch, _forVeCake);
    }

    function addBribeERC20(
        uint256 _batch,
        address _pool,
        address _token,
        uint256 _amount,
        bool _forPreviousEpoch,
        bool _forVeCake
    ) external nonReentrant whenNotPaused {
        _addBribeERC20(_batch, _pool, _token, _amount, _forPreviousEpoch, _forVeCake);
    }

    function addBribeNativeToTargetTime(
        uint256 _targetTime,
        address _pool,
        bool forVeCake
    ) external payable nonReentrant whenNotPaused onlyOperator {
        uint256 timeDifference;
        if (_targetTime >= getCurrentPeriodEndTime()) {
            timeDifference = _targetTime - getCurrentPeriodEndTime();
        } else {
            timeDifference = getCurrentPeriodEndTime() - _targetTime;
            // only can add bribes to the previous period
            if (timeDifference > TWOWEEK) revert InvalidTargetTime();
        }

        if (_targetTime < getCurrentPeriodEndTime() - TWOWEEK || timeDifference % TWOWEEK != 0)
            revert InvalidTargetTime();
        if (!poolInfo[_pool].isActive) revert InvalidPool();

        bool successNativeTransfer;
        uint256 bribeForVlCKP = msg.value;
        uint256 bribeForVeCake;
        uint256 totalFee = 0;

        if (forVeCake) {
            bribeForVlCKP = (msg.value * ckpBribingRatio) / DENOMINATOR;
            bribeForVeCake = msg.value - bribeForVlCKP;
            if (bribeForVeCake > 0) {
                (uint256 feeForVeCake, uint256 afterFeeForVeCake) = _addBribeForVeCake(
                    _targetTime,
                    _pool,
                    NATIVE,
                    bribeForVeCake
                );
                totalFee += feeForVeCake;
                (successNativeTransfer, ) = distributorForVeCake.call{ value: afterFeeForVeCake }(
                    ""
                );
                if (!successNativeTransfer) revert NativeTransferFailed();
            }
        }

        (uint256 fee, uint256 afterFee) = _addBribe(_targetTime, _pool, NATIVE, bribeForVlCKP);
        totalFee += fee;

        // transfer the token to the target directly in one time to save the gas fee
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[NATIVE] += totalFee;
            } else {
                feeCollector.transfer(totalFee);
            }
        }
        (successNativeTransfer, ) = distributor.call{ value: afterFee }("");
        if (!successNativeTransfer) revert NativeTransferFailed();
    }

    function addBribeERC20ToTargetTime(
        uint256 _targetTime,
        address _pool,
        address _token,
        uint256 _amount,
        bool forVeCake
    ) external nonReentrant whenNotPaused onlyOperator {
        uint256 timeDifference;
        if (_targetTime >= getCurrentPeriodEndTime()) {
            timeDifference = _targetTime - getCurrentPeriodEndTime();
        } else {
            timeDifference = getCurrentPeriodEndTime() - _targetTime;
            // only can add bribes to the previous period
            if (timeDifference > TWOWEEK) revert InvalidTargetTime();
        }

        if (_targetTime < getCurrentPeriodEndTime() - TWOWEEK || timeDifference % TWOWEEK != 0)
            revert InvalidTargetTime();
        if (!poolInfo[_pool].isActive) revert InvalidPool();
        if (!allowedToken[_token] && _token != NATIVE) revert InvalidBribeToken();

        uint256 bribeForVlCKP = _amount;
        uint256 bribeForVeCake;
        uint256 totalFee = 0;

        if (forVeCake) {
            bribeForVlCKP = (_amount * ckpBribingRatio) / DENOMINATOR;
            bribeForVeCake = _amount - bribeForVlCKP;
            if (bribeForVeCake > 0) {
                (uint256 feeForVeCake, uint256 afterFeeForVeCake) = _addBribeForVeCake(
                    _targetTime,
                    _pool,
                    _token,
                    bribeForVeCake
                );
                totalFee += feeForVeCake;
                IERC20(_token).safeTransferFrom(
                    msg.sender,
                    distributorForVeCake,
                    afterFeeForVeCake
                );
            }
        }

        (uint256 fee, uint256 afterFee) = _addBribe(_targetTime, _pool, _token, bribeForVlCKP);
        totalFee += fee;

        // transfer the token to the target directly in one time to save the gas fee
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[_token] += totalFee;
                IERC20(_token).safeTransferFrom(msg.sender, address(this), totalFee);
            } else {
                IERC20(_token).safeTransferFrom(msg.sender, feeCollector, totalFee);
            }
        }

        IERC20(_token).safeTransferFrom(msg.sender, distributor, afterFee);
    }

    /* ============ Internal Functions ============ */

    /// @dev this function can get the same end time as Pancake's gauge controller
    function _getNextTime() internal view returns (uint256 nextTime) {
        nextTime = ((block.timestamp + TWOWEEK) / TWOWEEK) * TWOWEEK;
    }

    function _getPoolIdentifier(
        uint256 _targetTime,
        address _pool
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_targetTime, _pool));
    }

    function _getTokenIdentifier(
        uint256 _targetTime,
        address _pool,
        address _token
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_targetTime, _pool, _token));
    }

    function _isValidPeriodEndTime(uint256 _targetTime) internal view returns (bool) {
        uint256 timeDifference = (_targetTime >= getCurrentPeriodEndTime())
            ? _targetTime - getCurrentPeriodEndTime()
            : getCurrentPeriodEndTime() - _targetTime;

        if (_targetTime < getCurrentPeriodEndTime() - TWOWEEK || timeDifference % TWOWEEK != 0)
            return false;
        else return true;
    }

    function _addBribeNative(
        uint256 _batch,
        address _pool,
        bool _forPreviousEpoch,
        bool forVeCake
    ) internal {
        if (_batch == 0 || _batch > maxBribingBatch) revert InvalidBatch();
        if (!poolInfo[_pool].isActive) revert InvalidPool();

        uint256 totalFee = 0;
        uint256 totalBribing = 0;
        uint256 totalBribingForVeCake = 0;

        uint256 bribePerBatch = msg.value / _batch;
        uint256 bribePerBatchForVlCKP = bribePerBatch;
        uint256 bribePerBatchForVeCake = 0;
        if (forVeCake) {
            bribePerBatchForVlCKP = (bribePerBatch * ckpBribingRatio) / DENOMINATOR;
            bribePerBatchForVeCake = bribePerBatch - bribePerBatchForVlCKP;
        }

        uint256 wTimeFrom = getCurrentPeriodEndTime();
        if (wTimeFrom > block.timestamp && wTimeFrom - block.timestamp < 122400)
            wTimeFrom += TWOWEEK;
        if (_forPreviousEpoch) wTimeFrom -= TWOWEEK;
        for (uint256 b = 0; b < _batch; b++) {
            uint256 wTime = wTimeFrom + TWOWEEK * b;
            if (forVeCake && bribePerBatchForVeCake > 0) {
                (uint256 feeForVeCake, uint256 afterFeeForVeCake) = _addBribeForVeCake(
                    wTime,
                    _pool,
                    NATIVE,
                    bribePerBatchForVeCake
                );
                totalFee += feeForVeCake;
                totalBribingForVeCake += afterFeeForVeCake;
            }
            (uint256 fee, uint256 afterFee) = _addBribe(
                wTime,
                _pool,
                NATIVE,
                bribePerBatchForVlCKP
            );
            totalFee += fee;
            totalBribing += afterFee;
        }

        // transfer the token to the target directly in one time to save the gas fee
        bool success;
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[NATIVE] += totalFee;
            } else {
                feeCollector.transfer(totalFee);
            }
        }
        (success, ) = distributor.call{ value: totalBribing }("");
        if (!success) revert NativeTransferFailed();

        if (forVeCake && totalBribingForVeCake > 0) {
            (success, ) = distributorForVeCake.call{ value: totalBribingForVeCake }("");
            if (!success) revert NativeTransferFailed();
        }
    }

    function _addBribeERC20(
        uint256 _batch,
        address _pool,
        address _token,
        uint256 _amount,
        bool _forPreviousEpoch,
        bool forVeCake
    ) internal {
        if (_batch == 0 || _batch > maxBribingBatch) revert InvalidBatch();
        if (!poolInfo[_pool].isActive) revert InvalidPool();
        if (!allowedToken[_token] && _token != NATIVE) revert InvalidBribeToken();

        uint256 totalFee = 0;
        uint256 totalBribing = 0;
        uint256 totalBribingForVeCake = 0;

        uint256 bribePerPeriodForVlCKP = (_amount / _batch);
        uint256 bribePerPeriodForVeCake = 0;
        if (forVeCake) {
            bribePerPeriodForVlCKP = ((_amount / _batch) * ckpBribingRatio) / DENOMINATOR;
            bribePerPeriodForVeCake = (_amount / _batch) - bribePerPeriodForVlCKP;
        }

        uint256 wTimeFrom = getCurrentPeriodEndTime();
        // wTimeFrom = 1710374400
        // block.timestamp = 1710330968
        // wTimeFrom - block.timestamp
        if (wTimeFrom > block.timestamp && wTimeFrom - block.timestamp < 122400)
            wTimeFrom += TWOWEEK;
        if (_forPreviousEpoch) wTimeFrom -= TWOWEEK;
        for (uint256 b = 0; b < _batch; b++) {
            if (forVeCake && bribePerPeriodForVeCake > 0) {
                (uint256 feeForVeCake, uint256 afterFeeForVeCake) = _addBribeForVeCake(
                    wTimeFrom + TWOWEEK * b,
                    _pool,
                    _token,
                    bribePerPeriodForVeCake
                );
                totalFee += feeForVeCake;
                totalBribingForVeCake += afterFeeForVeCake;
            }
            (uint256 fee, uint256 afterFee) = _addBribe(
                wTimeFrom + TWOWEEK * b,
                _pool,
                _token,
                bribePerPeriodForVlCKP
            );
            totalFee += fee;
            totalBribing += afterFee;
        }

        // transfer the token to the target directly in one time to save the gas fee
        if (totalFee > 0) {
            if (feeCollector == address(0)) {
                unCollectedFee[_token] += totalFee;
                IERC20(_token).safeTransferFrom(msg.sender, address(this), totalFee);
            } else {
                IERC20(_token).safeTransferFrom(msg.sender, feeCollector, totalFee);
            }
        }

        IERC20(_token).safeTransferFrom(msg.sender, distributor, totalBribing);

        if (forVeCake && totalBribingForVeCake > 0) {
            IERC20(_token).safeTransferFrom(
                msg.sender,
                distributorForVeCake,
                totalBribingForVeCake
            );
        }
    }

    function _addBribe(
        uint256 _targetTime,
        address _pool,
        address _token,
        uint256 _amount
    ) internal returns (uint256 fee, uint256 afterFee) {
        fee = (_amount * feeRatio) / DENOMINATOR;
        afterFee = _amount - fee;

        // We will generate a unique index for each pool and reward based on the targetTime
        bytes32 poolIdentifier = _getPoolIdentifier(_targetTime, _pool);
        bytes32 rewardIdentifier = _getTokenIdentifier(_targetTime, _pool, _token);

        Bribe storage bribe = bribes[rewardIdentifier];
        bribe.amount += afterFee;
        if (bribe.token == address(0)) {
            bribe.token = _token;
            bribesInPool[poolIdentifier].push(rewardIdentifier);
        }

        emit NewBribe(msg.sender, _targetTime, _pool, _token, afterFee);
    }

    function _addBribeForVeCake(
        uint256 _targetTime,
        address _pool,
        address _token,
        uint256 _amount
    ) internal returns (uint256 fee, uint256 afterFee) {
        fee = (_amount * feeRatio) / DENOMINATOR;
        afterFee = _amount - fee;

        // We will generate a unique index for each pool and reward based on the epoch
        bytes32 poolIdentifier = _getPoolIdentifier(_targetTime, _pool);
        bytes32 rewardIdentifier = _getTokenIdentifier(_targetTime, _pool, _token);

        Bribe storage bribe = bribesForVeCake[rewardIdentifier];
        bribe.amount += afterFee;
        if (bribe.token == address(0)) {
            bribe.token = _token;
            bribesInPoolForVeCake[poolIdentifier].push(rewardIdentifier);
        }

        emit NewBribeForVeCake(msg.sender, _targetTime, _pool, _token, afterFee);
    }

    /* ============ Admin Functions ============ */

    /// @notice this function will create a new pool in the bribeManager and voteManager
    function newPool(address _pool, uint256 _gaugeType, uint256 _chainId) external onlyOwner {
        if (_pool == address(0)) revert ZeroAddress();
        if (poolInfo[_pool].pool != address(0)) revert InvalidPool();

        poolInfo[_pool] = Pool(
            keccak256(abi.encodePacked(_pool, _chainId)),
            _pool,
            _gaugeType,
            _chainId,
            true
        );
        pools.push(_pool);

        if (voteManager != address(0))
            IPancakeVoteManager(voteManager).addPool(_pool, _gaugeType, _chainId);

        emit NewPool(_pool, _chainId);
    }

    function newPoolBatch(
        address[] calldata _pools,
        uint256[] calldata _gaugeTypes,
        uint256[] calldata _chainIds
    ) external onlyOwner {
        if (_pools.length != _gaugeTypes.length || _pools.length != _chainIds.length)
            revert LengthMismatch();

        for (uint256 i = 0; i < _pools.length; i++) {
            address _pool = _pools[i];
            uint256 _gaugeType = _gaugeTypes[i];
            uint256 _chainId = _chainIds[i];

            if (_pool == address(0)) revert ZeroAddress();
            if (poolInfo[_pool].pool != address(0)) revert InvalidPool();

            poolInfo[_pool] = Pool(
                keccak256(abi.encodePacked(_pool, _chainId)),
                _pool,
                _gaugeType,
                _chainId,
                true
            );
            pools.push(_pool);

            if (voteManager != address(0))
                IPancakeVoteManager(voteManager).addPool(_pool, _gaugeType, _chainId);

            emit NewPoolBatch(_pools, _chainIds);
        }
    }

    function deactivatePool(address _pool) external onlyOwner {
        if (!poolInfo[_pool].isActive) revert InvalidPool();
        poolInfo[_pool].isActive = false;

        if (voteManager != address(0)) IPancakeVoteManager(voteManager).deactivatePool(_pool);
    }

    function updatePool(
        address _pool,
        uint256 _gaugeType,
        uint256 _chainId,
        bool _active
    ) external onlyOwner {
        Pool storage pool = poolInfo[_pool];
        if (pool.pool == address(0)) revert InvalidPool();

        Pool memory oldPoolInfo = poolInfo[_pool];

        poolInfo[_pool] = Pool(
            keccak256(abi.encodePacked(_pool, _chainId)),
            _pool,
            _gaugeType,
            _chainId,
            _active
        );

        if (voteManager != address(0))
            IPancakeVoteManager(voteManager).updatePool(_pool, _gaugeType, _chainId, _active);

        emit PoolUpdated(
            _pool,
            oldPoolInfo.gaugeType,
            _gaugeType,
            oldPoolInfo.chainId,
            _chainId,
            oldPoolInfo.isActive,
            _active
        );
    }

    function addAllowedTokens(address _token) external onlyOwner {
        if (allowedToken[_token]) revert InvalidBribeToken();

        allowedTokens.push(_token);

        allowedToken[_token] = true;

        emit NewAllowedToken(_token);
    }

    function removeAllowedTokens(address _token) external onlyOwner {
        if (!allowedToken[_token]) revert InvalidBribeToken();
        uint256 allowedTokensLength = allowedTokens.length;
        uint256 i = 0;
        while (allowedTokens[i] != _token) {
            i++;
            if (i >= allowedTokensLength) revert InvalidBribeToken();
        }

        allowedTokens[i] = allowedTokens[allowedTokensLength - 1];
        allowedTokens.pop();

        allowedToken[_token] = false;

        emit RemovedAllowedToken(_token);
    }

    function updateAllowedOperator(address _user, bool _allowed) external onlyOwner {
        allowedOperator[_user] = _allowed;

        emit UpdateOperatorStatus(_user, _allowed);
    }

    function setDistributor(address payable _distributor) external onlyOwner {
        distributor = _distributor;
    }

    function setFeeCollector(address payable _collector) external onlyOwner {
        feeCollector = _collector;
    }

    function setFeeRatio(uint256 _feeRatio) external onlyOwner {
        if (_feeRatio > 10000) revert ExceedDenomintor();
        feeRatio = _feeRatio;
    }

    function setDistributorForVeCake(address payable _distributorForVeCake) external onlyOwner {
        distributorForVeCake = _distributorForVeCake;
    }

    function setCkpBribingRatio(uint256 _ckpBribingRatio) external onlyOwner {
        ckpBribingRatio = _ckpBribingRatio;
    }

    function manualClaimFees(address _token) external onlyOwner {
        if (feeCollector != address(0)) {
            unCollectedFee[_token] = 0;
            if (_token == NATIVE) {
                feeCollector.transfer(address(this).balance);
            } else {
                uint256 balance = IERC20(_token).balanceOf(address(this));
                IERC20(_token).safeTransfer(feeCollector, balance);
            }
        }
    }

    function reallocateBribe(
        uint256 _targetTimeFrom,
        uint256 _targetTimeTo,
        address _pool,
        address _token,
        uint256 _amount,
        bool forVeCake
    ) external onlyOwner {
        if (!poolInfo[_pool].isActive) revert InvalidPool();
        if (!allowedToken[_token] && _token != NATIVE) revert InvalidBribeToken();

        if (!_isValidPeriodEndTime(_targetTimeFrom) || !_isValidPeriodEndTime(_targetTimeTo))
            revert InvalidTargetTime();
        if (_amount == 0) revert ZeroAmount();

        bytes32 rewardIdentifierFrom = _getTokenIdentifier(_targetTimeFrom, _pool, _token);

        Bribe storage bribeFrom = forVeCake
            ? bribesForVeCake[rewardIdentifierFrom]
            : bribes[rewardIdentifierFrom];

        if (bribeFrom.token == address(0)) revert InvalidBribeToken();

        if (bribeFrom.amount < _amount) revert InsufficientAmount();

        bribeFrom.amount -= _amount;

        bytes32 poolIdentifierTo = _getPoolIdentifier(_targetTimeTo, _pool);
        bytes32 rewardIdentifierTo = _getTokenIdentifier(_targetTimeTo, _pool, _token);

        Bribe storage bribeTo = forVeCake
            ? bribesForVeCake[rewardIdentifierTo]
            : bribes[rewardIdentifierTo];
        bribeTo.amount += _amount;
        if (bribeTo.token == address(0)) {
            bribeTo.token = _token;
            if (forVeCake) bribesInPoolForVeCake[poolIdentifierTo].push(rewardIdentifierTo);
            else bribesInPool[poolIdentifierTo].push(rewardIdentifierTo);
        }

        emit BribeReallocated(_pool, _token, _targetTimeFrom, _targetTimeTo, _amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
