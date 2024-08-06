// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { mCakeConvertorBaseUpg } from "../baseupgs/mCakeConvertorBaseUpg.sol";

/// @title mCakeConvertor for side chains such as Ethereum, Abritrum
/// @author Magpie Team
/// @notice common functions please check mCakeConvertorBaseUpg

contract mCakeConvertorSideChain is Initializable, mCakeConvertorBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __mCakeConvertorSideChain_init(
        address _pancakeStaking,
        address _CAKE,
        address _mCake,
        address _masterCakepie
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pancakeStaking = _pancakeStaking;
        CAKE = _CAKE;
        mCake = _mCake;
        masterCakepie = _masterCakepie;
    }

    function withdrawToAdmin() external onlyOwner {
        uint256 allCake = IERC20(CAKE).balanceOf(address(this));
        IERC20(CAKE).safeTransfer(owner(), allCake);
        emit CakeWithdrawToAdmin(owner(), allCake);
    }
}
