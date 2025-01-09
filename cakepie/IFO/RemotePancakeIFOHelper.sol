// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/pancakeswap/IIFOV8.sol";
import "../../interfaces/pancakeswap/IICake.sol";
import "../../libraries/cakepie/IFOConstantsLib.sol";
import "../../interfaces/cakepie/IRemoteCakepieIFOManager.sol";

/// @title PancakeIFOHelper
/// @author Magpie Team
/// @notice This contract serves as the primary interface for users to engage with and participate in Initial Farm Offerings (IFO) on PancakeSwap through CakePie.
//         The PancakeIFOHelper is a shared utility accessible to CakePie users for participating in IFO events.
contract RemotePancakeIFOHelper is Ownable, ReentrancyGuard, Pausable {
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
    mapping(bytes32 => uint256) public userAmounts; // Mapping of user address and token ID hash to the associated amount
    mapping(address => mapping(address => UserInfo)) public userInfos;

    //IFO related
    IIFOV8 public immutable pancakeIFO;
    uint8 public immutable pid;

    address public immutable pancakeStaking;
    address public immutable cakepieIFOManager;
    
    uint256 public totalAmtDeposited;
    uint256 public constant DENOMINATOR = 10000;

    uint256 public lastClaimVestedTime;
    bool public isHarvestFromPancake;

    // [0] mCakeSVMultiplier [1] mCakeLPMultiplier [2] ckpMcakeLPMultiplier [3] vlCKPMultiplier
    uint256[4] public multipliers;

    /* ============ Events ============ */

    event UserDeposit(address indexed user, uint256 amount);
    event UserClaimed(address indexed user, uint256 userReward, address rewardToken);
    event RewardAllocation(uint256 _reward, address indexed _token);
    event MultiplierSet(uint256 tokenId, uint256 multiplier);
    event UserAmountSet(address indexed account, uint256 tokenId, uint256 amount);

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
    error LengthMismatch();

    /* ============ Constructor ============ */

    constructor(
        address _pancakeIFO,
        uint8 _pid,
        address _pancakeStaking,
        address _cakepieIFOManager
    ) {
        pancakeIFO = IIFOV8(_pancakeIFO);
        pid = _pid;
        pancakeStaking = _pancakeStaking;
        cakepieIFOManager = _cakepieIFOManager;
    }

    /* ============ Modifiers ============ */

    modifier _onlyPancakeStaking() {
        if (msg.sender != address(pancakeStaking)) revert OnlyPancakeStaking();
        _;
    }

    /* ============ External Functions ============ */

    function getDepositNOfferingToken() public view returns (address _depositToken, address _offeredToken) {
        _depositToken = IIFOV8(pancakeIFO).addresses(IFOConstantsLib.DEPOSIT_TOKEN_INDEX);
        _offeredToken = IIFOV8(pancakeIFO).addresses(IFOConstantsLib.OFFERING_TOKEN_INDEX);
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

    function earned(
        address _account,
        address _token
    ) public view returns (uint256) {
        return _earned(_account, _token, userDeposit[_account]);
    }

    function getMaxUserCap(address _for) external view returns (uint256) {
        uint256 maxUserCap;
        for (uint8 i; i < IFOConstantsLib.MAX_TOKEN_NUMBER; ++i) {
            maxUserCap += (userAmounts[this.getKey(_for, i)] * multipliers[i]) / DENOMINATOR;
        }
        return maxUserCap;
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

    function participateInIFO(
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        if (!this.isSaleStarted()) revert SaleNotStarted();

        if (this.isSaleEnded()) revert SaleEnded();

        (address _depsoitToken, ) = getDepositNOfferingToken();

        totalAmtDeposited = totalAmtDeposited + _amount;

        uint256 totalLimit = _getTotalLimit();
        if (totalAmtDeposited > totalLimit) revert DepositExceed();

        userDeposit[msg.sender] += _amount;

        if (userDeposit[msg.sender] > this.getMaxUserCap(msg.sender)) revert UserMaxCapReached();

        IRemoteCakepieIFOManager(cakepieIFOManager).transferDepositToIFO(
            address(pancakeIFO),
            pid,
            _depsoitToken,
            msg.sender,
            _amount
        );

        emit UserDeposit(msg.sender, _amount);
    }

    function claim(address[] calldata _tokens) external nonReentrant whenNotPaused {
        (address depositToken, address offeringToken) = getDepositNOfferingToken();

        if (!isHarvestFromPancake) revert ClaimPhaseNotStarted();

        if (userDeposit[msg.sender] == 0) revert ZeroDeposit();

        if (_tokens.length == 0 || _tokens.length > 2) revert InvalidTokenLength();

        for (uint8 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] != depositToken && _tokens[i] != offeringToken) revert InvalidTokenAddress();

            lastClaimVestedTime = block.timestamp;
            if (_tokens[i] == offeringToken) {
                IRemoteCakepieIFOManager(cakepieIFOManager).releaseIFOFromPancake(
                    address(pancakeIFO),
                    pid
                );
            }

            _updateFor(msg.sender, _tokens[i]);

            uint256 claimableAmt = userInfos[_tokens[i]][msg.sender].userRewards;
            if (claimableAmt > 0) {
                _sendReward(_tokens[i], msg.sender, claimableAmt);
            }

            emit UserClaimed(msg.sender, claimableAmt, offeringToken);
        }
    }

    function getCommitedAndCapForIFO() external view returns (uint256, uint256) {
        uint256 totalLimit = _getTotalLimit();
        return (totalAmtDeposited, totalLimit);
    }

    function getKey(
        address _account,
        uint8 _tokenId
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _tokenId));
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

    function setMultipliers(
        uint256[] calldata _multipliers
    ) external onlyOwner {
        uint256 multipliersLength = _multipliers.length; 
        if (multipliersLength != IFOConstantsLib.MAX_TOKEN_NUMBER) revert LengthMismatch();

        for (uint256 i; i < multipliersLength; ++i){
            multipliers[i] = _multipliers[i];
            emit MultiplierSet(i, multipliers[i]);
        }
    }

    function setUserAmounts(
        address[] calldata _accounts,
        uint8 _tokenId,
        uint256[] calldata _amounts
    ) external onlyOwner {
        uint256 accountsLength = _accounts.length;
        if (accountsLength != _amounts.length) revert LengthMismatch();
    
        for (uint256 i; i < accountsLength; ++i) {
            userAmounts[this.getKey(_accounts[i], _tokenId)] = _amounts[i];
            emit UserAmountSet(_accounts[i], _tokenId, _amounts[i]);
        }
    }

    /* ============ Internal Functions ============ */

    function _provisionReward(
        uint256 _amountReward,
        address _rewardToken
    ) internal {
        uint256 balBefore = IERC20(_rewardToken).balanceOf(address(this));
        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _amountReward);
        _amountReward = IERC20(_rewardToken).balanceOf(address(this)) - balBefore;

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalAmtDeposited == 0) {
            rewardInfo.queuedTokens = rewardInfo.queuedTokens + _amountReward;
        } else {
            if (rewardInfo.queuedTokens > 0) {
                _amountReward = _amountReward + rewardInfo.queuedTokens;
                rewardInfo.queuedTokens = 0;
            }
            rewardInfo.rewardPerTokenStored = rewardInfo.rewardPerTokenStored +
                (_amountReward * 10**18) / totalAmtDeposited;
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
            ((_userShare * (_rewardPerToken(_rewardToken) - userInfo.userRewardPerTokenPaid)) /
                (10 ** 18)) + userInfo.userRewards;
    }

    function _updateFor(
        address _account,
        address _token
    ) internal {
        UserInfo storage userInfo = userInfos[_token][_account];
        if (userInfo.userRewardPerTokenPaid == _rewardPerToken(_token)) return;

        userInfo.userRewards = earned(_account, _token);
        userInfo.userRewardPerTokenPaid = _rewardPerToken(_token);
    }

    function _sendReward(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        userInfos[_token][_to].userRewards = 0;
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _rewardPerToken(address _token) internal view returns (uint256) {
        return rewards[_token].rewardPerTokenStored;
    }

    function _calReward(address _account) internal view returns (uint256) {
        if (!isHarvestFromPancake)
            return 0;

        bytes32 _vestingScheduleId = IIFOV8(pancakeIFO).computeVestingScheduleIdForAddressAndPid(
            address(pancakeStaking),
            pid
        );

        uint256 vestedAmount = IIFOV8(pancakeIFO).computeReleasableAmount(_vestingScheduleId);

        return (vestedAmount * userDeposit[_account]) / totalAmtDeposited;
    }

    function _getTotalLimit() internal view returns(uint256) {
        address iCakeAddress = IIFOV8(pancakeIFO).addresses(IFOConstantsLib.ICAKE_INDEX);
        return IICake(iCakeAddress).getUserCreditWithIfoAddr(
            address(pancakeStaking),
            address(pancakeIFO)
        );
       
    }
}