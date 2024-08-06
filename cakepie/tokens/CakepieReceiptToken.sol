// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/ERC20.sol)
pragma solidity ^0.8.19;

import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IMasterCakepie } from "../../interfaces/cakepie/IMasterCakepie.sol";
import { IPancakeStaking } from "../../interfaces/cakepie/IPancakeStaking.sol";

/// @title CakepieReceiptToken is to represent a Pancake pools deposited to cakepie posistion. CakepieReceiptToken is minted to user who deposited pools token
///        on Pancake staking to increase defi lego
///         
///         Reward from Magpie and on BaseReward should be updated upon every transfer.
///
/// @author Magpie Team
/// @notice Mater cakepie emit `CKP` reward token based on Time. For a pool, 

contract CakepieReceiptToken is ERC20, Ownable {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IERC20;

    address public underlying;  // pool address if a pancake pool, underlying otken if a masterCakepie pool
    address public immutable masterCakepie;
    address public immutable pancakeStaking;  // pancakStaking none zero address, means the receipt token represents a LP staked on cakepie getting boosted yield

    /* ============ Constructor ============ */

    constructor(address _underlying, address _masterCakepie, address _pancakeStaking, string memory name, string memory symbol) ERC20(name, symbol) {
        underlying = _underlying;
        masterCakepie = _masterCakepie;
        pancakeStaking = _pancakeStaking;
    } 

    // should only be called by 1. pancakestaking for Pancake pools deposits 2. masterCakepie for other general staking token such as mCAKEOFT or CKP Lp tokens
    function mint(address account, uint256 amount) external virtual onlyOwner {
        _mint(account, amount);
    }

    // should only be called by 1. pancakestaking for Pancake pools deposits 2. masterCakepie for other general staking token such as mCAKEOFT or CKP Lp tokens
    function burn(address account, uint256 amount) external virtual onlyOwner {
        _burn(account, amount);
    }

    /* ============ Internal Functions ============ */

    // rewards are calculated based on user's receipt token balance, so reward should be updated on master cakepie before transfer
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // no need to harvest again if mint or burn (trigger upon deposit or withdraw)
        if (from != address(0) && to != address(0)) _checkHarvestPancake(); 
        IMasterCakepie(masterCakepie).beforeReceiptTokenTransfer(from, to, amount);
    }

    // rewards are calculated based on user's receipt token balance, so balance should be updated on master cakepie before transfer
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // no need to harvest again if mint or burn (trigger upon deposit or withdraw)
        if (from != address(0) && to != address(0)) _checkHarvestPancake();
        IMasterCakepie(masterCakepie).afterReceiptTokenTransfer(from, to, amount);
    }

    function _checkHarvestPancake() internal {
        if (pancakeStaking != address(0)) {
            IPancakeStaking(pancakeStaking).genericHarvest(underlying);
        }
    }

}