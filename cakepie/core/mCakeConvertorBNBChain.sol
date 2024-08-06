// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { mCakeConvertorBaseUpg } from "../baseupgs/mCakeConvertorBaseUpg.sol";
import { IVeCake } from "../../interfaces/pancakeswap/IVeCake.sol";
import { IMintableERC20 } from "../../interfaces/common/IMintableERC20.sol";

import { IPancakeStaking } from "../../interfaces/cakepie/IPancakeStaking.sol";

/// @title mCakeConvertor for BNB chain, which is the main chain for pancakeswap and cakepie
/// @author Magpie Team
/// @notice common functions please check mCakeConvertorBaseUpg

contract mCakeConvertorBNBChain is Initializable, mCakeConvertorBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    IVeCake public veCake;
    mapping(address => bool) public allowedOperator;

    /* ============ Events ============ */

    event MintMCakeFor(address _caller, address _for, uint256 _amount);
    event AllowedOperatorSet(address _operator, bool _active);

    /* ============ Errors ============ */

    error OnlyOperator();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __mCakeConvertorBNBChain_init(
        address _CAKE,
        address _mCake,
        address _masterCakepie,
        address _pancakeStaking
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        CAKE = _CAKE;
        mCake = _mCake;
        masterCakepie = _masterCakepie;
        pancakeStaking = _pancakeStaking;
    }

    /* ============ Modifiers ============ */

    modifier _onlyOperator() {
        if (!allowedOperator[msg.sender]) revert OnlyOperator();
        _;
    }

    /* ============ External Functions ============ */

    function mintFor(address _user, uint256 _amount) external _onlyOperator {
        IMintableERC20(mCake).mint(_user, _amount);

        emit MintMCakeFor(msg.sender, _user, _amount);
    }

    /* ============ Admin Functions ============ */

    function lockAllCake() external onlyOwner {
        uint256 allCake = IERC20(CAKE).balanceOf(address(this));

        IERC20(CAKE).safeIncreaseAllowance(pancakeStaking, allCake);
        IPancakeStaking(pancakeStaking).increaseLock(allCake);
    }

    function setAllowedOperator(address _operator, bool _active) external onlyOwner {
        allowedOperator[_operator] = _active;
        emit AllowedOperatorSet(_operator, _active);
    }
}
