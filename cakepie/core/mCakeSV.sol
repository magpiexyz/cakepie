// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/cakepie/IMasterCakepie.sol";
import "../../interfaces/cakepie/ILocker.sol";

// Lock mCake Steability Vault token can exist ONLY in MasterCakepie for reward counting
// Master Magpie needs to add this as mCake Loyalty Vault helper as well
/// @title mCake Steadbility Vault
/// @author Magpie XYZ Team
contract mCakeSV is
    ILocker,
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public masterCakepie;
    uint256 public maxSlot;

    uint256 public constant DENOMINATOR = 10000;

    IERC20 public mCake;

    uint256 public coolDownInSecs;
    uint256 public override totalAmountInCoolDown;

    mapping(address => UserUnlocking[]) public userUnlockings;
    mapping(address => bool) public transferWhitelist;
    address public penaltyDestination;
    uint256 public totalPenalty;
    uint256 private totalAmount;

    /* ============ Errors ============ */

    error MaxSlotShouldNotZero();
    error BeyondUnlockLength();
    error BeyondUnlockSlotLimit();
    error NotEnoughLockedmCake();
    error UnlockSlotOccupied();
    error StillInCoolDown();
    error NotInCoolDown();
    error UnlockedAlready();
    error MaxSlotCantLowered();
    error NotTransferrable();
    error AllUnlockSlotOccupied();
    error InvalidAddress();
    error InvalidCoolDownPeriod();

    /* ============ Events ============ */

    event UnlockStarts(address indexed _user, uint256 indexed _timestamp, uint256 _amount);
    event Unlock(address indexed user, uint256 indexed timestamp, uint256 amount);
    event NewLock(address indexed user, uint256 indexed timestamp, uint256 amount);
    event ReLock(address indexed user, uint256 slotIdx, uint256 amount);
    event WhitelistSet(address _for, bool _status);
    event NewMasterChiefUpdated(address _oldMaster, address _newMaster);
    event MaxSlotUpdated(uint256 _maxSlot);
    event CoolDownInSecsUpdated(uint256 _coolDownSecs);
    event ForceUnLock(
        address indexed user,
        uint256 slotIdx,
        uint256 mCakeAmount,
        uint256 penaltyAmount
    );
    event PenaltyDestinationUpdated(address penaltyDestination);
    event PenaltySentTo(address penaltyDestination, uint256 amount);

    function __mCakeSV_init_(
        address _masterCakepie,
        uint256 _maxSlots,
        address _mCake,
        uint256 _coolDownInSecs
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ERC20_init("mCake Stability Vault", "mCakeSV");
        if (_maxSlots <= 0) revert MaxSlotShouldNotZero();
        maxSlot = _maxSlots;
        masterCakepie = _masterCakepie;
        mCake = IERC20(_mCake);
        coolDownInSecs = _coolDownInSecs;
    }

    /* ============ External Getters ============ */

    function totalSupply() public view override returns (uint256) {
        return totalAmount;
    }

    function balanceOf(address _user) public view override returns (uint256) {
        return getUserTotalLocked(_user) + getUserAmountInCoolDown(_user);
    }

    // total mCake locked, excluding the ones in cool down
    function totalLocked() public view override returns (uint256) {
        return this.totalSupply() - this.totalAmountInCoolDown();
    }

    /// @notice Get the total mCake a user locked, not counting the ones in cool down
    /// @param _user the user
    /// @return _lockAmount the total mCake a user locked, not counting the ones in cool down
    function getUserTotalLocked(address _user) public view override returns (uint256 _lockAmount) {
        // needs fixing
        (uint256 _amountInMasterCakepie, ) = IMasterCakepie(masterCakepie).stakingInfo(
            address(this),
            _user
        );
        _lockAmount = _amountInMasterCakepie - getUserAmountInCoolDown(_user);
    }

    function getUserAmountInCoolDown(address _user) public view override returns (uint256) {
        uint256 length = getUserUnlockSlotLength(_user);
        uint256 totalCoolDownAmount = 0;
        for (uint256 i; i < length; i++) {
            totalCoolDownAmount += userUnlockings[_user][i].amountInCoolDown;
        }

        return totalCoolDownAmount;
    }

    /// @notice Get the n'th user slot info
    /// @param _user the user
    /// @param n the index of the unlock slot
    function getUserNthUnlockSlot(
        address _user,
        uint256 n
    )
        external
        view
        override
        returns (uint256 startTime, uint256 endTime, uint256 amountInCoolDown)
    {
        UserUnlocking storage slot = userUnlockings[_user][n];
        startTime = slot.startTime;
        endTime = slot.endTime;
        amountInCoolDown = slot.amountInCoolDown;
    }

    /// @notice Get the number of user unlock schedule
    /// @param _user the user
    function getUserUnlockSlotLength(address _user) public view override returns (uint256) {
        return userUnlockings[_user].length;
    }

    function getUserUnlockingSchedule(
        address _user
    ) external view override returns (UserUnlocking[] memory slots) {
        uint256 length = getUserUnlockSlotLength(_user);
        slots = new UserUnlocking[](length);
        for (uint256 i; i < length; i++) {
            slots[i] = userUnlockings[_user][i];
        }
    }

    function getFullyUnlock(address _user) public view override returns (uint256 unlockedAmount) {
        uint256 length = getUserUnlockSlotLength(_user);
        for (uint256 i; i < length; i++) {
            if (
                userUnlockings[_user][i].amountInCoolDown > 0 &&
                block.timestamp > userUnlockings[_user][i].endTime
            ) unlockedAmount += userUnlockings[_user][i].amountInCoolDown;
        }
    }

    function getRewardablePercentWAD(address _user) public view override returns (uint256 percent) {
        uint256 fullyInLock = getUserTotalLocked(_user);
        uint256 inCoolDown = getUserAmountInCoolDown(_user);
        uint256 userTotalmCakeSV = fullyInLock + inCoolDown;
        if (userTotalmCakeSV == 0) return 0;
        percent = (fullyInLock * 1e18) / userTotalmCakeSV;

        uint256 timeNow = block.timestamp;
        UserUnlocking[] storage userUnlocking = userUnlockings[_user];

        for (uint256 i; i < userUnlocking.length; i++) {
            if (userUnlocking[i].amountInCoolDown > 0) {
                if (block.timestamp > userUnlocking[i].endTime) {
                    // fully unlocked
                    percent +=
                        (userUnlocking[i].amountInCoolDown *
                            1e18 *
                            (userUnlocking[i].endTime - userUnlocking[i].startTime)) /
                        userTotalmCakeSV /
                        (timeNow - userUnlocking[i].startTime);
                } else {
                    // still in cool down
                    percent += (userUnlocking[i].amountInCoolDown * 1e18) / userTotalmCakeSV;
                }
            }
        }

        return percent;
    }

    function getNextAvailableUnlockSlot(address _user) public view override returns (uint256) {
        uint256 length = getUserUnlockSlotLength(_user);
        if (length < maxSlot) return length;

        // length as maxSlot
        for (uint256 i; i < length; i++) {
            if (userUnlockings[_user][i].amountInCoolDown == 0) return i;
        }

        revert AllUnlockSlotOccupied();
    }

    /* ============ External Functions ============ */

    // @notice lock mCake in the contract
    // @param _amount the amount of mCake to lock
    function lock(uint256 _amount) external override whenNotPaused nonReentrant {
        _lock(msg.sender, msg.sender, _amount);

        emit NewLock(msg.sender, block.timestamp, _amount);
    }

    // @notice lock mCake in the contract
    // @param _amount the amount of mCake to lock
    // @param _for the address to lcock for
    // @dev the tokens will be taken from msg.sender
    function lockFor(uint256 _amount, address _for) external override whenNotPaused nonReentrant {
        _lock(msg.sender, _for, _amount);

        emit NewLock(_for, block.timestamp, _amount);
    }

    // @notice starts an unlock slot
    // @notice this function can also be used to reset or change a slot
    // @param strategyIndex The choosen unlock strategy
    // @param amount the mCake amount for the slot
    // @param slotIndex the index of the slot to use
    function startUnlock(uint256 _amountToCoolDown) external override whenNotPaused nonReentrant {
        if (_amountToCoolDown > getUserTotalLocked(msg.sender)) revert NotEnoughLockedmCake();

        //uint256 totalLockAfterStartUnlock = getUserTotalLocked(msg.sender) - _amountToCoolDown;
        address[] memory lps = new address[](1);
        address[][] memory mCakeSVrewards = new address[][](1);
        lps[0] = address(this);
        IMasterCakepie(masterCakepie).multiclaimFor(lps, mCakeSVrewards, msg.sender);

        uint256 _slotIndex = getNextAvailableUnlockSlot(msg.sender);
        totalAmountInCoolDown += _amountToCoolDown;

        if (_slotIndex < getUserUnlockSlotLength(msg.sender)) {
            userUnlockings[msg.sender][_slotIndex] = UserUnlocking({
                startTime: block.timestamp,
                endTime: block.timestamp + coolDownInSecs,
                amountInCoolDown: _amountToCoolDown
            });
        } else {
            userUnlockings[msg.sender].push(
                UserUnlocking({
                    startTime: block.timestamp,
                    endTime: block.timestamp + coolDownInSecs,
                    amountInCoolDown: _amountToCoolDown
                })
            );
        }

        emit UnlockStarts(msg.sender, block.timestamp, _amountToCoolDown);
    }

    // @notice unlock a finished slot
    // @param slotIndex the index of the slot to unlock
    function unlock(uint256 _slotIndex) external override whenNotPaused nonReentrant {
        _checkIdexInBoundary(msg.sender, _slotIndex);
        UserUnlocking storage slot = userUnlockings[msg.sender][_slotIndex];

        if (slot.endTime > block.timestamp) revert StillInCoolDown();

        if (slot.amountInCoolDown == 0) revert UnlockedAlready();

        address[] memory lps = new address[](1);
        address[][] memory mCakeSVrewards = new address[][](1);
        lps[0] = address(this);
        IMasterCakepie(masterCakepie).multiclaimFor(lps, mCakeSVrewards, msg.sender);

        uint256 unlockedAmount = slot.amountInCoolDown;
        _unlock(unlockedAmount);

        slot.amountInCoolDown = 0;
        IERC20(mCake).safeTransfer(msg.sender, unlockedAmount);

        emit Unlock(msg.sender, block.timestamp, unlockedAmount);
    }

    function cancelUnlock(uint256 _slotIndex) external override whenNotPaused {
        _checkIdexInBoundary(msg.sender, _slotIndex);
        UserUnlocking storage slot = userUnlockings[msg.sender][_slotIndex];

        _checkInCoolDown(msg.sender, _slotIndex);

        totalAmountInCoolDown -= slot.amountInCoolDown; // reduce amount to cool down accordingly
        slot.amountInCoolDown = 0; // not in cool down anymore

        emit ReLock(msg.sender, _slotIndex, slot.amountInCoolDown);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setCoolDownInSecs(uint256 _coolDownSecs) external onlyOwner {
        if (_coolDownSecs <= 0) revert InvalidCoolDownPeriod();
        coolDownInSecs = _coolDownSecs;

        emit CoolDownInSecsUpdated(_coolDownSecs);
    }

    /// @notice Change the max number of unlocking slots
    /// @param _maxSlots the new max number
    function setMaxSlots(uint256 _maxSlots) external onlyOwner {
        if (_maxSlots <= maxSlot) revert MaxSlotCantLowered();

        maxSlot = _maxSlots;

        emit MaxSlotUpdated(maxSlot);
    }

    /* ============ Internal Functions ============ */

    function _checkIdexInBoundary(address _user, uint256 _slotIdx) internal view {
        if (_slotIdx >= maxSlot) revert BeyondUnlockSlotLimit();

        if (_slotIdx >= getUserUnlockSlotLength(_user)) revert BeyondUnlockLength();
    }

    function _checkInCoolDown(address _user, uint256 _slotIdx) internal view {
        UserUnlocking storage slot = userUnlockings[_user][_slotIdx];
        if (slot.amountInCoolDown == 0) revert UnlockedAlready();

        if (slot.endTime <= block.timestamp) revert NotInCoolDown();
    }

    function _unlock(uint256 _unlockedAmount) internal {
        IMasterCakepie(masterCakepie).withdrawMCakeSVFor(_unlockedAmount, msg.sender); // trigers update pool share, so happens before total amount reducing
        totalAmountInCoolDown -= _unlockedAmount;
        totalAmount -= _unlockedAmount;
    }

    function _lock(address spender, address _for, uint256 _amount) internal {
        mCake.safeTransferFrom(spender, address(this), _amount);
        IMasterCakepie(masterCakepie).depositMCakeSVFor(_amount, _for);
        totalAmount += _amount; // trigers update pool share, so happens after toal amount increase
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        revert NotTransferrable();
    }
}
