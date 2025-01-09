// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/cakepieReader/IMasterCakepieReader.sol";
import "../interfaces/cakepieReader/IPancakeStakingReader.sol";
import "../interfaces/cakepieReader/IPancakeV3HelperReader.sol";
import "../interfaces/cakepieReader/IPancakeRouter02Reader.sol";
import "../interfaces/cakepieReader/IPancakeV3PoolReader.sol";
import "../interfaces/cakepieReader/IPancakeV3LmPoolReader.sol";
import "../interfaces/cakepieReader/IFarmBoosterReader.sol";
import "../interfaces/cakepie/AggregatorV3Interface.sol";
import "../interfaces/pancakeswap/IMasterChefV3.sol";
import "../interfaces/pancakeswap/IPancakeV3PoolImmutables.sol";
import "../interfaces/cakepie/IRewardDistributor.sol";
import "../interfaces/pancakeswap/INonfungiblePositionManager.sol";
import "../interfaces/pancakeswap/IPancakeV3Factory.sol";
import "../interfaces/cakepieReader/IVLCakepieReader.sol";
import "../interfaces/cakepieReader/IMCakeConvertorReader.sol";
import "../interfaces/pancakeswap/IAdapter.sol";
import "../interfaces/pancakeswap/IALMWrapper.sol";

/// @title CakepieReader for SideChain
/// @author Magpie Team

