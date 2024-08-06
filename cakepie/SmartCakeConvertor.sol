// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/pancakeswap/IStableSwapRouter.sol";
import "../interfaces/pancakeswap/IPancakeStableSwapTwoPool.sol";
import "../interfaces/cakepie/IConvertor.sol";
import "../interfaces/cakepie/IMasterCakepie.sol";
import "../interfaces/cakepie/ILocker.sol";

/// @title Smart Cake Convertor
/// @author Magpie Team

contract SmartCakeConvertor is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public mCake;
    address public mCakeConvertor;
    address public cake;
    address public router;
    address public swapContract;
    address public masterCakepie;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant STAKE_MODE = 1;
    uint256 public constant LOCK_MODE = 2;
    uint256 public WAD = 1e18;
    uint256 public ratio;
    uint256 public buybackThreshold;
    ILocker public mCakeSV;

    /* ============ Errors ============ */

    error IncorrectRatio();
    error MinRecNotMatch();
    error MustNoBeZero();
    error IncorrectThreshold();
    error AddressZero();

    /* ============ Events ============ */

    event mCakeConverted(address user, uint256 cakeInput, uint256 obtainedmCake, uint256 mode);

    event mCakeSVUpdated(address _oldmCakeSV, address _newmCakeSV);

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __SmartCakeConvert_init(
        address _mCake,
        address _mCakeConvertor,
        address _cake,
        address _mCakeSV,
        address _router,
        address _masterCakepie,
        address _swapContract,
        uint256 _ratio
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (_ratio > DENOMINATOR)
            revert IncorrectRatio();

        mCake = _mCake;
        mCakeConvertor = _mCakeConvertor;
        cake = _cake;
        mCakeSV = ILocker(_mCakeSV);
        router = _router;
        masterCakepie = _masterCakepie;
        swapContract = _swapContract;
        ratio = _ratio;
        buybackThreshold = 9500;
    }

    /* ============ External Getters ============ */

    function estimateTotalConversion(
        uint256 _amountIn,
        uint256 _convertRatio
    ) public view returns (uint256 minimumEstimatedTotal) {
        if (_convertRatio > DENOMINATOR) revert IncorrectRatio();

        uint256 buybackAmount = _amountIn - ((_amountIn * _convertRatio) / DENOMINATOR);
        uint256 convertAmount = _amountIn - buybackAmount;
        uint256 amountOut = 0;

        if (buybackAmount > 0) {
            (amountOut) = IPancakeStableSwapTwoPool(swapContract).get_dy(0, 1, buybackAmount);
        }

        return (amountOut + convertAmount);
    }

    function maxSwapAmount() public view returns (uint256) {
        uint256 cakeBalance = IPancakeStableSwapTwoPool(swapContract).balances(0);
        uint256 mCakeBalance = IPancakeStableSwapTwoPool(swapContract).balances(1);

        if (cakeBalance >= mCakeBalance) return 0;

        return ((mCakeBalance - cakeBalance) * ratio) / DENOMINATOR;
    }

    function currentRatio() public view returns (uint256) {
        uint256 amountOut = IPancakeStableSwapTwoPool(swapContract).get_dy(1, 0, 1e18);
        return (amountOut * DENOMINATOR) / 1e18;
    }

    // /* ============ External Functions ============ */

    function convert(
        uint256 _amountIn,
        uint256 _convertRatio,
        uint256 _minRec,
        uint256 _mode
    ) external returns (uint256 obtainedMCakeAmount) {
        obtainedMCakeAmount = _convertFor(_amountIn, _convertRatio, _minRec, msg.sender, _mode);
    }

    function convertFor(
        uint256 _amountIn,
        uint256 _convertRatio,
        uint256 _minRec,
        address _for,
        uint256 _mode
    ) external returns (uint256 obtainedMCakeAmount) {
        obtainedMCakeAmount = _convertFor(_amountIn, _convertRatio, _minRec, _for, _mode);
    }

    // should mainly used by cakepie staking upon sending cake
    function smartConvert(
        uint256 _amountIn,
        uint256 _mode
    ) external returns (uint256 obtainedMCakeAmount) {
        if (_amountIn == 0) revert MustNoBeZero();

        uint256 convertRatio = _calConvertRatio(_amountIn);

        return _convertFor(_amountIn, convertRatio, _amountIn, msg.sender, _mode);
    }

    function smartConvertFor(
        uint256 _amountIn,
        uint256 _mode,
        address _for
    ) external returns (uint256 obtainedmCakeAmount) {
        if (_amountIn == 0) revert MustNoBeZero();

        uint256 convertRatio = _calConvertRatio(_amountIn);

        return _convertFor(_amountIn, convertRatio, _amountIn, _for, _mode);
    }

    function setRatio(uint256 _ratio) external onlyOwner {
        if (_ratio > DENOMINATOR) revert IncorrectRatio();

        ratio = _ratio;
    }

    function setBuybackThreshold(uint256 _threshold) external onlyOwner {
        if (_threshold > DENOMINATOR) revert IncorrectThreshold();

        buybackThreshold = _threshold;
    }

    /* ============ Admin Functions ============ */

    function setmCakeSV(address _newmCakeSV) public onlyOwner {
        if (_newmCakeSV == address(0)) revert AddressZero();

        address _oldmCakeSV = address(mCakeSV);
        mCakeSV = ILocker(_newmCakeSV);

        emit mCakeSVUpdated(_oldmCakeSV, _newmCakeSV);
    }

    // /* ============ Internal Functions ============ */

    function _calConvertRatio(uint256 _amountIn) internal view returns (uint256 convertRatio) {
        convertRatio = DENOMINATOR;
        uint256 mCakeToCake = currentRatio();

        if (mCakeToCake < buybackThreshold) {
            uint256 maxSwap = maxSwapAmount();
            uint256 amountToSwap = _amountIn > maxSwap ? maxSwap : _amountIn;
            uint256 convertAmount = _amountIn - amountToSwap;
            convertRatio = (convertAmount * DENOMINATOR) / _amountIn;
        }
    }

    function _convertFor(
        uint256 _amount,
        uint256 _convertRatio,
        uint256 _minRec,
        address _for,
        uint256 _mode
    ) internal nonReentrant returns (uint256 obtainedMCakeAmount) {
        if (_convertRatio > DENOMINATOR) revert IncorrectRatio();

        IERC20(cake).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 buybackAmount = _amount - ((_amount * _convertRatio) / DENOMINATOR);
        uint256 convertAmount = _amount - buybackAmount;
        uint256 amountRec = 0;

        if (buybackAmount > 0) {
            address[] memory tokenPath = new address[](2);
            tokenPath[0] = cake;
            tokenPath[1] = mCake;
            uint256[] memory flag = new uint256[](1);
            flag[0] = 2;

            IERC20(cake).safeApprove(router, buybackAmount);

            uint256 oldBalance = IERC20(mCake).balanceOf(address(this));
            IStableSwapRouter(router).exactInputStableSwap(
                tokenPath,
                flag,
                buybackAmount,
                buybackAmount,
                address(this)
            );
            uint256 newBalance = IERC20(mCake).balanceOf(address(this));

            amountRec = newBalance - oldBalance;
        }
        if (convertAmount + amountRec < _minRec) revert MinRecNotMatch();

        if (convertAmount > 0) {
            IERC20(cake).safeApprove(mCakeConvertor, convertAmount);
            IConvertor(mCakeConvertor).convert(address(this), convertAmount, 0);
        }

        obtainedMCakeAmount = convertAmount + amountRec;

        if (_mode == STAKE_MODE) {
            IERC20(mCake).safeApprove(masterCakepie, obtainedMCakeAmount);
            IMasterCakepie(masterCakepie).depositFor(mCake, _for, obtainedMCakeAmount);
        } else if (_mode == LOCK_MODE) {
            IERC20(mCake).safeApprove(address(mCakeSV), obtainedMCakeAmount);
            mCakeSV.lockFor(obtainedMCakeAmount, _for);
        } else {
            IERC20(mCake).safeTransfer(_for, obtainedMCakeAmount);
        }

        emit mCakeConverted(_for, _amount, obtainedMCakeAmount, _mode);
    }
}
