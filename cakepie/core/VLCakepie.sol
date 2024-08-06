// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

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
import { IMasterCakepie } from "../../interfaces/cakepie/IMasterCakepie.sol";
import { IVLCakepie } from "../../interfaces/cakepie/IVLCakepie.sol";
import { IPancakeVoteManager } from "../../interfaces/cakepie/IPancakeVoteManager.sol";

// Lock Cakepie token can exist ONLY in masterCakepie for reward counting
// Master Magpie needs to add this as vote Lock Cakepie's pool helper as well
/// @title Vote Lock Cakepie
/// @author Magpie XYZ Team
contract VLCakepie is
    IVLCakepie,
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

    IERC20 public override cakepie;

    uint256 public coolDownInSecs;
    uint256 public override totalAmountInCoolDown;

    mapping(address => UserUnlocking[]) public userUnlockings;
    address public penaltyDestination;
    uint256 public totalPenalty;

    address public pancakeVoteManager;
    uint256 private totalAmount;

    

    /* ============ Errors ============ */

    error MaxSlotShouldNotZero();
    error BeyondUnlockLength();
    error BeyondUnlockSlotLimit();
    error NotEnoughLockedCakepie();
    error UnlockSlotOccupied();
    error StillInCoolDown();
    error NotInCoolDown();
    error UnlockedAlready();
    error MaxSlotCantLowered();
    error TransferNotAllowed();
    error AllUnlockSlotOccupied();
    error InvalidAddress();
    error InvalidCoolDownPeriod();
    error PenaltyToNotSet();
    error AlreadyMigrated();

    /* ============ Events ============ */

    event UnlockStarts(
        address indexed _user,
        uint256 indexed _timestamp,
        uint256 _amount
    );
    event Unlock(
        address indexed user,
        uint256 indexed timestamp,
        uint256 amount
    );
    event NewLock(
        address indexed user,
        uint256 indexed timestamp,
        uint256 amount
    );
    event ReLock(address indexed user, uint256 slotIdx, uint256 amount);
    event WhitelistSet(address _for, bool _status);
    event NewMasterChiefUpdated(address _oldMaster, address _newMaster);
    event MaxSlotUpdated(uint256 _maxSlot);
    event CoolDownInSecsUpdated(uint256 _coolDownSecs);
    event ForceUnLock(
        address indexed user,
        uint256 slotIdx,
        uint256 cakepieamount,
        uint256 penaltyAmount
    );
    event PenaltyDestinationUpdated(address penaltyDestination);
    event PenaltySentTo(address penaltyDestination, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function __vlCakepie_init_(
        address _masterCakepie,
        uint256 _maxSlots,
        address _cakepie,
        uint256 _coolDownInSecs
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("Vote Locked Cakepie", "vlCakepie");
        if (_maxSlots == 0)
            revert MaxSlotShouldNotZero();
        maxSlot = _maxSlots;
        masterCakepie = _masterCakepie;
        cakepie = IERC20(_cakepie);
        coolDownInSecs = _coolDownInSecs;
    }

    /* ============ External Getters ============ */

    function totalSupply() public view override returns (uint256) {
        return totalAmount;
    }

    function balanceOf(address _user) public view override returns (uint256) {
        return getUserTotalLocked(_user) + getUserAmountInCoolDown(_user);
    }

    // total Cakepie locked, excluding the ones in cool down
    function totalLocked() public view override returns (uint256) {
        return this.totalSupply() - this.totalAmountInCoolDown();
    }

    /// @notice Get the total Cakepie a user locked, not counting the ones in cool down
    /// @param _user the user
    /// @return _lockAmount the total Cakepie a user locked, not counting the ones in cool down
    function getUserTotalLocked(
        address _user
    ) public view override returns (uint256 _lockAmount) {
        // needs fixing
        (uint256 _amountInmasterCakepie, ) = IMasterCakepie(masterCakepie)
            .stakingInfo(address(this), _user);
        _lockAmount = _amountInmasterCakepie - getUserAmountInCoolDown(_user);
    }

    function getUserAmountInCoolDown(
        address _user
    ) public view override returns (uint256) {
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
    function getUserUnlockSlotLength(
        address _user
    ) public view override returns (uint256) {
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

    function getFullyUnlock(
        address _user
    ) public view override returns (uint256 unlockedAmount) {
        uint256 length = getUserUnlockSlotLength(_user);
        for (uint256 i; i < length; i++) {
            if (
                userUnlockings[_user][i].amountInCoolDown > 0 &&
                block.timestamp > userUnlockings[_user][i].endTime
            ) unlockedAmount += userUnlockings[_user][i].amountInCoolDown;
        }
    }

    function getRewardablePercentWAD(
        address _user
    ) public view override returns (uint256 percent) {
        uint256 fullyInLock = getUserTotalLocked(_user);
        uint256 inCoolDown = getUserAmountInCoolDown(_user);
        uint256 userTotalvlCakepie = fullyInLock + inCoolDown;
        if (userTotalvlCakepie == 0) return 0;
        percent = (fullyInLock * 1e18) / userTotalvlCakepie;

        uint256 timeNow = block.timestamp;
        UserUnlocking[] storage userUnlocking = userUnlockings[_user];

        for (uint256 i; i < userUnlocking.length; i++) {
            if (userUnlocking[i].amountInCoolDown > 0) {
                if (block.timestamp > userUnlocking[i].endTime) {
                    // fully unlocked
                    percent +=
                        (userUnlocking[i].amountInCoolDown *
                            1e18 *
                            (userUnlocking[i].endTime -
                                userUnlocking[i].startTime)) /
                        userTotalvlCakepie /
                        (timeNow - userUnlocking[i].startTime);
                } else {
                    // still in cool down
                    percent +=
                        (userUnlocking[i].amountInCoolDown * 1e18) /
                        userTotalvlCakepie;
                }
            }
        }

        return percent;
    }

    function getNextAvailableUnlockSlot(
        address _user
    ) public view override returns (uint256) {
        uint256 length = getUserUnlockSlotLength(_user);
        if (length < maxSlot) return length;

        // length as maxSlot
        for (uint256 i; i < length; i++) {
            if (userUnlockings[_user][i].amountInCoolDown == 0) return i;
        }

        revert AllUnlockSlotOccupied();
    }

    function expectedPenaltyAmount(uint256 _slotIndex) public view returns(uint256 penaltyAmount, uint256 amountToUser) {
        return expectedPenaltyAmountByAccount(msg.sender, _slotIndex);
    }


    function expectedPenaltyAmountByAccount(address account, uint256 _slotIndex) public view returns(uint256 penaltyAmount, uint256 amountToUser) {
        UserUnlocking storage slot = userUnlockings[account][_slotIndex];

        uint256 coolDownAmount = slot.amountInCoolDown;
        uint256 baseAmountToUser = slot.amountInCoolDown / 5;
        uint256 waitingAmount = coolDownAmount - baseAmountToUser;

        uint256 unlockFactor = 1e12;
        if (
            (block.timestamp - slot.startTime) <=
            (slot.endTime - slot.startTime)
        )
            unlockFactor =
                (((block.timestamp - slot.startTime) * 1e12) /
                    (slot.endTime - slot.startTime)) **
                    2 /
                1e12;

        uint256 unlockAmount = (waitingAmount * unlockFactor) / 1e12;
        amountToUser = baseAmountToUser + unlockAmount;
        penaltyAmount = coolDownAmount - amountToUser;
    }

    /* ============ External Functions ============ */

    // @notice lock Cakepie in the contract
    // @param _amount the amount of Cakepie to lock
    function lock(
        uint256 _amount
    ) external override whenNotPaused nonReentrant {
        _lock(msg.sender, msg.sender, _amount);

        emit NewLock(msg.sender, block.timestamp, _amount);
    }

    // @notice lock Cakepie in the contract
    // @param _amount the amount of Cakepie to lock
    // @param _for the address to lcock for
    // @dev the tokens will be taken from msg.sender
    function lockFor(
        uint256 _amount,
        address _for
    ) external override whenNotPaused nonReentrant {
        if (_for == address(0)) revert InvalidAddress();
        _lock(msg.sender, _for, _amount);

        emit NewLock(_for, block.timestamp, _amount);
    }

    // @notice starts an unlock slot
    // @param _amountToCoolDown the Cakepie amount to start unlock
    function startUnlock(
        uint256 _amountToCoolDown
    ) external override whenNotPaused nonReentrant {
        if (_amountToCoolDown > getUserTotalLocked(msg.sender))
            revert NotEnoughLockedCakepie();

        uint256 totalLockAfterStartUnlock = getUserTotalLocked(msg.sender) -
            _amountToCoolDown;
        if (
            address(pancakeVoteManager) != address(0) &&
            totalLockAfterStartUnlock <
            IPancakeVoteManager(pancakeVoteManager).userTotalVotedInVlCakepie(
                msg.sender
            )
        ) revert NotEnoughLockedCakepie();

        _claimFromMaster(msg.sender);

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
    function unlock(
        uint256 _slotIndex
    ) external override whenNotPaused nonReentrant {
        _checkIdexInBoundary(msg.sender, _slotIndex);
        UserUnlocking storage slot = userUnlockings[msg.sender][_slotIndex];

        if (slot.endTime > block.timestamp) revert StillInCoolDown();

        if (slot.amountInCoolDown == 0) revert UnlockedAlready();

        _claimFromMaster(msg.sender);

        uint256 unlockedAmount = slot.amountInCoolDown;
        _unlock(unlockedAmount);

        slot.amountInCoolDown = 0;
        IERC20(cakepie).safeTransfer(msg.sender, unlockedAmount);

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

    // penalty caculation
    function forceUnLock(
        uint256 _slotIndex
    ) external whenNotPaused nonReentrant {
        _checkIdexInBoundary(msg.sender, _slotIndex);
        UserUnlocking storage slot = userUnlockings[msg.sender][_slotIndex];

         // Check if the slot is already unlocked (amountInCoolDown == 0) and revert if so
        if (slot.amountInCoolDown == 0) {
            revert UnlockedAlready();
        }

        uint256 penaltyAmount = 0;
        uint256 amountToUser = slot.amountInCoolDown; // Default to the full amount

        _claimFromMaster(msg.sender);

        // If the current time is not beyond the slot's endTime, then there's penalty.
        if (block.timestamp < slot.endTime) {
            _checkInCoolDown(msg.sender, _slotIndex);

            (penaltyAmount, amountToUser) = expectedPenaltyAmount(_slotIndex);
        }
        
        _unlock(slot.amountInCoolDown); 

        IERC20(cakepie).safeTransfer(msg.sender, amountToUser);
        totalPenalty += penaltyAmount;

        slot.amountInCoolDown = 0;
        slot.endTime = block.timestamp;

        emit ForceUnLock(msg.sender, _slotIndex, amountToUser, penaltyAmount);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function transferPenalty() external onlyOwner {
        if(penaltyDestination == address(0))
            revert PenaltyToNotSet();

        IERC20(cakepie).safeTransfer(penaltyDestination, totalPenalty);

        emit PenaltySentTo(penaltyDestination, totalPenalty);

        totalPenalty = 0;
    }

    function setMasterChief(address _masterCakepie) external onlyOwner {
        if (_masterCakepie == address(0)) revert InvalidAddress();
        address oldChief = masterCakepie;
        masterCakepie = _masterCakepie;

        emit NewMasterChiefUpdated(oldChief, masterCakepie);
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

    function setPenaltyDestination(
        address _penaltyDestination
    ) external onlyOwner {
        penaltyDestination = _penaltyDestination;

        emit PenaltyDestinationUpdated(penaltyDestination);
    }

    function setPancakeVoteManager(
        address _pancakeVoteManager
    ) external onlyOwner {
        pancakeVoteManager = _pancakeVoteManager;
    }

    /* ============ Internal Functions ============ */

    function _checkIdexInBoundary(
        address _user,
        uint256 _slotIdx
    ) internal view {
        if (_slotIdx >= maxSlot) revert BeyondUnlockSlotLimit();

        if (_slotIdx >= getUserUnlockSlotLength(_user))
            revert BeyondUnlockLength();
    }

    function _checkInCoolDown(address _user, uint256 _slotIdx) internal view {
        UserUnlocking storage slot = userUnlockings[_user][_slotIdx];
        if (slot.amountInCoolDown == 0) revert UnlockedAlready();

        if (slot.endTime <= block.timestamp) revert NotInCoolDown();
    }

    function _unlock(uint256 _unlockedAmount) internal {
        IMasterCakepie(masterCakepie).withdrawVlCakepieFor(_unlockedAmount, msg.sender); // trigers update pool share, so happens before total amount reducing
        totalAmountInCoolDown -= _unlockedAmount;
        totalAmount -= _unlockedAmount;
    }

    function _lock(
        address spender,
        address _for,
        uint256 _amount
    ) internal {
        cakepie.safeTransferFrom(spender, address(this), _amount);
        IMasterCakepie(masterCakepie).depositVlCakepieFor(_amount, _for);
        totalAmount += _amount; // trigers update pool share, so happens after toal amount increase
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        revert TransferNotAllowed();
    }

    function _claimFromMaster(address _user) internal {
        address[] memory lps = new address[](1);
        address[][] memory vlCakepieRewards = new address[][](1);
        lps[0] = address(this);
        IMasterCakepie(masterCakepie).multiclaimFor(
            lps,
            vlCakepieRewards,
            _user
        );
    }
}
