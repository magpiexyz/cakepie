// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./PancakeIFOHelper.sol";
import "../../interfaces/cakepie/IPancakeStaking.sol";
import "../../interfaces/cakepie/IPancakeIFOHelper.sol";
import "../../interfaces/pancakeswap/IIFO.sol";
import "../../interfaces/pancakeswap/IIFOV8.sol";

contract CakepieIFOManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /* ============ State Variables ============ */

    address public pancakeStaking;
    address public mCakeSV;
    address[] public pancakeIFOHelpersList;

    mapping(address => bool) public isIFOHelperValid;
    mapping(address => address) public ifoToHelper;
    address public treasuryAddress;
    address public mCakeLp;
    address public mCakeLpToken;
    address public smartCakeConvertor;
    uint256 public lpDepositLimit;

    /* ============ Events ============ */

    event IFOHelperCreated(
        address indexed pancakeIFOHelper,
        address indexed pancakeIFO,
        uint8 indexed pid
    );
    event RewardClaimedFor(address pancakeIFOHelper, address pancakeIFO);
    event DepositTransferredToIFO(
        address indexed pancakeIFOHelper,
        address indexed pancakeIFO,
        uint8 pid,
        address depositToken,
        address indexed depositFor,
        uint256 amount
    );
    event Harvested(
        address indexed pancakeIFOHelper,
        address indexed pancakeIFO,
        uint8 pid,
        address offeringToken,
        uint256 vestedAmount
    );
    event MultiplierSet(address indexed pancakeIFOHelper, uint256 multiplier, uint256 lpMultiplier);
    event LpDepositLimitSet(address indexed pancakeIFOHelper, uint256 lpDepositLimit);
    event TreasurySet(address indexed treasury);
    event MCakeLpSet(address indexed mCakeLp);
    event MCakeLpTokenSet(address indexed mCakeLpToken);
    event SmartCakeConvertorSet(address indexed smartCakeConvertor);
    
    /* ============ Errors ============ */

    error AlreadyClaimed();
    error OnlyIFOHelper();
    error InvalidMultiplier();
    error HelperExist();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __CakepieIFOManager_init(
        address _pancakeStaking,
        address _mCakeSV
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pancakeStaking = _pancakeStaking;
        mCakeSV = _mCakeSV;
    }

    modifier _onlyIFOHelper() {
        if (!isIFOHelperValid[msg.sender]) revert OnlyIFOHelper();
        _;
    }

    /* ============ External Read Functions ============ */

    function getPancakeIFOHelpers() external view returns (address[] memory) {
        return pancakeIFOHelpersList;
    }

    function getPancakeIFOHelpersCount() external view returns (uint256) {
        return pancakeIFOHelpersList.length;
    }

    /* ============ External Authorize Functions ============ */

    function transferDepositToIFO(
        address _pancakeIFO,
        uint8 _pid,
        address _depositToken,
        address _account,
        uint256 _amount
    ) external nonReentrant whenNotPaused _onlyIFOHelper {
        address _pancakeIFOHelper = ifoToHelper[_pancakeIFO];

        IPancakeStaking(pancakeStaking).depositIFO(
            _pancakeIFOHelper,
            _pancakeIFO,
            _pid,
            _depositToken,
            _account,
            _amount
        );
        emit DepositTransferredToIFO(
            _pancakeIFOHelper,
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
        address _pancakeIFOHelper = ifoToHelper[_pancakeIFO];

        (, address offeringToken) = IPancakeIFOHelper(_pancakeIFOHelper).getDepositNOfferingToken();
        (bytes32 _vestingScheduleId, uint256 _vestedAmount) = _getVestingDetails(_pancakeIFO, _pid);

        if (_vestedAmount > 0) {
            IPancakeStaking(pancakeStaking).releaseIFO(
                _pancakeIFOHelper,
                _pancakeIFO,
                _vestingScheduleId,
                offeringToken
            );
        }
        emit Harvested(_pancakeIFOHelper, _pancakeIFO, _pid, offeringToken, _vestedAmount);
    }

    /* ============ Admin Functions ============ */

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function pauseIFOHelper(address _pancakeIFO) external onlyOwner {
        address _pancakeIFOHelper = ifoToHelper[_pancakeIFO];

        IPancakeIFOHelper(_pancakeIFOHelper).pause();
    }

    function unpauseIFOHelper(address _pancakeIFO) external onlyOwner {
        address _pancakeIFOHelper = ifoToHelper[_pancakeIFO];

        IPancakeIFOHelper(_pancakeIFOHelper).unpause();
    }

    function createPancakeIFOHelper(address _pancakeIFO, uint8 _pid) external onlyOwner {
        if (ifoToHelper[_pancakeIFO] != address(0)) revert HelperExist();

        PancakeIFOHelper newIFOHelper = new PancakeIFOHelper(
            _pancakeIFO,
            _pid,
            mCakeSV,
            pancakeStaking,
            address(this),
            treasuryAddress,
            mCakeLp,
            mCakeLpToken,
            smartCakeConvertor
        );
        pancakeIFOHelpersList.push(address(newIFOHelper));
        isIFOHelperValid[address(newIFOHelper)] = true;
        ifoToHelper[_pancakeIFO] = address(newIFOHelper);
        emit IFOHelperCreated(address(newIFOHelper), _pancakeIFO, _pid);
    }

    function harvestIFOFromPancake(address _pancakeIFO) external onlyOwner {
        address _pancakeIFOHelper = ifoToHelper[_pancakeIFO];

        (address depositToken, address offeringToken) = IPancakeIFOHelper(_pancakeIFOHelper)
            .getDepositNOfferingToken();

        bool isClaimed = IPancakeIFOHelper(_pancakeIFOHelper).isHarvestFromPancake();

        if (isClaimed) revert AlreadyClaimed();

        IPancakeStaking(pancakeStaking).harvestIFO(
            _pancakeIFOHelper,
            _pancakeIFO,
            IPancakeIFOHelper(_pancakeIFOHelper).pid(),
            depositToken,
            offeringToken
        );

        IPancakeIFOHelper(_pancakeIFOHelper).updateStatus();

        emit RewardClaimedFor(_pancakeIFOHelper, _pancakeIFO);
    }

    function setMultiplierForIFOHelper(
        address _pancakeIFOHelper,
        uint256 _multiplier,
        uint256 _lpMultiplier
    ) external onlyOwner {
        if (_multiplier == 0 || _lpMultiplier == 0) revert InvalidMultiplier();
        IPancakeIFOHelper(_pancakeIFOHelper).setMultiplier(_multiplier, _lpMultiplier);
        emit MultiplierSet(_pancakeIFOHelper, _multiplier, _lpMultiplier);
    }

    function setLpDepositLimitAmountForIFOHelper(
        address _pancakeIFOHelper,
        uint256 _lpDepositLimit
    ) external onlyOwner {
        lpDepositLimit = _lpDepositLimit;
        IPancakeIFOHelper(_pancakeIFOHelper).setlpContributionLimit(_lpDepositLimit);
        emit LpDepositLimitSet(_pancakeIFOHelper, _lpDepositLimit);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasuryAddress = _treasury;
        emit TreasurySet(_treasury);
    }

    function setMCakeLp(address _mCakeLp) external onlyOwner {
        mCakeLp = _mCakeLp;
        emit MCakeLpSet(_mCakeLp);
    }

    function setLpToken(address _lpToken) external onlyOwner {
        mCakeLpToken = _lpToken;
        emit MCakeLpTokenSet(_lpToken);
    }

    function setSmartCakeConvertor(address _smartCakeConvertor) external onlyOwner {
        smartCakeConvertor = _smartCakeConvertor;
        emit SmartCakeConvertorSet(_smartCakeConvertor);
    }

    function _getVestingDetails(
        address _pancakeIFO,
        uint8 _pid
    ) internal view returns (bytes32 vestingScheduleId, uint256 vestedAmount) {
        if (pancakeIFOHelpersList[0] == ifoToHelper[_pancakeIFO]) {
            vestingScheduleId = IIFO(_pancakeIFO).computeVestingScheduleIdForAddressAndPid(
                address(pancakeStaking),
                _pid
            );
        } else {
            vestingScheduleId = IIFOV8(_pancakeIFO).computeVestingScheduleIdForAddressAndPid(
                address(pancakeStaking),
                _pid
            );
        }

        vestedAmount = IIFOV8(_pancakeIFO).computeReleasableAmount(vestingScheduleId);
    }

}
