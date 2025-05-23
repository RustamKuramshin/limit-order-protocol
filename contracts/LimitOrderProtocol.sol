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

    // State variable to store the fee percentage (in basis points, e.g., 100 = 1%)
    uint256 private executionFeeBps;
    address private feeRecipient;

    // State variable to store the reward amount for executors
    uint256 private executorReward;

    // State variable to store the cashback percentage (in basis points, e.g., 100 = 1%)
    uint256 private cashbackBps;

    // State variables for dynamic fee adjustment
    struct FeeBracket {
        uint256 minAmount; // Минимальная сумма ордера для применения этого уровня комиссии
        uint256 feeBps;    // Комиссия в базисных пунктах (bps)
    }

    FeeBracket[] private feeBrackets;

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
     * @notice Sets the fee percentage for order execution.
     * @dev Only the owner can set this fee. Fee is in basis points (1% = 100 bps).
     * @param _feeBps The fee percentage in basis points.
     */
    function setExecutionFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "Fee too high"); // Max fee is 10%
        executionFeeBps = _feeBps;
    }

    /**
     * @notice Sets the recipient address for the execution fees.
     * @dev Only the owner can set this address.
     * @param _recipient The address to receive the fees.
     */
    function setFeeRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Invalid recipient address");
        feeRecipient = _recipient;
    }

    /**
     * @notice Returns the current execution fee percentage.
     * @return The fee percentage in basis points.
     */
    function getExecutionFee() external view returns (uint256) {
        return executionFeeBps;
    }

    /**
     * @notice Sets the reward amount for executors.
     * @dev Only the owner can set this value.
     * @param _reward The reward amount in wei.
     */
    function setExecutorReward(uint256 _reward) external onlyOwner {
        executorReward = _reward;
    }

    /**
     * @notice Returns the current reward amount for executors.
     * @return The reward amount in wei.
     */
    function getExecutorReward() external view returns (uint256) {
        return executorReward;
    }

    /**
     * @notice Sets the cashback percentage for users.
     * @dev Only the owner can set this value. Cashback is in basis points (1% = 100 bps).
     * @param _cashbackBps The cashback percentage in basis points.
     */
    function setCashback(uint256 _cashbackBps) external onlyOwner {
        require(_cashbackBps <= 500, "Cashback too high"); // Максимальный кэшбэк — 5%
        cashbackBps = _cashbackBps;
    }

    /**
     * @notice Returns the current cashback percentage.
     * @return The cashback percentage in basis points.
     */
    function getCashback() external view returns (uint256) {
        return cashbackBps;
    }

    /**
     * @notice Adds a new fee bracket for dynamic fee adjustment.
     * @dev Only the owner can add fee brackets. Fee brackets should be added in ascending order of `minAmount`.
     * @param minAmount The minimum order amount for this fee bracket.
     * @param feeBps The fee percentage in basis points for this bracket.
     */
    function addFeeBracket(uint256 minAmount, uint256 feeBps) external onlyOwner {
        require(feeBps <= 1000, "Fee too high"); // Максимальная комиссия — 10%
        if (feeBrackets.length > 0) {
            require(minAmount > feeBrackets[feeBrackets.length - 1].minAmount, "Brackets must be in ascending order");
        }
        feeBrackets.push(FeeBracket(minAmount, feeBps));
    }

    /**
     * @notice Removes the last fee bracket.
     * @dev Only the owner can remove fee brackets.
     */
    function removeLastFeeBracket() external onlyOwner {
        require(feeBrackets.length > 0, "No fee brackets to remove");
        feeBrackets.pop();
    }

    /**
     * @notice Returns the fee percentage for a given order amount.
     * @param amount The order amount.
     * @return The fee percentage in basis points.
     */
    function getFeeForAmount(uint256 amount) public view returns (uint256) {
        for (uint256 i = feeBrackets.length; i > 0; i--) {
            if (amount >= feeBrackets[i - 1].minAmount) {
                return feeBrackets[i - 1].feeBps;
            }
        }
        return 0; // Если сумма ордера меньше минимального порога, комиссия равна 0
    }

    /**
     * @notice Executes an order with dynamic fee adjustment.
     * @param user The address of the user executing the order.
     * @param amount The amount of the order.
     */
    function executeOrderWithDynamicFee(address user, uint256 amount) external payable {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Order amount must be greater than zero");

        // Получаем комиссию для указанного объема
        uint256 feeBps = getFeeForAmount(amount);
        uint256 fee = (amount * feeBps) / 10000;

        require(msg.value >= fee, "Insufficient fee");

        // Переводим комиссию получателю
        payable(feeRecipient).transfer(fee);

        // Логика выполнения ордера
        _trackOrderExecution();
        _trackUserOrderExecution(user);

        // Placeholder for actual order execution logic
        // ...
    }

    /**
     * @notice Executes an order with cashback for the user.
     * @param user The address of the user executing the order.
     * @param amount The amount of the order.
     */
    function executeOrderWithCashback(address user, uint256 amount) external payable {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Order amount must be greater than zero");

        // Calculate the fee
        uint256 feeBps = getFeeForAmount(amount);
        uint256 fee = (amount * feeBps) / 10000;
        require(msg.value >= fee, "Insufficient fee");

        // Calculate the cashback
        uint256 cashback = (fee * cashbackBps) / 10000;

        // Transfer the fee to the recipient
        payable(feeRecipient).transfer(fee - cashback);

        // Transfer the cashback to the user
        payable(user).transfer(cashback);

        // Enforce global and individual limits
        _trackOrderExecution();
        _trackUserOrderExecution(user);

        // Placeholder for actual order execution logic
        // ...
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

    /**
     * @notice Executes an order and deducts the execution fee.
     * @param user The address of the user executing the order.
     */
    function executeOrderWithFee(address user) external payable {
        require(user != address(0), "Invalid user address");

        // Calculate the fee
        uint256 fee = (msg.value * executionFeeBps) / 10000;
        require(msg.value >= fee, "Insufficient fee");

        // Transfer the fee to the recipient
        payable(feeRecipient).transfer(fee);

        // Enforce global and individual limits
        _trackOrderExecution();
        _trackUserOrderExecution(user);

        // Placeholder for actual order execution logic
        // ...
    }

    /**
     * @notice Executes an order and rewards the executor.
     * @param user The address of the user executing the order.
     */
    function executeOrderWithReward(address user) external {
        require(user != address(0), "Invalid user address");

        // Enforce global and individual limits
        _trackOrderExecution();
        _trackUserOrderExecution(user);

        // Reward the executor
        payable(msg.sender).transfer(executorReward);

        // Placeholder for actual order execution logic
        // ...
    }
}
