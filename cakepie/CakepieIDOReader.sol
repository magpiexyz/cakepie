// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ICakeRush } from "../interfaces/cakepie/ICakepieIDOReader.sol";
import { IVlmgp } from "../interfaces/cakepie/ICakepieIDOReader.sol";
import { IBurnEventManager } from "../interfaces/cakepie/ICakepieIDOReader.sol";
import { ImCakeSV } from "../interfaces/cakepie/ICakepieIDOReader.sol";

/// @title CalepieIdoDataReader
/// @author Magpie Team

contract CakepieIdoDataReader is Initializable, OwnableUpgradeable {
    /* ============ State Variables ============ */

    address public mCake;
    address public mCakePoolReceiptToken;
    ICakeRush public cakeRush;
    IVlmgp public vlmgp;
    IBurnEventManager public burnEventManager;
    ImCakeSV public mCakeSv;

    /* ============ Structs ============ */

    struct CakepieIdoData {
        uint256 totalMCakeAmount;
        uint256 userTotalMCakeAmount;
        uint256 userStakedMCake;
        uint256 userLockedMCakeSV;
        uint256 userUnClaimedMCake;
        uint256 totalLockedMgp;
        uint256 userLockedMgp;
        uint256 totelBurnedMgpInGivenEvent;
        uint256 totelBurnedMgpInEventByUser;
    }

    /* ============ Constructor ============ */


    constructor() {
        _disableInitializers();
    }    

    function __CakepieIdoDataReader_init(
        address _mCake,
        address _mCakePoolReceiptToken,
        address _mCakeSV,
        address _cakeRush,
        address _vlMgp,
        address _burnEventManager
    ) public initializer {
        __Ownable_init();
        mCake = _mCake;
        mCakePoolReceiptToken = _mCakePoolReceiptToken;
        mCakeSv = ImCakeSV(_mCakeSV);
        cakeRush = ICakeRush(_cakeRush);
        vlmgp = IVlmgp(_vlMgp);
        burnEventManager = IBurnEventManager(_burnEventManager);
    }

    /* ============ External Getters ============ */

    function getUserMCakeHoldings(
        address _user
    ) external view returns (uint256 totalMCakeAmount, uint256 userMCakeAmount ) {
        if( mCake != address(0) && address(mCakePoolReceiptToken) != address(0) && address(mCakeSv) != address(0) && address(cakeRush) != address(0) )
        {
            ICakeRush.UserInfo memory userinfo = cakeRush.userInfos(_user);

            totalMCakeAmount = IERC20(mCake).totalSupply();

            uint256 _userStakedMCake = IERC20(mCakePoolReceiptToken).balanceOf(_user);
            uint256 _userLockedMCaseSV = mCakeSv.balanceOf(_user);
            uint256 _userUnClaimedMCake = userinfo.converted - cakeRush.claimedMCake(_user);
            userMCakeAmount = (((IERC20(mCake).balanceOf(_user) + _userStakedMCake) + _userLockedMCaseSV) + _userUnClaimedMCake);
        }
    }

    function getVlMgpHoldersData(
        address _user
    ) external view returns (uint256 totalLockedMgp, uint256 userLockedMgp) {
        if (address(vlmgp) != address(0)) {
            totalLockedMgp = vlmgp.totalLocked();
            userLockedMgp = vlmgp.getUserTotalLocked(_user);
        }
    }

    function getMgpBurnersData(
        uint256 _eventId,
        address _user
    )
        external
        view
        returns (uint256 totelBurnedMgpInEventByUser, uint256 totelBurnedMgpInGivenEvent)
    {
        if (address(burnEventManager) != address(0)) {
            totelBurnedMgpInEventByUser = burnEventManager.userMgpBurnAmountForEvent(
                _user,
                _eventId
            );
            (, , totelBurnedMgpInGivenEvent,, ) = burnEventManager.eventInfos(_eventId);
        }
    }

    function getCakepieIdoData(
        uint256 _mgpBurnEventId,
        address _user
    ) external view returns (CakepieIdoData memory) {
        CakepieIdoData memory cakepieIdoData;

        if( mCake != address(0) && address(mCakePoolReceiptToken) != address(0) && address(mCakeSv) != address(0) && address(cakeRush) != address(0) )
        {
            ICakeRush.UserInfo memory userinfo = cakeRush.userInfos(_user);

            cakepieIdoData.totalMCakeAmount = IERC20(mCake).totalSupply();
            cakepieIdoData.userStakedMCake = IERC20(mCakePoolReceiptToken).balanceOf(_user);
            cakepieIdoData.userLockedMCakeSV = mCakeSv.balanceOf(_user);
            cakepieIdoData.userUnClaimedMCake = userinfo.converted - cakeRush.claimedMCake(_user);

            cakepieIdoData.userTotalMCakeAmount = (((IERC20(mCake).balanceOf(_user) + cakepieIdoData.userStakedMCake) +  cakepieIdoData.userLockedMCakeSV) + cakepieIdoData.userUnClaimedMCake);
        }

        if (address(vlmgp) != address(0)) {
            cakepieIdoData.totalLockedMgp = vlmgp.totalLocked();
            cakepieIdoData.userLockedMgp = vlmgp.getUserTotalLocked(_user);
        }

        if (address(burnEventManager) != address(0)) {
            cakepieIdoData.totelBurnedMgpInEventByUser = burnEventManager.userMgpBurnAmountForEvent(
                _user,
                _mgpBurnEventId
            );
            (, , cakepieIdoData.totelBurnedMgpInGivenEvent,, ) = burnEventManager.eventInfos(
                _mgpBurnEventId
            );
        }

        return cakepieIdoData;
    }

    /* ============ Admin functions ============ */

    function config(
        address _mCake,
        address _mCakePoolReceiptToken,
        address _mCakeSV,
        address _cakeRush,
        address _vlMgp,
        address _burnEventManager
    ) external onlyOwner {
        mCake = _mCake;
        mCakePoolReceiptToken = _mCakePoolReceiptToken;
        mCakeSv = ImCakeSV(_mCakeSV);
        cakeRush = ICakeRush(_cakeRush);
        vlmgp = IVlmgp(_vlMgp);
        burnEventManager = IBurnEventManager(_burnEventManager);
    }
}
