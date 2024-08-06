// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
pragma abicoder v2;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../../interfaces/pancakeswap/IFarmBooster.sol";

/// @title CrossChainStaker
/// @notice Cross Chain Staker contract is the main contract that will stake positions or LPs into MasterChef V3 and Wrappers on side chains
/// @author Magpie Team

contract CrossChainStaker is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{

    /* ============ Events ============ */
    event ApproveToLocker(address indexed _veCakeUser);

    /* ============ Errors ============ */
    error AddressZero();

    /* ============ Constructor ============ */

    receive() external payable {}

    constructor() {
        _disableInitializers();
    }

    /* ============ Constructor ============ */

    function __CrossChainStaker_init() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    function approveToLocker(
        address[] memory _farmBooster,
        address _veCakeUser
    ) external nonReentrant onlyOwner {
        if (_veCakeUser == address(0)) revert AddressZero();
        for (uint256 i = 0; i < _farmBooster.length; i++) {
            if (_farmBooster[i] == address(0)) revert AddressZero();
            IFarmBooster(_farmBooster[i]).approveToVECakeUser(_veCakeUser);
        }
        emit ApproveToLocker(_veCakeUser);
    }
}
