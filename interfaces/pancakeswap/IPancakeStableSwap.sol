// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IPancakeStableSwap {
    function balances(uint256) external view returns (uint256);

    function get_dy(
        uint256 token0,
        uint256 token1,
        uint256 inputAmount
    ) external view returns (uint256 outputAmount);

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external;

    /*
        Simplified method to calculate addition or reduction in token supply at
        deposit or withdrawal without taking fees into account (but looking at
        slippage).
        Needed to prevent front-running, not for precise calculations!
    */
    function calc_token_amount(
        uint256[2] memory amounts,
        bool deposit
    ) external view returns (uint256);
}
