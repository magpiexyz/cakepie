// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @title mCake
/// @author Magpie Team
contract mCake is
    OwnableUpgradeable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() {
        _disableInitializers();
    }

    error NonContractCaller();

    function __mCake_init(address deployer, uint256 _initialMint) public initializer {
        __ERC20_init("mCake Token", "mCake");
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init();
        __ERC20Permit_init("mCake Token");
        _mint(deployer, _initialMint);
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        if (!Address.isContract(msg.sender)) revert NonContractCaller();
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal virtual override whenNotPaused {
        super._mint(to, amount);
    }

    function _burn(address to, uint256 amount) internal virtual override whenNotPaused {
        super._burn(to, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
