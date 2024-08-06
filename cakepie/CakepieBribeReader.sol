pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/cakepieReader/IPancakeVoteManagerReader.sol";
import "../interfaces/cakepieReader/ICakepieBribeManagerReader.sol";
import "../interfaces/pancakeswap/IVeCake.sol";

/// @title MagpieReader for Arbitrum
/// @author Magpie Team

contract CakepieBribeReader is Initializable, OwnableUpgradeable {
    struct ERC20TokenInfo {
        address tokenAddress;
        string symbol;
        uint256 decimals;
        bool isNative;
    }

    struct BribeConfig {
        address cakepieBribeManager;
        address cakepieVoteManager;
    }

    struct BribeInfo {
        uint256 userTotalVotedInVlCakepie;
        uint256 totalVlCakepieInVote;
        uint256 lastCastTime;
        uint256 userVotable;
        uint256 cakepieVeCake;
        uint256 totalVeCake;
        uint256 currentVotePeriodEndTime;
        uint256 currentBribePeriodEndTime;
        ApprovedToken[] approvedTokens;
        BribePool[] pools;
    }

    struct ApprovedToken {
        address token;
        ERC20TokenInfo tokenInfo;
        uint256 balanceOf;
        uint256 addBribeAllowance;
    }

    struct BribePool {
        address pool;
        bytes32 gaugeHash;
        uint256 chainId;
        uint256 gaugeType;
        uint256 totalVoteInVlCakepie;
        uint256 userVotedForPoolInVlCakepie;
        bool isActive;
        Bribe[] currentVoterBribes;
        Bribe[] currentAccumulatedBribes;
    }

    struct Bribe {
        address token;
        ERC20TokenInfo tokenInfo;
        uint256 amount;
    }

    ICakepieBribeManagerReader public cakepieBribeManager;
    IPancakeVoteManagerReader public cakepieVoteManager;

    /* ============ State Variables ============ */

    function __CakepieBribeReader_init() public initializer {
        __Ownable_init();
    }

    function getBribeInfo(address account) external view returns (BribeInfo memory) {
        BribeInfo memory info;
        info.currentVotePeriodEndTime = cakepieVoteManager.getCurrentPeriodEndTime();
        info.lastCastTime = cakepieVoteManager.lastCastTime();
        info.totalVlCakepieInVote = cakepieVoteManager.totalVlCakepieInVote();
        info.cakepieVeCake = cakepieVoteManager.totalVotes();
        info.totalVeCake = IVeCake(cakepieVoteManager.veCake()).totalSupply();

        address[] memory approvedTokensAddress = cakepieBribeManager.getApprovedTokens();
        ApprovedToken[] memory approvedTokens = new ApprovedToken[](approvedTokensAddress.length);
        for (uint256 i = 0; i < approvedTokensAddress.length; i++) {
            ApprovedToken memory approvedToken;
            approvedToken.token = approvedTokensAddress[i];
            approvedToken.tokenInfo = getERC20TokenInfo(approvedTokensAddress[i]);
            if (account != address(0)) {
                approvedToken.balanceOf = ERC20(approvedToken.token).balanceOf(account);
                approvedToken.addBribeAllowance = ERC20(approvedToken.token).allowance(
                    account,
                    address(cakepieBribeManager)
                );
            }
            approvedTokens[i] = approvedToken;
        }
        info.approvedTokens = approvedTokens;

        address[] memory poolList = cakepieVoteManager.getAllPools();
        BribePool[] memory pools = new BribePool[](poolList.length);
        for (uint256 i = 0; i < poolList.length; ++i) {
            pools[i] = getBribePoolInfo(poolList[i]);
        }
        info.pools = pools;
        if (account != address(0)) {
            info.userVotable = cakepieVoteManager.getUserVotable(account);
            info.userTotalVotedInVlCakepie = cakepieVoteManager.userTotalVotedInVlCakepie(account);
            uint256[] memory userVoted = cakepieVoteManager.getUserVoteForPoolsInVlCakepie(
                poolList,
                account
            );
            for (uint256 i = 0; i < poolList.length; ++i) {
                pools[i].userVotedForPoolInVlCakepie = userVoted[i];
            }
        }

        info.currentBribePeriodEndTime = cakepieBribeManager.getCurrentPeriodEndTime();
        _fillInBribeInAllPools(info.currentBribePeriodEndTime, poolList.length, pools, true);
        _fillInBribeInAllPools(
            info.currentBribePeriodEndTime - 86400 * 14,
            poolList.length,
            pools,
            false
        );

        return info;
    }

    function getERC20TokenInfo(address token) public view returns (ERC20TokenInfo memory) {
        ERC20TokenInfo memory tokenInfo;
        if (token == address(0)) return tokenInfo;
        tokenInfo.tokenAddress = token;
        if (token == address(1)) {
            tokenInfo.symbol = "BNB";
            tokenInfo.decimals = 18;
            return tokenInfo;
        }
        ERC20 tokenContract = ERC20(token);
        tokenInfo.symbol = tokenContract.symbol();
        tokenInfo.decimals = tokenContract.decimals();
        return tokenInfo;
    }

    function getBribePoolInfo(address pool) public view returns (BribePool memory) {
        BribePool memory bribePool;

        (
            bribePool.gaugeHash,
            bribePool.pool,
            bribePool.gaugeType,
            bribePool.chainId,
            bribePool.isActive,
            bribePool.totalVoteInVlCakepie
        ) = cakepieVoteManager.poolInfo(pool);

        return bribePool;
    }

    function getBribeConfig() external view returns (BribeConfig memory) {
        BribeConfig memory bribeConfig;
        bribeConfig.cakepieBribeManager = address(cakepieBribeManager);
        bribeConfig.cakepieVoteManager = address(cakepieVoteManager);
        return bribeConfig;
    }

    /* ============ Internal Functions ============ */

    function _fillInBribeInAllPools(
        uint256 _epoch,
        uint256 _poolCount,
        BribePool[] memory _pools,
        bool _isCurrentEpoch
    ) internal view {
        ICakepieBribeManagerReader.IBribe[][] memory bribes = cakepieBribeManager
            .getBribesInAllPools(_epoch);

        for (uint256 i = 0; i < _poolCount; ++i) {
            uint256 size = bribes[i].length;
            Bribe[] memory poolBribe = new Bribe[](size);
            for (uint256 m = 0; m < size; ++m) {
                address token = bribes[i][m]._token;
                uint256 amount = bribes[i][m]._amount;
                Bribe memory temp;
                temp.token = token;
                temp.amount = amount;
                temp.tokenInfo = getERC20TokenInfo(token);
                poolBribe[m] = temp;
            }
            if (_isCurrentEpoch) _pools[i].currentAccumulatedBribes = poolBribe;
            else _pools[i].currentVoterBribes = poolBribe;
        }
    }

    /* ============ Admin Functions ============ */

    function config(address _cakepieBribeManager, address _cakepieVoteManager) external onlyOwner {
        cakepieBribeManager = ICakepieBribeManagerReader(_cakepieBribeManager);
        cakepieVoteManager = IPancakeVoteManagerReader(_cakepieVoteManager);
    }
}