contract CakepieReaderSideChain is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct CakepieInfo {
        address masterCakepie;
        address pancakeStaking;
        address cakepieOFT;
        address CAKE;
        address nonFungiblePositionManager;
        address mCakeConvertor;
        address masterChefV3;
        CakepiePool[] pools;
        CakepiePool mCakePool;
        CakepiePool mCakeSVPool;
        TokenIdInfo[] userStakedTokenIdsInfo;
        TokenIdInfo[] userAvailableTokenIdsInfo;
        TokenIdInfo[] allStakedTokenIdsInfo;
        MasterChefV3Info masterChefV3Info;
        uint256 userCakeBal;
        uint256 userCakeConvertAllowance;
        VlCakepieLockInfo userMCakeSVInfo;
        uint256 userMCakeLockAllowance;
        CakepiePool vlCKPPool;
        VlCakepieLockInfo userVlCKPInfo;
        uint256 userCKPBal;
        uint256 userCKPLockAllowance;
    }

    struct MasterChefV3Info {
        uint256 totalAllocPoint;
        uint256 latestPeriodCakePerSecond;
    }

    struct CakepiePool {
        uint256 poolId;
        address poolAddress; // Address of staking token contract to be staked.
        address depositToken; // For V2, it's Lp address, For V3 it's single side token
        uint256 depositTokenBalance;
        address receiptToken; // Address of receipt token contract represent a staking position
        uint256 lastRewardTimestamp; // Last timestamp that Cakepies distribution occurs.
        uint256 CKPemission;
        uint256 totalStaked;
        address helper;
        address rewarder;
        bool isActive;
        uint256 poolType;
        uint256 lastHarvestTime;
        ERC20TokenInfo depositTokenInfo;
        V2LikeAccountInfo accountInfo;
        V3AccountInfo v3AccountInfo;
        V3PoolInfo v3PoolInfo;
        bool isAmount0;
    }

    struct RewardInfo {
        uint256 pendingCakepie;
        address[] bonusTokenAddresses;
        string[] bonusTokenSymbols;
        uint256[] pendingBonusRewards;
        uint256[] pendingBonusDecimals;
        uint256 masterChefV3PendingCakepie;
    }

    struct V3PoolInfo {
        uint256 pid;
        ERC20TokenInfo token0;
        ERC20TokenInfo token1;
        uint256 totalLiquidity;
        uint256 totalBoostLiquidity;
        uint256 allocPoint;
        address v3Pool;
        V3PoolSlot0 slot0;
        uint24 fee;
        uint128 liquidity;
        address lmPool;
        uint128 lmLiquidity;
        bool farmCanBoost;
    }

    struct V3PoolSlot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint32 feeProtocol;
        bool unlocked;
    }

    struct V3AccountInfo {
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 token0V3HelperAllowance;
        uint256 token1V3HelperAllowance;
        uint256 stakedAmount;
    }

    struct TokenIdInfo {
        uint256 tokenId;
        bool isApprovedStake;
        TokenIdPosition position;
        RewardInfo rewardInfo;
        EarnedFeeInfo earnedFeeInfo;
        address pool;
    }

    struct TokenIdPosition {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint128 boostLiquidity;
        uint256 boostMultiplier;
    }

    struct EarnedFeeInfo {
        //  ERC20TokenInfo token0;
        uint256 feeEarnedtoken0;
        //  ERC20TokenInfo token1;
        uint256 feeEarnedtoken1;
    }

    struct DepositInfo {
        uint256 balance;
        uint256 stakingAllowance;
    }

    struct V2LikeAccountInfo {
        RewardInfo rewardInfo;
        uint256 balance;
        uint256 stakedAmount;
        uint256 stakingAllowance;
        RewardInfo legacyRewardInfo;
    }

    struct ERC20TokenInfo {
        address tokenAddress;
        string symbol;
        uint256 decimals;
        bool isNative;
    }

    struct VlCakepieLockInfo {
        uint256 userTotalLocked;
        uint256 userAmountInCoolDown;
        VlCakepieUserUnlocking[] userUnlockingSchedule;
        uint256 totalPenalty;
        uint256 nextAvailableUnlockSlot;
        bool isFull;
    }

    struct VlCakepieUserUnlocking {
        uint256 startTime;
        uint256 endTime;
        uint256 amountInCoolDown; // total amount comitted to the unlock slot, never changes except when reseting slot
        uint256 expectedPenaltyAmount;
        uint256 amountToUser;
    }

    IPancakeStakingReader public pancakeStaking;
    IPancakeV3HelperReader public pancakeV3Helper;
    IMasterCakepieReader public masterCakepie;
    IMasterChefV3 public masterChefV3;
    IRewardDistributor public rewardDistributor;
    address public nonFungiblePositionManager;

    address public pancakeV2LPHelper;
    address public pancakeAMLHelper;

    uint16 public totalLpFee;

    uint256 public constant StableSwapType = 0;
    uint256 public constant V3Type = 1;
    uint256 public constant V2Type = 2;
    uint256 public constant AMLType = 3;

    address[] public tokenList;
    address public cake;
    address public mCake;
    address public cakepieOFT;
    address public WETHToken;
    address public mCakeConvertor;
    address public v3Factory;
    address public v3FARM_BOOSTER;
    address public mCakeSV;
    address public vlCKP;

    function __CakepieReaderSideChain_init() public initializer {
        __Ownable_init();
    }

    /* ============ External Getters ============ */
    function getERC20TokenInfo(address token) public view returns (ERC20TokenInfo memory) {
        ERC20TokenInfo memory tokenInfo;
        if (token == address(0)) return tokenInfo;
        tokenInfo.tokenAddress = token;
        if (token == address(1)) {
            tokenInfo.symbol = "ETH";
            tokenInfo.decimals = 18;
            return tokenInfo;
        }
        ERC20 tokenContract = ERC20(token);
        tokenInfo.symbol = tokenContract.symbol();
        tokenInfo.decimals = tokenContract.decimals();
        return tokenInfo;
    }

    function getCakepieInfo(address account) external view returns (CakepieInfo memory) {
        CakepieInfo memory info;
        uint256 poolCount = pancakeStaking.poolLength();

        CakepiePool[] memory pools = new CakepiePool[](poolCount);

        for (uint256 i = 0; i < poolCount; ++i) {
            pools[i] = getCakepiePoolInfo(i, account);
            pools[i].poolId = i;
        }

        info.pools = pools;
        info.masterCakepie = address(masterCakepie);
        info.pancakeStaking = address(pancakeStaking);
        info.masterChefV3 = address(masterChefV3);
        MasterChefV3Info memory masterChefV3Info;
        masterChefV3Info.totalAllocPoint = masterChefV3.totalAllocPoint();
        masterChefV3Info.latestPeriodCakePerSecond = masterChefV3.latestPeriodCakePerSecond();
        info.masterChefV3Info = masterChefV3Info;
        info.cakepieOFT = cakepieOFT;
        info.CAKE = cake;
        info.nonFungiblePositionManager = address(nonFungiblePositionManager);
        info.mCakeConvertor = mCakeConvertor;
        if (account != address(0)) {
            info.userStakedTokenIdsInfo = _getCakepieStakedTokenIdsInfo(account);
            info.userAvailableTokenIdsInfo = _getAvailableTokenIdsInfo(account);
            // info.userMCakeSVInfo = getCakepieLockInfo(account, mCakeSV);
            // info.userVlCKPInfo = getCakepieLockInfo(account, vlCKP);

            info.userCakeBal = ERC20(cake).balanceOf(account);
            // info.userCakeConvertAllowance = ERC20(cake).allowance(account, mCakeConvertor);
            // info.userMCakeLockAllowance = ERC20(mCake).allowance(account, mCakeSV);
            // if (cakepieOFT != address(0)) {
            //     info.userCKPBal = ERC20(cakepieOFT).balanceOf(account);
            //     info.userCKPLockAllowance = ERC20(cakepieOFT).allowance(account, vlCKP);
            // }
        }

        // info.mCakePool = getMCakePooInfo(account, mCake);
        // info.mCakeSVPool = getMCakePooInfo(account, mCakeSV);
        // info.vlCKPPool = getMCakePooInfo(account, vlCKP);

        //info.allStakedTokenIdsInfo = _getStakedTokenIdsInfo(info.pancakeStaking);
        return info;
    }

    function getCakepiePoolInfo(
        uint256 poolId,
        address account
    ) public view returns (CakepiePool memory) {
        address poolAddresss = pancakeStaking.poolList(poolId);
        IPancakeStakingReader.PancakeStakingPoolInfo memory poolInfo = pancakeStaking.pools(
            poolAddresss
        );

        if (poolInfo.poolType == V3Type) {
            return getV3PoolInfo(poolInfo, account);
        } else if (
            poolInfo.poolType == V2Type ||
            poolInfo.poolType == AMLType ||
            poolInfo.poolType == StableSwapType
        ) {
            return getV2LikePoolInfo(poolInfo, account);
        }

        CakepiePool memory dummy;
        return dummy;
    }

    function getMCakePooInfo(
        address account,
        address poolAddr
    ) public view returns (CakepiePool memory) {
        CakepiePool memory pool;
        IMasterCakepieReader.CakepiePoolInfo memory cakepiePoolInfo = masterCakepie.tokenToPoolInfo(
            poolAddr
        );
        pool.poolAddress = poolAddr;
        pool.lastRewardTimestamp = cakepiePoolInfo.lastRewardTimestamp;
        pool.totalStaked = cakepiePoolInfo.totalStaked;
        pool.rewarder = cakepiePoolInfo.rewarder;
        pool.isActive = cakepiePoolInfo.isActive;
        pool.receiptToken = cakepiePoolInfo.receiptToken;
        pool.depositTokenInfo = getERC20TokenInfo(pool.poolAddress);
        pool.depositToken = pool.poolAddress;
        (pool.CKPemission, , , ) = masterCakepie.getPoolInfo(pool.poolAddress);
        if (account != address(0)) {
            pool.accountInfo = getV2LikeAccountInfo(pool, account);
            pool.accountInfo.rewardInfo = getRewardInfo(pool.poolAddress, account, false);
            pool.accountInfo.legacyRewardInfo = getRewardInfo(pool.poolAddress, account, true);
        }

        return pool;
    }

    // for V2, AML, and stable swap
    function getV2LikePoolInfo(
        IPancakeStakingReader.PancakeStakingPoolInfo memory V2LpLikepoolInfo,
        address account
    ) public view returns (CakepiePool memory) {
        CakepiePool memory cakepiePool;
        IMasterCakepieReader.CakepiePoolInfo memory cakepiePoolInfo = masterCakepie.tokenToPoolInfo(
            V2LpLikepoolInfo.poolAddress
        );
        cakepiePool.poolAddress = V2LpLikepoolInfo.poolAddress;
        cakepiePool.lastRewardTimestamp = cakepiePoolInfo.lastRewardTimestamp;
        cakepiePool.totalStaked = cakepiePoolInfo.totalStaked;
        cakepiePool.rewarder = cakepiePoolInfo.rewarder;
        cakepiePool.isActive = cakepiePoolInfo.isActive;
        cakepiePool.receiptToken = cakepiePoolInfo.receiptToken;
        (cakepiePool.CKPemission, , , ) = masterCakepie.getPoolInfo(cakepiePool.poolAddress);

        cakepiePool.poolType = V2LpLikepoolInfo.poolType;
        cakepiePool.depositToken = V2LpLikepoolInfo.depositToken;
        cakepiePool.isAmount0 = V2LpLikepoolInfo.isAmount0;

        cakepiePool.helper = (V2LpLikepoolInfo.poolType == V2Type ||
            V2LpLikepoolInfo.poolType == StableSwapType)
            ? pancakeV2LPHelper
            : pancakeAMLHelper;
        cakepiePool.lastHarvestTime = V2LpLikepoolInfo.lastHarvestTime;
        cakepiePool.depositTokenInfo = getERC20TokenInfo(V2LpLikepoolInfo.depositToken);

        if (account != address(0)) {
            if (cakepiePool.poolType == 3 && cakepiePool.depositToken == address(0))
                cakepiePool.v3AccountInfo = getALMAccountInfo(cakepiePool, account);
            else cakepiePool.accountInfo = getV2LikeAccountInfo(cakepiePool, account);
            cakepiePool.accountInfo.rewardInfo = getRewardInfo(
                cakepiePool.poolAddress,
                account,
                false
            );
            cakepiePool.accountInfo.legacyRewardInfo = getRewardInfo(
                cakepiePool.poolAddress,
                account,
                true
            );
        }

        return cakepiePool;
    }

    function getV2LikeAccountInfo(
        CakepiePool memory pool,
        address account
    ) public view returns (V2LikeAccountInfo memory) {
        V2LikeAccountInfo memory accountInfo;
        if (pool.poolAddress != mCake) {
            // if poolType > 3, not pancakeStaking pool
            accountInfo.balance = ERC20(pool.depositToken).balanceOf(account);
            accountInfo.stakingAllowance = ERC20(pool.depositToken).allowance(
                account,
                address(pancakeStaking)
            );
            accountInfo.stakedAmount = ERC20(pool.receiptToken).balanceOf(account);
        } else {
            accountInfo.balance = ERC20(pool.depositToken).balanceOf(account);
            accountInfo.stakingAllowance = ERC20(pool.depositToken).allowance(
                account,
                address(masterCakepie)
            );
            (accountInfo.stakedAmount, ) = masterCakepie.stakingInfo(pool.depositToken, account);
        }

        return accountInfo;
    }

    function getV3PoolInfo(
        IPancakeStakingReader.PancakeStakingPoolInfo memory V3poolInfo,
        address account
    ) public view returns (CakepiePool memory) {
        CakepiePool memory cakepiePool;
        cakepiePool.poolAddress = V3poolInfo.poolAddress;
        cakepiePool.totalStaked = V3poolInfo.v3Liquidity;
        cakepiePool.helper = address(pancakeV3Helper);
        cakepiePool.isActive = V3poolInfo.isActive;
        cakepiePool.poolType = V3poolInfo.poolType;
        V3PoolInfo memory v3PoolInfo;
        uint256 pid = masterChefV3.v3PoolAddressPid(V3poolInfo.poolAddress);
        address token0;
        address token1;
        (
            v3PoolInfo.allocPoint,
            v3PoolInfo.v3Pool,
            token0,
            token1,
            ,
            v3PoolInfo.totalLiquidity,
            v3PoolInfo.totalBoostLiquidity
        ) = masterChefV3.poolInfo(pid);
        v3PoolInfo.token0 = getERC20TokenInfo(token0);

        v3PoolInfo.token1 = getERC20TokenInfo(token1);
        if (v3PoolInfo.token0.tokenAddress == WETHToken) {
            v3PoolInfo.token0.isNative = true;
        }
        if (v3PoolInfo.token1.tokenAddress == WETHToken) {
            v3PoolInfo.token1.isNative = true;
        }
        v3PoolInfo.pid = pid;
        V3PoolSlot0 memory slot0;
        (
            slot0.sqrtPriceX96,
            slot0.tick,
            slot0.observationIndex,
            slot0.observationCardinality,
            slot0.observationCardinalityNext,
            slot0.feeProtocol,
            slot0.unlocked
        ) = IPancakeV3PoolReader(V3poolInfo.poolAddress).slot0();
        v3PoolInfo.slot0 = slot0;
        v3PoolInfo.fee = IPancakeV3PoolReader(V3poolInfo.poolAddress).fee();
        v3PoolInfo.liquidity = IPancakeV3PoolReader(V3poolInfo.poolAddress).liquidity();
        v3PoolInfo.lmPool = IPancakeV3PoolReader(V3poolInfo.poolAddress).lmPool();
        v3PoolInfo.lmLiquidity = IPancakeV3LmPoolReader(v3PoolInfo.lmPool).lmLiquidity();
        v3PoolInfo.farmCanBoost = IFarmBoosterReader(v3FARM_BOOSTER).whiteList(pid);
        cakepiePool.v3PoolInfo = v3PoolInfo;
        if (account != address(0)) {
            cakepiePool.v3AccountInfo = getV3AccountInfo(cakepiePool, account);
        }
        return cakepiePool;
    }

    function getV3AccountInfo(
        CakepiePool memory pool,
        address account
    ) public view returns (V3AccountInfo memory) {
        V3AccountInfo memory v3Info;
        address token0 = pool.v3PoolInfo.token0.tokenAddress;
        address token1 = pool.v3PoolInfo.token1.tokenAddress;
        if (pool.v3PoolInfo.token0.isNative == true) {
            v3Info.token0Balance = account.balance;
            v3Info.token0V3HelperAllowance = type(uint256).max;
        } else {
            v3Info.token0Balance = IERC20(token0).balanceOf(account);
            v3Info.token0V3HelperAllowance = IERC20(token0).allowance(account, pool.helper);
        }
        if (pool.v3PoolInfo.token1.isNative == true) {
            v3Info.token1Balance = account.balance;
            v3Info.token1V3HelperAllowance = type(uint256).max;
        } else {
            v3Info.token1Balance = IERC20(token1).balanceOf(account);
            v3Info.token1V3HelperAllowance = IERC20(token1).allowance(account, pool.helper);
        }
        return v3Info;
    }

    function getALMAccountInfo(
        CakepiePool memory pool,
        address account
    ) public view returns (V3AccountInfo memory) {
        V3AccountInfo memory v3Info;
        address adapterAddress = IALMWrapper(pool.poolAddress).adapterAddr();
        address token0 = IAdapter(adapterAddress).token0();
        address token1 = IAdapter(adapterAddress).token1();

        v3Info.token0Balance = IERC20(token0).balanceOf(account);
        v3Info.token0V3HelperAllowance = IERC20(token0).allowance(account, address(pancakeStaking));
        v3Info.token1Balance = IERC20(token1).balanceOf(account);
        v3Info.token1V3HelperAllowance = IERC20(token1).allowance(account, address(pancakeStaking));
        v3Info.stakedAmount = ERC20(pool.receiptToken).balanceOf(account);
        return v3Info;
    }

    function getV3DepositInfo(
        address depositToken,
        address account
    ) public view returns (DepositInfo memory) {
        DepositInfo memory accountInfo;

        accountInfo.balance = ERC20(depositToken).balanceOf(account);
        accountInfo.stakingAllowance = ERC20(depositToken).allowance(
            account,
            address(pancakeV3Helper)
        );

        return accountInfo;
    }

    function getRewardInfo(
        address poolAddress,
        address account,
        bool isLgacy
    ) public view returns (RewardInfo memory) {
        RewardInfo memory rewardInfo;

        if (!isLgacy) {
            (
                rewardInfo.pendingCakepie,
                rewardInfo.bonusTokenAddresses,
                rewardInfo.bonusTokenSymbols,
                rewardInfo.pendingBonusRewards
            ) = masterCakepie.allPendingTokens(poolAddress, account);
        } else {
            (
                rewardInfo.bonusTokenAddresses,
                rewardInfo.bonusTokenSymbols,
                rewardInfo.pendingBonusRewards
            ) = masterCakepie.allPendingLegacyTokens(poolAddress, account);
        }

        uint256 tokenCount = rewardInfo.bonusTokenAddresses.length;
        rewardInfo.pendingBonusDecimals = new uint256[](rewardInfo.bonusTokenAddresses.length);
        for (uint256 i = 0; i < tokenCount; i++) {
            rewardInfo.pendingBonusDecimals[i] = IERC20Metadata(rewardInfo.bonusTokenAddresses[i])
                .decimals();
        }
        return rewardInfo;
    }

    function getV3Reward(uint256 cakeRewardAmount) public view returns (RewardInfo memory) {
        RewardInfo memory rewardInfo;

        uint256 userCakeReward = (cakeRewardAmount * totalLpFee) / 10000;

        rewardInfo.bonusTokenAddresses = new address[](1);
        rewardInfo.bonusTokenAddresses[0] = cake;
        rewardInfo.bonusTokenSymbols = new string[](1);
        rewardInfo.bonusTokenSymbols[0] = IERC20Metadata(cake).symbol();
        rewardInfo.pendingBonusRewards = new uint256[](1);
        rewardInfo.pendingBonusRewards[0] = userCakeReward;
        rewardInfo.pendingBonusDecimals = new uint256[](1);
        rewardInfo.pendingBonusDecimals[0] = IERC20Metadata(cake).decimals();
        rewardInfo.masterChefV3PendingCakepie = cakeRewardAmount;
        rewardInfo.pendingCakepie = (rewardDistributor.CKPRatio() * userCakeReward) / 10000;
        return rewardInfo;
    }

    // function getCakepieLockInfo(
    //     address account,
    //     address locker
    // ) public view returns (VlCakepieLockInfo memory) {
    //     VlCakepieLockInfo memory vlCakepieLockInfo;
    //     IVLCakepieReader vlCakepieReader = IVLCakepieReader(locker);
    //     vlCakepieLockInfo.totalPenalty = vlCakepieReader.totalPenalty();
    //     if (account != address(0)) {
    //         try vlCakepieReader.getNextAvailableUnlockSlot(account) returns (
    //             uint256 nextAvailableUnlockSlot
    //         ) {
    //             vlCakepieLockInfo.isFull = false;
    //         } catch {
    //             vlCakepieLockInfo.isFull = true;
    //         }
    //         vlCakepieLockInfo.userAmountInCoolDown = vlCakepieReader.getUserAmountInCoolDown(
    //             account
    //         );
    //         vlCakepieLockInfo.userTotalLocked = vlCakepieReader.getUserTotalLocked(account);
    //         IVLCakepieReader.UserUnlocking[] memory userUnlockingList = vlCakepieReader
    //             .getUserUnlockingSchedule(account);
    //         VlCakepieUserUnlocking[]
    //             memory vlCakepieUserUnlockingList = new VlCakepieUserUnlocking[](
    //                 userUnlockingList.length
    //             );
    //         for (uint256 i = 0; i < userUnlockingList.length; i++) {
    //             VlCakepieUserUnlocking memory vlCakepieUserUnlocking;
    //             IVLCakepieReader.UserUnlocking memory userUnlocking = userUnlockingList[i];
    //             vlCakepieUserUnlocking.startTime = userUnlocking.startTime;
    //             vlCakepieUserUnlocking.endTime = userUnlocking.endTime;
    //             vlCakepieUserUnlocking.amountInCoolDown = userUnlocking.amountInCoolDown;
    //             // force unlock info only applicable for vlCKP
    //             if (locker == vlCKP) {
    //                 (uint256 penaltyAmount, uint256 amountToUser) = vlCakepieReader
    //                     .expectedPenaltyAmountByAccount(account, i);
    //                 vlCakepieUserUnlocking.expectedPenaltyAmount = penaltyAmount;
    //                 vlCakepieUserUnlocking.amountToUser = amountToUser;
    //             }
    //             vlCakepieUserUnlockingList[i] = vlCakepieUserUnlocking;
    //         }
    //         vlCakepieLockInfo.userUnlockingSchedule = vlCakepieUserUnlockingList;
    //     }
    //     return vlCakepieLockInfo;
    // }

    function config(
        address _pancakeStaking,
        address _masterChefV3,
        //address _mCakeConvertor,
        uint16 _totalpfee
    ) external onlyOwner {
        pancakeStaking = IPancakeStakingReader(_pancakeStaking);
        pancakeV2LPHelper = pancakeStaking.pancakeV2LPHelper();
        pancakeV3Helper = IPancakeV3HelperReader(pancakeStaking.pancakeV3Helper());
        pancakeAMLHelper = pancakeStaking.pancakeAMLHelper();
        rewardDistributor = IRewardDistributor(pancakeStaking.rewardDistributor());
        cake = pancakeStaking.CAKE();
        masterCakepie = IMasterCakepieReader(pancakeStaking.masterCakepie());
        masterChefV3 = IMasterChefV3(_masterChefV3);
        // mCakeConvertor = _mCakeConvertor;
        // mCake = IMCakeConvertorReader(_mCakeConvertor).mCake();
        totalLpFee = _totalpfee;
        nonFungiblePositionManager = pancakeV3Helper.nonfungiblePositionManager();
        WETHToken = masterChefV3.WETH();
        v3Factory = IPancakeV3PoolImmutables(nonFungiblePositionManager).factory();
        v3FARM_BOOSTER = masterChefV3.FARM_BOOSTER();
    }

    // function setVLCKP(address _vlCKP) external onlyOwner {
    //     vlCKP = _vlCKP;
    // }

    function tokenToPool(uint256 tokenId) public view returns (address) {
        address factory = IPancakeV3PoolImmutables(nonFungiblePositionManager).factory();
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(nonFungiblePositionManager).positions(tokenId);
        address pool = IPancakeV3Factory(factory).getPool(token0, token1, fee);

        return pool;
    }

    function positionToPool(TokenIdPosition memory position) public view returns (address) {
        address pool = IPancakeV3Factory(v3Factory).getPool(
            position.token0,
            position.token1,
            position.fee
        );
        return pool;
    }

    /* ============ Internal Functions ============ */

    function _getAvailableTokenIdsInfo(
        address account
    ) internal view returns (TokenIdInfo[] memory) {
        uint256 counter = 0;
        uint256 totalAvailableToken = INonfungiblePositionManager(nonFungiblePositionManager)
            .balanceOf(account);
        TokenIdInfo[] memory availableTokenIdsInfo = new TokenIdInfo[](totalAvailableToken);
        for (uint256 i = 0; i < totalAvailableToken; i++) {
            uint256 _tokenId = INonfungiblePositionManager(nonFungiblePositionManager)
                .tokenOfOwnerByIndex(account, i);
            TokenIdInfo memory idInfo;
            idInfo.tokenId = _tokenId;
            address approvedAddress = INonfungiblePositionManager(nonFungiblePositionManager)
                .getApproved(idInfo.tokenId);
            if (approvedAddress == address(pancakeStaking)) {
                idInfo.isApprovedStake = true;
            }
            idInfo.position = _getTokenIdPositionInfo(_tokenId);
            if (idInfo.position.liquidity > 0) {
                idInfo.pool = positionToPool(idInfo.position);
                availableTokenIdsInfo[counter++] = idInfo;
            } else {
                continue;
            }
        }
        TokenIdInfo[] memory availableTokenIdsWithLiquidityInfo = new TokenIdInfo[](counter);
        for (uint256 i = 0; i < counter; i++) {
            availableTokenIdsWithLiquidityInfo[i] = availableTokenIdsInfo[i];
        }
        return availableTokenIdsWithLiquidityInfo;
    }

    function _getStakedTokenIdsInfo(address account) internal view returns (TokenIdInfo[] memory) {
        uint256 totalAvailableToken = IMasterChefV3(masterChefV3).balanceOf(account);
        TokenIdInfo[] memory availableTokenIdsInfo = new TokenIdInfo[](totalAvailableToken);
        for (uint256 i = 0; i < totalAvailableToken; i++) {
            uint256 _tokenId = IMasterChefV3(masterChefV3).tokenOfOwnerByIndex(account, i);
            TokenIdInfo memory idInfo;
            idInfo.tokenId = _tokenId;

            idInfo.position = _getTokenIdPositionInfo(_tokenId);
            idInfo.pool = positionToPool(idInfo.position);
            availableTokenIdsInfo[i] = idInfo;
        }
        return availableTokenIdsInfo;
    }

    function _getCakepieStakedTokenIdsInfo(
        address account
    ) internal view returns (TokenIdInfo[] memory) {
        uint256 totalCKPStakedToken = pancakeV3Helper.balanceOf(account);
        TokenIdInfo[] memory cakepieStakedTokenIdsInfo = new TokenIdInfo[](totalCKPStakedToken);
        for (uint256 i = 0; i < totalCKPStakedToken; i++) {
            uint256 _tokenId = pancakeV3Helper.tokenOfOwnerByIndex(account, i);
            address _pool = tokenToPool(_tokenId);
            TokenIdInfo memory idInfo;
            idInfo.tokenId = _tokenId;
            idInfo.pool = _pool;
            idInfo.position = _getTokenIdPositionInfo(_tokenId);
            (
                ,
                idInfo.position.boostLiquidity,
                ,
                ,
                ,
                ,
                ,
                ,
                idInfo.position.boostMultiplier
            ) = masterChefV3.userPositionInfos(_tokenId);

            idInfo.rewardInfo = getV3Reward(masterChefV3.pendingCake(idInfo.tokenId));
            EarnedFeeInfo memory earnedFeeInfo;
            earnedFeeInfo.feeEarnedtoken0 = idInfo.position.tokensOwed0;
            earnedFeeInfo.feeEarnedtoken1 = idInfo.position.tokensOwed1;
            idInfo.earnedFeeInfo = earnedFeeInfo;
            idInfo.pool = positionToPool(idInfo.position);
            cakepieStakedTokenIdsInfo[i] = idInfo;
        }
        return cakepieStakedTokenIdsInfo;
    }

    function _getTokenIdPositionInfo(
        uint256 tokenId
    ) internal view returns (TokenIdPosition memory) {
        TokenIdPosition memory position;
        (
            ,
            ,
            ,
            ,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        ) = INonfungiblePositionManager(nonFungiblePositionManager).positions(tokenId);
        (, , position.token0, position.token1, , , , , , , , ) = INonfungiblePositionManager(
            nonFungiblePositionManager
        ).positions(tokenId);
        return position;
    }

    function setMCakeSV(address _mCakeSV) external onlyOwner {
        mCakeSV = _mCakeSV;
    }

    function setCakepieOFT(address _cakepieOFT) external onlyOwner {
        cakepieOFT = _cakepieOFT;
    }
}
