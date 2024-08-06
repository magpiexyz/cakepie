// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IPancakeStaking } from "../../interfaces/cakepie/IPancakeStaking.sol";

library PancakeStakingHelper {

    struct PoolRegistrationParam {
        address _lpAddress;  // can be V3, V2 or AML Wrapper
        uint256 _allocPoints;
        string name;
        string symbol;
    }
}