// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IMasterChefV3 } from "../../interfaces/pancakeswap/IMasterChefV3.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { INonfungiblePositionManager } from "../../interfaces/pancakeswap/INonfungiblePositionManager.sol";
import { INonfungiblePositionManagerStruct } from "../../interfaces/pancakeswap/INonfungiblePositionManagerStruct.sol";
import { IPancakeV3PoolImmutables } from "../../interfaces/pancakeswap/IPancakeV3PoolImmutables.sol";
import { IMintableERC20 } from "../../interfaces/common/IMintableERC20.sol";
import { IRewardDistributor } from "../../interfaces/cakepie/IRewardDistributor.sol";
import { IALMWrapper } from "../../interfaces/pancakeswap/IALMWrapper.sol";
import { IV2Wrapper } from "../../interfaces/pancakeswap/IV2Wrapper.sol";
import { IAdapter } from "../../interfaces/pancakeswap/IAdapter.sol";
import {IPancakeVeSender} from "../../interfaces/pancakeswap/IPancakeVeSender.sol";
import {IIFOV8} from "../../interfaces/pancakeswap/IIFOV8.sol";
import {IPancakeIFOHelper} from "../../interfaces/cakepie/IPancakeIFOHelper.sol";



library PancakeStakingLib {
    using SafeERC20 for IERC20;

    event V3PoolFeesPaidTo(
        address indexed _user,
        uint256 _positionId,
        address _token,
        uint256 _feeAmount
    );
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
    event BroadcastedVeCakeToChain(uint32 indexed _destChainId);
    event VestedIFORewardClaimed(
        address indexed pancakeIFOHelper,
        address _for,
        uint256 claimedAmount,
        address rewardToken
    );
    event IFORewardHarvested(
        address indexed pancakeIFOHelper,
        address _for,
        address rewardToken,
        uint256 harvestedAmount,
        address refundToken,
        uint256 refundAmount
    );
    event DepositedIntoIFO(address indexed pancakeIFOHelper, uint8 pid, uint256 amount);

    error AddressZero();
    error TransferFailed();

    function depositV3For(
        address _for,
        address _pool,
        uint256 _tokenId,
        IMasterChefV3 masterChefV3,
        INonfungiblePositionManager nonfungiblePositionManager
    ) external {
        (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(_tokenId);

        nonfungiblePositionManager.safeTransferFrom(_for, address(this), _tokenId);
        nonfungiblePositionManager.safeTransferFrom(address(this), address(masterChefV3), _tokenId);

        emit NewTokenStaked(_for, _pool, _tokenId, liquidity);
    }

    function withdrawV3For(
        address _for,
        address _pool,
        uint256 _tokenId,
        address cake,
        IMasterChefV3 masterChefV3,
        IRewardDistributor rewardDistributor,
        INonfungiblePositionManager nonfungiblePositionManager
    ) external {
        (uint256[] memory tokenId, ) = toArray(_tokenId, address(0));

        (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(_tokenId);

        harvestV3PoolFees(_for, tokenId, masterChefV3, nonfungiblePositionManager);

        uint256 balBefore = IERC20(cake).balanceOf(address(this));

        masterChefV3.withdraw(_tokenId, address(this));

        handleRewards(rewardDistributor, _pool, address(cake), balBefore, _for, false);

        INonfungiblePositionManager(nonfungiblePositionManager).safeTransferFrom(
            address(this),
            _for,
            _tokenId
        );

        emit NewTokenUnstaked(_for, _pool, _tokenId, liquidity);
    }

    function increaseLiquidityV3For(
        address _for,
        address _pool,
        IMasterChefV3 masterChefV3,
        IMasterChefV3.IncreaseLiquidityParams calldata params
    ) external {
        address token0 = IPancakeV3PoolImmutables(_pool).token0();
        address token1 = IPancakeV3PoolImmutables(_pool).token1();

        (uint256 balBeforeToken0, uint256 balBeforeToken1) = checkTokenBalances(token0, token1);

        IERC20(token0).safeTransferFrom(msg.sender, address(this), params.amount0Desired);
        IERC20(token0).safeIncreaseAllowance(address(masterChefV3), params.amount0Desired);

        IERC20(token1).safeTransferFrom(msg.sender, address(this), params.amount1Desired);
        IERC20(token1).safeIncreaseAllowance(address(masterChefV3), params.amount1Desired);

        masterChefV3.increaseLiquidity(params);

        refund(token0, _for, balBeforeToken0);
        refund(token1, _for, balBeforeToken1);
    }

    function decreaseLiquidityV3For(
        address _for,
        IMasterChefV3 masterChefV3,
        INonfungiblePositionManager nonfungiblePositionManager,
        IMasterChefV3.DecreaseLiquidityParams calldata params
    ) external {
        (uint256[] memory tokenId, ) = toArray(params.tokenId, address(0));
        masterChefV3.decreaseLiquidity(params);
        harvestV3PoolFees(_for, tokenId, masterChefV3, nonfungiblePositionManager);
    }

    function harvestV3(
        address _for,
        uint256[] memory _tokenIds,
        address cake,
        IMasterChefV3 masterChefV3,
        IRewardDistributor rewardDistributor
    ) external {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            (, , , , , , , uint256 pid, ) = masterChefV3.userPositionInfos(
                _tokenIds[i]
            );

            (, address _pool, , , , , ) = masterChefV3.poolInfo(pid);

            uint256 balBefore = IERC20(cake).balanceOf(address(this));

            masterChefV3.harvest(_tokenIds[i], address(this));

            handleRewards(rewardDistributor, _pool, address(cake), balBefore, _for, false);
        }
    }

    function harvestV3PoolFees(
        address _for,
        uint256[] memory _tokenIds,
        IMasterChefV3 masterChefV3,
        INonfungiblePositionManager nonfungiblePositionManager
    ) public {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(_tokenIds[i]);

            (uint256 token0BalBefore, uint256 token1BalBefore) = checkTokenBalances(
                token0,
                token1
            );

            INonfungiblePositionManagerStruct.CollectParams
                memory params = INonfungiblePositionManagerStruct.CollectParams({
                    tokenId: _tokenIds[i],
                    recipient: address(this),
                    amount0Max: 340282366920938463463374607431768211455,
                    amount1Max: 340282366920938463463374607431768211455
                });

            masterChefV3.collect(params);
            (uint256 token0BalAfter, uint256 token1BalAfter) = checkTokenBalances(token0, token1);

            // Since fee is not boosted, simply transfer to owner
            uint256 diff0 = token0BalAfter - token0BalBefore;
            if (diff0 > 0) {
                IERC20(token0).safeTransfer(_for, diff0);
                emit V3PoolFeesPaidTo(_for, _tokenIds[i], token0, diff0);
            }

            uint256 diff1 = token1BalAfter - token1BalBefore;
            if (diff1 > 0) {
                IERC20(token1).safeTransfer(_for, diff1);
                emit V3PoolFeesPaidTo(_for, _tokenIds[i], token1, diff1);
            }
        }
    }

    function handleWithdrawAML(
        address _for,
        address _pool,
        uint256 _amount,
        address _token0,
        address _token1,
        address _rewarder,
        address cake,
        IRewardDistributor rewardDistributor
    ) external {
        uint256 balBefore = IERC20(cake).balanceOf(address(this));

        (uint256 balBeforeToken0, uint256 balBeforeToken1) = checkTokenBalances(_token0, _token1);
        IALMWrapper(_pool).withdrawThenBurn(_amount, false, "");
        (uint256 balAfterToken0, uint256 balAfterToken1) = checkTokenBalances(_token0, _token1);

        IERC20(_token0).safeTransfer(_for, balAfterToken0 - balBeforeToken0);
        IERC20(_token1).safeTransfer(_for, balAfterToken1 - balBeforeToken1);

        handleRewards(rewardDistributor, _pool, address(cake), balBefore, _rewarder, true);
    }

    function handleRewards(
        IRewardDistributor rewardDistributor,
        address _poolAddress,
        address _rewardToken,
        uint256 _balBefore,
        address _to,
        bool _isRewarder
    ) public {
        uint256 _pendingRewards = IERC20(_rewardToken).balanceOf(address(this)) - _balBefore;
        if (_pendingRewards > 0) {
            IERC20(_rewardToken).safeIncreaseAllowance(address(rewardDistributor), _pendingRewards);
            IRewardDistributor(rewardDistributor).sendRewards(
                _poolAddress,
                _rewardToken,
                _to,
                _pendingRewards,
                _isRewarder
            );
        }
    }

    function refund(address _token, address _dustTo, uint256 _balBeforeToken) public {
        uint256 dustTokenAmt = IERC20(_token).balanceOf(address(this)) - _balBeforeToken;
        if (dustTokenAmt > 0) IERC20(_token).safeTransfer(_dustTo, dustTokenAmt);
    }

    function checkTokenBalances(
        address _token0,
        address _token1
    ) public view returns (uint256, uint256) {
        uint256 balBeforeToken0 = IERC20(_token0).balanceOf(address(this));
        uint256 balBeforeToken1 = IERC20(_token1).balanceOf(address(this));

        return (balBeforeToken0, balBeforeToken1);
    }

    function toArray(
        uint256 _tokenId,
        address _poolAddress
    ) public pure returns (uint256[] memory tokenId, address[] memory poolAddress) {
        tokenId = new uint256[](1);
        tokenId[0] = _tokenId;

        poolAddress = new address[](1);
        poolAddress[0] = _poolAddress;
    }

    function depositIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        uint8 _pid,
        address _depositToken,
        address _for,
        uint256 _amount
    ) external {
        IERC20(_depositToken).safeTransferFrom(_for, address(this), _amount);
        IERC20(_depositToken).safeIncreaseAllowance(_pancakeIFO, _amount);

        IIFOV8(_pancakeIFO).depositPool(_amount, _pid);

        emit DepositedIntoIFO(_pancakeIFOHelper, _pid, _amount);
    }

    function harvestIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        uint8 _pid,
        address _depositToken,
        address _rewardToken
    ) external {
        (uint256 balBeforedepositToken, uint256 balBeforeRewardToken) = checkTokenBalances(
            _depositToken,
            _rewardToken
        );

        IIFOV8(_pancakeIFO).harvestPool(_pid);

        uint256 refundAmt = IERC20(_depositToken).balanceOf(address(this)) - balBeforedepositToken;
        uint256 harvestedTokenAmt = IERC20(_rewardToken).balanceOf(address(this)) -
            balBeforeRewardToken;
        if (refundAmt > 0) {
            IERC20(_depositToken).safeIncreaseAllowance(_pancakeIFOHelper, refundAmt);
            IPancakeIFOHelper(_pancakeIFOHelper).queueNewTokens(refundAmt, _depositToken);
        }
        if (harvestedTokenAmt > 0) {
            IERC20(_rewardToken).safeIncreaseAllowance(_pancakeIFOHelper, harvestedTokenAmt);
            IPancakeIFOHelper(_pancakeIFOHelper).queueNewTokens(harvestedTokenAmt, _rewardToken);
        }
        emit IFORewardHarvested(
            _pancakeIFOHelper,
            address(this),
            _rewardToken,
            harvestedTokenAmt,
            _depositToken,
            refundAmt
        );
    }

    function releaseIFO(
        address _pancakeIFOHelper,
        address _pancakeIFO,
        bytes32 _vestingScheduleId,
        address _rewardToken
    ) external {
        uint256 balBefore = IERC20(_rewardToken).balanceOf(address(this));

        IIFOV8(_pancakeIFO).release(_vestingScheduleId);

        uint256 earnedVestedReward = IERC20(_rewardToken).balanceOf(address(this)) - balBefore;

        if (earnedVestedReward > 0) {
            IERC20(_rewardToken).safeIncreaseAllowance(_pancakeIFOHelper, earnedVestedReward);
            IPancakeIFOHelper(_pancakeIFOHelper).queueNewTokens(earnedVestedReward, _rewardToken);
        }

        emit VestedIFORewardClaimed(
            _pancakeIFOHelper,
            address(this),
            earnedVestedReward,
            _rewardToken
        );
    }

    function broadcastVeCake(
        address _pancakeVeSender,
        uint32 _dstChainId,
        uint128 _gasForDest,
        address owner
    ) external {
        if (_pancakeVeSender == address(0)) revert AddressZero();
        IPancakeVeSender(_pancakeVeSender).sendSyncMsg{ value: msg.value }(
            _dstChainId,
            address(this),
            true,
            true,
            _gasForDest
        );
        uint256 refundedAmount = address(this).balance;
        if (refundedAmount > 0) {
            (bool success, ) = payable(owner).call{value: refundedAmount, gas: 5000}("");
            if(!success)
                revert TransferFailed();
        }
        emit BroadcastedVeCakeToChain(_dstChainId);
    }
}