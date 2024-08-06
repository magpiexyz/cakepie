// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PancakeStakingBaseUpg } from "../baseupgs/PancakeStakingBaseUpg.sol";

/// @title PancakeStaking
/// @notice PancakeStaking is the main contract interacting with pancakeswap side.
/// @author Magpie Team

contract PancakeStakingSideChain is PancakeStakingBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public mCakeConvertorSideChain;

    /* ============ Events ============ */

    event mCakeConvertorSet(address _mCakeConvertor);

    /* ============ Errors ============ */

    error AddressZero();

    /* ============ Constructor ============ */

    receive() external payable {}

    constructor() {
        _disableInitializers();
    }

    function __PancakeStakingSideChain_init(
        address _CAKE,
        address _mCake,
        address _masterCakepie
    ) public initializer {
        __PancakeStakingBaseUpg_init(_CAKE, _mCake, _masterCakepie);
    }

    /* ============ Modifiers ============ */

    /* ============ Admin Functions ============ */

    function setMCakeConvertorSideChain(address _mCakeConvertoSideChain) external onlyOwner {
        if (_mCakeConvertoSideChain == address(0)) revert AddressZero();
        mCakeConvertorSideChain = _mCakeConvertoSideChain;
        emit mCakeConvertorSet(mCakeConvertorSideChain);
    }
}
