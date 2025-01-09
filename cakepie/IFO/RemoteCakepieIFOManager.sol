// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./RemotePancakeIFOHelper.sol";
import "../../interfaces/cakepie/IPancakeStaking.sol";
import "../../interfaces/cakepie/IRemotePancakeIFOHelper.sol";
import "../../interfaces/pancakeswap/IIFOV8.sol";
import "../../libraries/cakepie/IFOConstantsLib.sol";

contract RemoteCakepieIFOManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /* ============ State Variables ============ */

    address public pancakeStaking;
    address[] public remotePancakeIFOHelpersList;

    mapping(address => bool) public isIFOHelperValid;
    mapping(address => address) public ifoToHelper;
    mapping(address => bool) public isAllowedPauser;

    /* ============ Events ============ */

    event IFOHelperCreated(
        address indexed remotePancakeIFOHelper,
        address indexed pancakeIFO,
        uint8 indexed pid
    );
    event RewardClaimedFor(address remotePancakeIFOHelper, address pancakeIFO);
    event DepositTransferredToIFO(
        address indexed remotePancakeIFOHelper,
        address indexed pancakeIFO,
        uint8 pid,
        address depositToken,
        address indexed depositFor,
        uint256 amount
    );
    event Harvested(
        address indexed remotePancakeIFOHelper,
        address indexed pancakeIFO,
        uint8 pid,
        address offeringToken,
        uint256 vestedAmount
    );
    event MultiplierSet();
    event AllowedPauserStatus(
        address indexed account,
        bool status
    );
    event UserAmountsSet();

    
    /* ============ Errors ============ */

    error AlreadyClaimed();
    error OnlyIFOHelper();
    error HelperExist();
    error LengthMismatch();
    error InvalidTokenId();
    error OnlyAllowedPauser();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __RemoteCakepieIFOManager_init(
        address _pancakeStaking
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pancakeStaking = _pancakeStaking;
    }

    modifier _onlyIFOHelper() {
        if (!isIFOHelperValid[msg.sender]) revert OnlyIFOHelper();
        _;
    }

    modifier _onlyAllowedPauser() {
        if (!isAllowedPauser[msg.sender]) revert OnlyAllowedPauser();
        _;
    }

    /* ============ External Read Functions ============ */

    function getPancakeIFOHelpers() external view returns (address[] memory) {
        return remotePancakeIFOHelpersList;
    }

    function getPancakeIFOHelpersCount() external view returns (uint256) {
        return remotePancakeIFOHelpersList.length;
    }

    /* ============ External Authorize Functions ============ */

    function transferDepositToIFO(
        address _pancakeIFO,
        uint8 _pid,
        address _depositToken,
        address _account,
        uint256 _amount
    ) external nonReentrant whenNotPaused _onlyIFOHelper {
        address remotePancakeIFOHelper = msg.sender;

        IPancakeStaking(pancakeStaking).depositIFO(
            remotePancakeIFOHelper,
            _pancakeIFO,
            _pid,
            _depositToken,
            _account,
            _amount
        );
        emit DepositTransferredToIFO(
            remotePancakeIFOHelper,
            _pancakeIFO,
            _pid,
            _depositToken,
            _account,
            _amount
        );
    }

    function releaseIFOFromPancake(
        address _pancakeIFO,
        uint8 _pid
    ) external nonReentrant whenNotPaused _onlyIFOHelper {
        address remotePancakeIFOHelper = msg.sender;

        (, address _offeringToken) = IRemotePancakeIFOHelper(remotePancakeIFOHelper).getDepositNOfferingToken();
        (bytes32 _vestingScheduleId, uint256 _vestedAmount) = _getVestingDetails(_pancakeIFO, _pid);

        if (_vestedAmount > 0) {
            IPancakeStaking(pancakeStaking).releaseIFO(
                remotePancakeIFOHelper,
                _pancakeIFO,
                _vestingScheduleId,
                _offeringToken
            );
        }
        emit Harvested(remotePancakeIFOHelper, _pancakeIFO, _pid, _offeringToken, _vestedAmount);
    }

    /* ============ Admin Functions ============ */

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setAllowedPauser(
        address _account,
        bool _status
    ) public onlyOwner {
        isAllowedPauser[_account] = _status;
        emit AllowedPauserStatus(_account, _status);
    }

    function pauseIFOHelper(address _pancakeIFO) external _onlyAllowedPauser {
        address remotePancakeIFOHelper = ifoToHelper[_pancakeIFO];

        IRemotePancakeIFOHelper(remotePancakeIFOHelper).pause();
    }

    function unpauseIFOHelper(address _pancakeIFO) external onlyOwner {
        address remotePancakeIFOHelper = ifoToHelper[_pancakeIFO];

        IRemotePancakeIFOHelper(remotePancakeIFOHelper).unpause();
    }

    function createPancakeIFOHelper(
        address _pancakeIFO,
        uint8 _pid
    ) external onlyOwner {
        if (ifoToHelper[_pancakeIFO] != address(0)) revert HelperExist();

        RemotePancakeIFOHelper newIFOHelper = new RemotePancakeIFOHelper(
            _pancakeIFO,
            _pid,
            pancakeStaking,
            address(this)
        );
        remotePancakeIFOHelpersList.push(address(newIFOHelper));
        isIFOHelperValid[address(newIFOHelper)] = true;
        ifoToHelper[_pancakeIFO] = address(newIFOHelper);
        emit IFOHelperCreated(address(newIFOHelper), _pancakeIFO, _pid);
    }

    function harvestIFOFromPancake(address _pancakeIFO) external onlyOwner {
        address remotePancakeIFOHelper = ifoToHelper[_pancakeIFO];

        (address depositToken, address offeringToken) = IRemotePancakeIFOHelper(remotePancakeIFOHelper)
            .getDepositNOfferingToken();

        bool isClaimed = IRemotePancakeIFOHelper(remotePancakeIFOHelper).isHarvestFromPancake();
        if (isClaimed) revert AlreadyClaimed();

        IPancakeStaking(pancakeStaking).harvestIFO(
            remotePancakeIFOHelper,
            _pancakeIFO,
            IRemotePancakeIFOHelper(remotePancakeIFOHelper).pid(),
            depositToken,
            offeringToken
        );

        IRemotePancakeIFOHelper(remotePancakeIFOHelper).updateStatus();

        emit RewardClaimedFor(remotePancakeIFOHelper, _pancakeIFO);
    }

    function setMultipliersForIFOHelper(
        address _remotePancakeIFOHelper,
        uint256[] calldata _multipliers
    ) external onlyOwner {
        IRemotePancakeIFOHelper(_remotePancakeIFOHelper).setMultipliers(_multipliers);
        emit MultiplierSet();
    }

    function setUserAmounts(
        address _remotePancakeIFOHelper,
        address[] calldata _accounts,
        uint8 _tokenId,
        uint256[] calldata _amounts
    ) external onlyOwner {
        if (_tokenId >= IFOConstantsLib.MAX_TOKEN_NUMBER) revert InvalidTokenId();

        if (_accounts.length > 0) {
            IRemotePancakeIFOHelper(_remotePancakeIFOHelper).setUserAmounts(_accounts, _tokenId, _amounts);
        }
        emit UserAmountsSet();
    }

    /* ============ Inernal Functions ============ */

    function _getVestingDetails(
        address _pancakeIFO,
        uint8 _pid
    ) internal view returns (bytes32 vestingScheduleId, uint256 vestedAmount) {
        vestingScheduleId = IIFOV8(_pancakeIFO).computeVestingScheduleIdForAddressAndPid(
            address(pancakeStaking),
            _pid
        );

        vestedAmount = IIFOV8(_pancakeIFO).computeReleasableAmount(vestingScheduleId);
    }

}