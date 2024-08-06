// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ILocker.sol";

interface IVLCakepie is ILocker {
    
    function cakepie() external view returns(IERC20);
}