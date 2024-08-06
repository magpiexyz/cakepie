// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CakepieReceiptToken } from "../../cakepie/tokens/CakepieReceiptToken.sol";
import { BaseRewardPoolV3 } from "../../cakepie/rewards/BaseRewardPoolV3.sol";

library ERC20FactoryLib {

    function createReceipt(address _stakeToken, address _masterCakepie, address _pancakeStaking, string memory _name, string memory _symbol) public returns(address)
    {
        ERC20 token = new CakepieReceiptToken(_stakeToken, _masterCakepie, _pancakeStaking, _name, _symbol);
        return address(token);
    }

    function createRewarder(
        address _receiptToken,
        address mainRewardToken,
        address _masterCakepie,
        address _rewardQueuer
    ) external returns (address) {
        BaseRewardPoolV3 _rewarder = new BaseRewardPoolV3(
            _receiptToken,
            mainRewardToken,
            _masterCakepie,
            _rewardQueuer
        );
        return address(_rewarder);
    }    
}