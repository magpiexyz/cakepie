// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../../interfaces/pancakeswap/IIFOV8.sol";
import "../../interfaces/pancakeswap/IICake.sol";
import "../../interfaces/pancakeswap/IPancakeStableSwap.sol";
import "../../interfaces/pancakeswap/ISmartCakeConvertor.sol";
import "../../interfaces/cakepie/ICakepieIFOManager.sol";
import "../../interfaces/cakepie/ILocker.sol";

/// @title PancakeIFOHelper
/// @author Magpie Team
/// @notice This contract serves as the primary interface for users to engage with and participate in Initial Farm Offerings (IFO) on PancakeSwap through CakePie.
//         The PancakeIFOHelper is a shared utility accessible to CakePie users for participating in IFO events.
contract PancakeIFOHelper is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct Reward {
        uint256 rewardPerTokenStored;
        uint256 queuedTokens;
    }

    struct UserInfo {
        uint256 userRewardPerTokenPaid;
        uint256 userRewards;
    }

    //Reward Realated Storage variable
    mapping(address => uint256) public userDeposit;
    mapping(address => Reward) public rewards; // [rewardToken]
    mapping(address => bool) public isRewardToken;
    mapping(address => mapping(address => UserInfo)) public userInfos;
    mapping(address => uint256) public userLpContributions;

    address public immutable mCakeSV;
    address public immutable pancakeStaking;
    address public immutable cakepieIFOManager;
    address public immutable treasuryAddress;
    address public immutable mCakeLp;
    address public immutable mCakeLpToken;
    address public immutable smartCakeConvertor;
    address public immutable CAKE;
    address public immutable mCAKE;

    //IFO related
    IIFOV8 public immutable pancakeIFO;
    uint8 public immutable pid;

    uint256 public totalAmtDeposited;
    uint256 public multiplier;
    uint256 public lastClaimVestedTime;
    uint256 public mCakeLpMultiplier;
    uint256 public totalLpContributions;
    uint256 public lpContributionLimit;
    bool public isHarvestFromPancake;

    // Constants
    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant DEPOSIT_TOKEN_INDEX = 0;
    uint256 public constant OFFERING_TOKEN_INDEX = 1;
    uint256 public constant ICAKE_INDEX = 3;



    /* ============ Events ============ */

    event UserDeposit(address indexed user, uint256 amount);
    event UserClaimed(address indexed user, uint256 userReward, address rewardToken);
    event RewardAllocation(uint256 _reward, address indexed _token);
    event ZapMCakeLPToTreasury(
        address indexed user,
        uint256 amount,
        address indexed treasuryAddress,
        uint256 lpAmount
    );
    event TransferMCakeLPToTreasury(
        address indexed user,
        uint256 amount,
        address indexed treasuryAddress
    );

    /* ============ Errors ============ */

    error OnlyPancakeStaking();
    error DepositExceed();
    error UserMaxCapReached();
    error ClaimPhaseNotStarted();
    error ZeroDeposit();
    error AddressZero();
    error InvalidTokenLength();
    error InvalidTokenAddress();
    error SaleEnded();
    error SaleNotStarted();
    error IncorrectRatio();
    error IFOMaxCapReached();

    /* ============ Constructor ============ */

    constructor(
        address _pancakeIFO,
        uint8 _pid,
        address _mCakeSV,
        address _pancakeStaking,
        address _cakepieIFOManager,
        address _treasuryAddress,
        address _mCakeLp,
        address _mCakeLpToken,
        address _smartCakeConvertor
    ) {
        pancakeIFO = IIFOV8(_pancakeIFO);
        pid = _pid;
        mCakeSV = _mCakeSV;
        pancakeStaking = _pancakeStaking;
        cakepieIFOManager = _cakepieIFOManager;
        treasuryAddress = _treasuryAddress;
        mCakeLp = _mCakeLp;
        mCakeLpToken = _mCakeLpToken;
        smartCakeConvertor = _smartCakeConvertor;
        CAKE = ISmartCakeConvertor(smartCakeConvertor).cake();
        mCAKE = ISmartCakeConvertor(smartCakeConvertor).mCake();
    }

    /* ============ Modifiers ============ */

    modifier _onlyPancakeStaking() {
        if (msg.sender != address(pancakeStaking)) revert OnlyPancakeStaking();
        _;
    }

    modifier _checkIFOLimit() {
        if(totalAmtDeposited >= _getTotalLimit()) revert IFOMaxCapReached();
        _;
    }

    /* ============ External Functions ============ */

    function getDepositNOfferingToken()
        public
        view
        returns (address _depositToken, address _offeredToken)
    {
        _depositToken = IIFOV8(pancakeIFO).addresses(DEPOSIT_TOKEN_INDEX);
        _offeredToken = IIFOV8(pancakeIFO).addresses(OFFERING_TOKEN_INDEX);
    }

    function isSaleStarted() external view returns (bool) {
        return block.timestamp > IIFOV8(pancakeIFO).startTimestamp();
    }

    function isSaleEnded() external view returns (bool) {
        return block.timestamp > IIFOV8(pancakeIFO).endTimestamp();
    }

    function pendingOfferingToken(address _account) external view returns (uint256) {
        (, address offeringToken) = getDepositNOfferingToken();
        return earned(_account, offeringToken) + _calReward(_account);
    }

    function earned(address _account, address _token) public view returns (uint256) {
        return _earned(_account, _token, userDeposit[_account]);
    }

    function getMaxUserCap(address _for) external view returns (uint256) {
        return this.getUserCapForMCakeSV(_for) + this.getUserCapForMCakeLP(_for);
    }

    function getUserCapForMCakeSV(address _for) external view returns (uint256) {
        if (mCakeSV == address(0)) revert AddressZero();
        return (ILocker(mCakeSV).getUserTotalLocked(_for) * multiplier) / DENOMINATOR;
    }

    function getUserCapForMCakeLP(address _for) external view returns (uint256) {
        return (userLpContributions[_for] * mCakeLpMultiplier) / DENOMINATOR;
    }

    function queueNewTokens(
        uint256 _amountReward,
        address _rewardToken
    ) external _onlyPancakeStaking returns (bool) {
        if (!isRewardToken[_rewardToken]) {
            rewards[_rewardToken] = Reward({ rewardPerTokenStored: 0, queuedTokens: 0 });
            isRewardToken[_rewardToken] = true;
        }
        _provisionReward(_amountReward, _rewardToken);
        return true;
    }

    function participateInIFO(uint256 _amount) external nonReentrant whenNotPaused {
        if (!this.isSaleStarted()) revert SaleNotStarted();

        if (this.isSaleEnded()) revert SaleEnded();

        (address _depositToken, ) = getDepositNOfferingToken();

        totalAmtDeposited += _amount;

        uint256 totalLimit = _getTotalLimit();
        if (totalAmtDeposited > totalLimit) revert DepositExceed();

        userDeposit[msg.sender] += _amount;

        if (userDeposit[msg.sender] > this.getMaxUserCap(msg.sender)) revert UserMaxCapReached();

        ICakepieIFOManager(cakepieIFOManager).transferDepositToIFO(
            address(pancakeIFO),
            pid,
            _depositToken,
            msg.sender,
            _amount
        );

        emit UserDeposit(msg.sender, _amount);
    }

    function claim(address[] calldata _tokens) external nonReentrant whenNotPaused {
        (address depositToken, address offeringToken) = getDepositNOfferingToken();
        if (!isHarvestFromPancake) revert ClaimPhaseNotStarted();

        if (userDeposit[msg.sender] == 0) revert ZeroDeposit();

        if (_tokens.length == 0) revert InvalidTokenLength();

        for (uint8 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] != depositToken && _tokens[i] != offeringToken)
                revert InvalidTokenAddress();

            if (_tokens[i] == offeringToken) {
                _releaseIFOFromPancake();
            }

            _updateFor(msg.sender, _tokens[i]);

            uint256 claimableAmt = userInfos[_tokens[i]][msg.sender].userRewards;

            if (claimableAmt > 0) _sendReward(_tokens[i], msg.sender, claimableAmt);

            emit UserClaimed(msg.sender, claimableAmt, offeringToken);
        }
        
        lastClaimVestedTime = block.timestamp;
    }

    function getVestingVestedAndClaimed(
        address _account
    ) external view returns (uint256 userVesting, uint256 userVested, uint256 userClaimed) {
        (, address offeringToken) = getDepositNOfferingToken();

        bytes32 _vestingScheduleId = IIFOV8(pancakeIFO).computeVestingScheduleIdForAddressAndPid(
            address(pancakeStaking),
            pid
        );

        IIFOV8.VestingSchedule memory vestingScheduleInfo = IIFOV8(pancakeIFO).getVestingSchedule(
            _vestingScheduleId
        );

        uint256 userRewardPerTokenPaid = userInfos[offeringToken][_account].userRewardPerTokenPaid;

        userVesting = (userDeposit[_account] * vestingScheduleInfo.amountTotal) /
            (totalAmtDeposited);
        userVested = (userDeposit[_account] * vestingScheduleInfo.released) /
            (totalAmtDeposited);
        userClaimed = (userDeposit[_account] * userRewardPerTokenPaid) / (1e18);
    }

    function sendMCakeLPToTreasury(uint256 _amount) external nonReentrant whenNotPaused _checkIFOLimit {
        if (mCakeLpToken == address(0) || mCakeLp == address(0)) revert AddressZero();

        IERC20(mCakeLpToken).safeTransferFrom(msg.sender, address(this), _amount);

        _checkAndTransfer(_amount);

        emit TransferMCakeLPToTreasury(msg.sender, _amount, treasuryAddress);
    }

    function zapMCakeLPToTreasury(
        uint256 _amount,
        uint256 _minMCakeAmount,
        uint256 _minLpAmount,
        uint256 _convertRatio
    ) external nonReentrant whenNotPaused _checkIFOLimit {
        if (smartCakeConvertor == address(0) || mCakeLpToken == address(0) || mCakeLp == address(0))
            revert AddressZero();
        
        IERC20(CAKE).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 lpAmount = _zap(_amount, _minMCakeAmount, _minLpAmount, _convertRatio);
        _checkAndTransfer(lpAmount);

        emit ZapMCakeLPToTreasury(msg.sender, _amount, treasuryAddress, lpAmount);
    }

    // This function will be used from frontend to prevent front-running attacks
    function getZapExpectedAmounts(
        uint256 _amount,
        uint256 _convertRatio
    ) external view returns (uint256 expectedMCakeAmount, uint256 expectedLpAmount) {
        if (smartCakeConvertor == address(0) || mCakeLp == address(0)) revert AddressZero();
        if (_convertRatio > DENOMINATOR) revert IncorrectRatio();

        uint256 convertAmount = (_amount * _convertRatio) / DENOMINATOR;

        expectedMCakeAmount = ISmartCakeConvertor(smartCakeConvertor).estimateTotalConversion(
            convertAmount,
            0
        );
        expectedLpAmount = IPancakeStableSwap(mCakeLp).calc_token_amount(
            [_amount - convertAmount, expectedMCakeAmount],
            true
        );
    }

    function getCommitedAndCapForIFO() external view returns (uint256, uint256) {
        uint256 totalLimit = _getTotalLimit();
        return (totalAmtDeposited, totalLimit);
    }

    /* ============ Admin Functions ============ */

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function updateStatus() external onlyOwner {
        isHarvestFromPancake = true;
    }

    function setMultiplier(uint256 _multiplier, uint256 _lpMultiplier) external onlyOwner {
        multiplier = _multiplier;
        mCakeLpMultiplier = _lpMultiplier;
    }

    function setlpContributionLimit(uint256 _depositLimit) external onlyOwner {
        lpContributionLimit = _depositLimit;
    }

    /* ============ Internal Functions ============ */

    function _provisionReward(uint256 _amountReward, address _rewardToken) internal {
        uint256 balBefore = IERC20(_rewardToken).balanceOf(address(this));
        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _amountReward);
        _amountReward = IERC20(_rewardToken).balanceOf(address(this)) - balBefore;

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalAmtDeposited == 0) {
            rewardInfo.queuedTokens += _amountReward;
        } else {
            if (rewardInfo.queuedTokens > 0) {
                _amountReward += rewardInfo.queuedTokens;
                rewardInfo.queuedTokens = 0;
            }
            rewardInfo.rewardPerTokenStored =
                rewardInfo.rewardPerTokenStored +
                (_amountReward * 10 ** 18) /
                totalAmtDeposited;
        }
        emit RewardAllocation(_amountReward, _rewardToken);
    }

    function _earned(
        address _account,
        address _rewardToken,
        uint256 _userShare
    ) internal view returns (uint256) {
        UserInfo memory userInfo = userInfos[_rewardToken][_account];
        return
            ((_userShare * (rewardPerToken(_rewardToken) - userInfo.userRewardPerTokenPaid)) /
                (10 ** 18)) + userInfo.userRewards;
    }

    function _updateFor(address _account, address _token) internal {
        UserInfo storage userInfo = userInfos[_token][_account];
        if (userInfo.userRewardPerTokenPaid == rewardPerToken(_token)) return;

        userInfo.userRewards = earned(_account, _token);
        userInfo.userRewardPerTokenPaid = rewardPerToken(_token);
    }

    function _sendReward(address _token, address _to, uint256 _amount) internal {
        userInfos[_token][_to].userRewards = 0;
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function rewardPerToken(address _token) internal view returns (uint256) {
        return rewards[_token].rewardPerTokenStored;
    }

    function _calReward(address _account) internal view returns (uint256) {

        (uint256 vestingPercentage,,,) = _getVestingData();

        if (!isHarvestFromPancake || vestingPercentage == 0)
            return 0;

        bytes32 _vestingScheduleId = IIFOV8(pancakeIFO).computeVestingScheduleIdForAddressAndPid(
            address(pancakeStaking),
            pid
        );

        uint256 vestedAmount = IIFOV8(pancakeIFO).computeReleasableAmount(_vestingScheduleId);

        return (vestedAmount * userDeposit[_account]) / totalAmtDeposited;
    }

    function _zap(
        uint256 _amount,
        uint256 _minMCakeAmount,
        uint256 _minLpAmount,
        uint256 _convertRatio
    ) internal returns (uint256) {
        
        uint256 convertAmount = (_amount * _convertRatio) / DENOMINATOR; 

        IERC20(CAKE).safeApprove(smartCakeConvertor, 0);
        IERC20(CAKE).safeApprove(smartCakeConvertor, convertAmount);

        uint256 mCakeAmount = ISmartCakeConvertor(smartCakeConvertor).convert(
            convertAmount,
            0,
            _minMCakeAmount,
            3
        );

        uint256 balanceBefore = IERC20(mCakeLpToken).balanceOf(address(this));

        IERC20(CAKE).safeApprove(mCakeLp, 0);
        IERC20(CAKE).safeApprove(mCakeLp, _amount - convertAmount);

        IERC20(mCAKE).safeApprove(mCakeLp, 0);
        IERC20(mCAKE).safeApprove(mCakeLp, mCakeAmount);

        IPancakeStableSwap(mCakeLp).add_liquidity(
            [_amount - convertAmount, mCakeAmount],
            _minLpAmount
        );
        uint256 lpMintAmount = IERC20(mCakeLpToken).balanceOf(address(this)) - balanceBefore;
        return lpMintAmount;
    }

    function _checkAndTransfer(uint256 _amount) internal {
        totalLpContributions += _amount;
        if (totalLpContributions > lpContributionLimit) revert DepositExceed();
        
        userLpContributions[msg.sender] += _amount;
        IERC20(mCakeLpToken).safeTransfer(treasuryAddress, _amount);
    }

    function _releaseIFOFromPancake() internal {
        (uint256 vestingPercentage,,,) = _getVestingData();
        if (vestingPercentage != 0){
            ICakepieIFOManager(cakepieIFOManager).releaseIFOFromPancake(
                address(pancakeIFO),
                pid
            );
        }
    }

    function _getVestingData() view internal returns(uint256, uint256, uint256, uint256) {
        return IIFOV8(pancakeIFO).viewPoolVestingInformation(pid);
    }

    function _getTotalLimit() view internal returns(uint256) {
        address iCakeAddress = IIFOV8(pancakeIFO).addresses(ICAKE_INDEX);
        return IICake(iCakeAddress).getUserCreditWithIfoAddr(
            address(pancakeStaking),
            address(pancakeIFO)
        );
    }
}
