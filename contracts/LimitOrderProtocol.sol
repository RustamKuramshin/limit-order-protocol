// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./OrderMixin.sol";

/**
 * @title ##1inch Limit Order Protocol v4
 * @notice Limit order protocol provides two different order types
 * - Regular Limit Order
 * - RFQ Order
 *
 * Both types provide similar order-fulfilling functionality. The difference is that regular order offers more customization options and features, while RFQ order is extremely gas efficient but without ability to customize.
 *
 * Regular limit order additionally supports
 * - Execution predicates. Conditions for order execution are set with predicates. For example, expiration timestamp or block number, price for stop loss or take profit strategies.
 * - Callbacks to notify maker on order execution
 *
 * See [OrderMixin](OrderMixin.md) for more details.
 *
 * RFQ orders supports
 * - Expiration time
 * - Cancelation by order id
 * - Partial Fill (only once)
 *
 * See [OrderMixin](OrderMixin.md) for more details.
 */
contract LimitOrderProtocol is
    EIP712("1inch Limit Order Protocol", "4"),
    Ownable,
    Pausable,
    OrderMixin
{
    // State variables
    uint256 private orderExecutionLimit; // Maximum number of orders allowed
    uint256 private executedOrders;      // Counter for executed orders

    // Mapping to store individual execution limits for users
    mapping(address => uint256) private userOrderExecutionLimits;
    mapping(address => uint256) private userExecutedOrders;

    // solhint-disable-next-line no-empty-blocks
    constructor(IWETH _weth) OrderMixin(_weth) Ownable(msg.sender) {}

    /// @dev Returns the domain separator for the current chain (EIP-712)
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns(bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Pauses all the trading functionality in the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all the trading functionality in the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets a global limit on the number of orders that can be executed.
     * @dev Only the owner can set this limit. Setting it to 0 disables the limit.
     * @param _limit The maximum number of orders that can be executed.
     */
    function setOrderExecutionLimit(uint256 _limit) external onlyOwner {
        orderExecutionLimit = _limit;
    }

    /**
     * @notice Returns the current global limit on order executions.
     * @return The maximum number of orders that can be executed.
     */
    function getOrderExecutionLimit() external view returns (uint256) {
        return orderExecutionLimit;
    }

    /**
     * @notice Sets an individual limit on the number of orders a user can execute.
     * @dev Only the owner can set this limit for a specific user. Setting it to 0 disables the limit for that user.
     * @param user The address of the user.
     * @param limit The maximum number of orders the user can execute.
     */
    function setUserOrderExecutionLimit(address user, uint256 limit) external onlyOwner {
        require(user != address(0), "Invalid user address");
        userOrderExecutionLimits[user] = limit;
    }

    /**
     * @notice Returns the current individual limit on order executions for a user.
     * @param user The address of the user.
     * @return The maximum number of orders the user can execute.
     */
    function getUserOrderExecutionLimit(address user) external view returns (uint256) {
        return userOrderExecutionLimits[user];
    }

    /**
     * @notice Returns the number of orders executed by a specific user.
     * @param user The address of the user.
     * @return The number of orders executed by the user.
     */
    function getUserExecutedOrders(address user) external view returns (uint256) {
        return userExecutedOrders[user];
    }

    /**
     * @notice Internal function to track executed orders and enforce the limit.
     */
    function _trackOrderExecution() internal {
        if (orderExecutionLimit > 0) {
            require(executedOrders < orderExecutionLimit, "Order execution limit reached");
            executedOrders++;
        }
    }

    /**
     * @notice Internal function to track executed orders for a specific user and enforce their individual limit.
     * @param user The address of the user executing the order.
     */
    function _trackUserOrderExecution(address user) internal {
        uint256 userLimit = userOrderExecutionLimits[user];
        if (userLimit > 0) {
            require(userExecutedOrders[user] < userLimit, "User order execution limit reached");
            userExecutedOrders[user]++;
        }
    }

    /**
     * @notice Executes an order on behalf of a user, enforcing both global and individual limits.
     * @dev This is a placeholder for the actual order execution logic.
     * @param user The address of the user executing the order.
     */
    function executeOrder(address user) external {
        require(user != address(0), "Invalid user address");

        // Enforce global limit
        _trackOrderExecution();

        // Enforce individual user limit
        _trackUserOrderExecution(user);

        // Placeholder for actual order execution logic
        // ...
    }
}
