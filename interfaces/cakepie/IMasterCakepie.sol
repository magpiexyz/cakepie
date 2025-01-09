// SPDX-License-Identifier: MIT

pragma solidity =0.8.19;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IMasterCakepie {
    function poolLength() external view returns (uint256);

    function setPoolManagerStatus(address _address, bool _bool) external;

    function add(
        uint256 _allocPoint,
        address _stakingTokenToken,
        address _receiptToken,
        address _rewarder,
        bool _isV3Pool
    ) external;

    function set(
        address _stakingToken,
        uint256 _allocPoint,
        address _rewarder
    ) external;

    function createRewarder(
        address _stakingTokenToken,
        address mainRewardToken,
        address rewardDistributor
    ) external returns (address);

    // View function to see pending GMPs on frontend.
    function getPoolInfo(
        address token
    )
        external
        view
        returns (uint256 emission, uint256 allocpoint, uint256 sizeOfPool, uint256 totalPoint);

    function pendingTokens(
        address _stakingToken,
        address _user,
        address token
    )
        external
        view
        returns (
            uint256 _pendingGMP,
            address _bonusTokenAddress,
            string memory _bonusTokenSymbol,
            uint256 _pendingBonusToken
        );

    // function allPendingTokensWithBribe(
    //     address _stakingToken,
    //     address _user,
    //     IBribeRewardDistributor.Claim[] calldata _proof
    // )
    //     external
    //     view
    //     returns (
    //         uint256 pendingCakepie,
    //         address[] memory bonusTokenAddresses,
    //         string[] memory bonusTokenSymbols,
    //         uint256[] memory pendingBonusRewards
    //     );

    function allPendingTokens(
        address _stakingToken,
        address _user
    )
        external
        view
        returns (
            uint256 pendingCakepie,
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        );

    function massUpdatePools() external;

    function updatePool(address _stakingToken) external;

    function deposit(address _stakingToken, uint256 _amount) external;

    function depositFor(address _stakingToken, address _for, uint256 _amount) external;

    function withdraw(address _stakingToken, uint256 _amount) external;

    function beforeReceiptTokenTransfer(address _from, address _to, uint256 _amount) external;

    function afterReceiptTokenTransfer(address _from, address _to, uint256 _amount) external;

    function depositVlCakepieFor(uint256 _amount, address sender) external;

    function withdrawVlCakepieFor(uint256 _amount, address sender) external;

    function depositMCakeSVFor(uint256 _amount, address sender) external;

    function withdrawMCakeSVFor(uint256 _amount, address sender) external;

    function multiclaimFor(
        address[] calldata _stakingTokens,
        address[][] calldata _rewardTokens,
        address user_address
    ) external;

    function multiclaimMCake(
        address[] calldata _stakingTokens,
        address[][] calldata _rewardTokens,
        address user_address,
        uint256 _minRecMCake
    ) external;

    function multiclaimOnBehalf(
        address[] memory _stakingTokens,
        address[][] calldata _rewardTokens,
        address user_address
    ) external;

    function multiclaim(address[] calldata _stakingTokens) external;

    function emergencyWithdraw(address _stakingToken, address sender) external;

    function updateEmissionRate(uint256 _gmpPerSec) external;

    function stakingInfo(
        address _stakingToken,
        address _user
    ) external view returns (uint256 depositAmount, uint256 availableAmount);

    function totalTokenStaked(address _stakingToken) external view returns (uint256);
}
