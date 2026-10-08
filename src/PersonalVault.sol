// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PersonalVault
/// @author Faiz A
/// @notice A time-locked personal savings vault ("digital piggy bank"). Anyone can put ETH in, but only the
///         owner can take it out, and only once `unlockTime` has passed. The owner may extend the lock, but
///         can never shorten it.
/// @dev Design notes:
///      - There is no admin, no upgradeability, no pause and no rescue function: {withdraw} is the only way
///        ETH can leave, and it always pays the immutable `owner`.
///      - Accounting uses `address(this).balance` rather than an internal counter, so ETH that is force-sent
///        (e.g. via `selfdestruct` or as a coinbase recipient) is still recoverable by the owner.
///      - Time checks use `block.timestamp`. Validators can only skew it by a few seconds, which is
///        negligible for lock periods measured in minutes or longer.
contract PersonalVault {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The vault owner: the only account allowed to withdraw funds or extend the lock.
    /// @dev Set once to the deployer. `immutable` because ownership is never transferred; this also makes
    ///      every owner check an inline constant instead of an SLOAD.
    address public immutable owner;

    /// @notice Unix timestamp (in seconds) from which the owner may withdraw.
    /// @dev Never decreases: after construction it is only written by {extendLock}, and only to a later time.
    uint256 public unlockTime;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted whenever ETH enters the vault (constructor value, {deposit} or a plain transfer).
    /// @param sender The account that sent the ETH.
    /// @param amount The amount of ETH deposited, in wei.
    event Deposit(address indexed sender, uint256 amount);

    /// @notice Emitted when the owner withdraws the full vault balance.
    /// @param amount The amount of ETH withdrawn, in wei.
    /// @param timestamp The block timestamp at which the withdrawal happened.
    event Withdrawal(uint256 amount, uint256 timestamp);

    /// @notice Emitted when the owner pushes the unlock time further into the future.
    /// @param newUnlockTime The new unlock timestamp, in seconds.
    event LockExtended(uint256 newUnlockTime);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when withdrawing before `unlockTime`.
    error FundsLocked();

    /// @notice Thrown when a restricted function is called by an account other than `owner`.
    error NotOwner();

    /// @notice Thrown when an unlock time is not in the future, or an extension would not move it later.
    error InvalidUnlockTime();

    /// @notice Thrown when withdrawing from an empty vault.
    error NoBalance();

    /// @notice Thrown when a deposit carries no ETH.
    error ZeroDeposit();

    /// @notice Thrown when sending ETH to the owner fails (e.g. the owner is a contract that rejects ETH).
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts a function to the vault owner.
    /// @dev Uses `msg.sender`, never `tx.origin`, so the owner cannot be impersonated through phishing contracts.
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a vault owned by the deployer, locked until `_unlockTime`, optionally funded at once.
    /// @dev Uses the `InvalidUnlockTime` custom error instead of the brief's `require` string, as the brief's
    ///      security requirements ask for. Any ETH sent along is logged as a regular {Deposit}.
    /// @param _unlockTime Unix timestamp (in seconds) from which funds can be withdrawn. Must be in the future.
    constructor(uint256 _unlockTime) payable {
        if (_unlockTime <= block.timestamp) revert InvalidUnlockTime();
        owner = msg.sender;
        unlockTime = _unlockTime;
        if (msg.value > 0) emit Deposit(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                            ETH ENTRY POINTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Treats a plain ETH transfer as a deposit, so wallets can fund the vault without calldata.
    /// @dev There is deliberately no `fallback`: calls with unknown calldata revert instead of being accepted.
    receive() external payable {
        _deposit();
    }

    /// @notice Adds the attached ETH to the vault.
    /// @dev Open to any sender: deposits can only ever benefit the owner, and the indexed `sender` field of
    ///      {Deposit} identifies each depositor. Reverts with {ZeroDeposit} if no ETH is attached.
    function deposit() external payable {
        _deposit();
    }

    /*//////////////////////////////////////////////////////////////
                             OWNER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sends the entire vault balance to the owner once the lock has expired.
    /// @dev Follows Checks-Effects-Interactions: all checks happen and the event is emitted before the single
    ///      external call. Reentrancy is harmless here: the only recipient is the owner, there is no internal
    ///      accounting to corrupt, and by the time the owner's code runs the vault balance is already zero, so a
    ///      nested {withdraw} reverts with {NoBalance}. Uses `call` rather than `transfer`/`send` so owners that
    ///      are smart-contract wallets (which need more than 2300 gas) can still receive funds.
    ///      Reverts with {NotOwner}, {FundsLocked}, {NoBalance} or {TransferFailed}.
    function withdraw() external onlyOwner {
        if (block.timestamp < unlockTime) revert FundsLocked();
        uint256 amount = address(this).balance;
        if (amount == 0) revert NoBalance();

        emit Withdrawal(amount, block.timestamp);

        (bool ok,) = owner.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Moves the unlock time further into the future. The lock can never be shortened.
    /// @dev `newTime` must be later than both the current `unlockTime` and the current block timestamp; an
    ///      "extension" to a moment that has already passed would be meaningless. Calling this after the vault
    ///      has unlocked re-locks it, which lets the owner keep saving with the same vault.
    ///      Reverts with {NotOwner} or {InvalidUnlockTime}.
    /// @param newTime The new unlock timestamp, in seconds.
    function extendLock(uint256 newTime) external onlyOwner {
        if (newTime <= unlockTime || newTime <= block.timestamp) revert InvalidUnlockTime();
        unlockTime = newTime;
        emit LockExtended(newTime);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether the owner can withdraw now (ignoring whether the vault holds any ETH).
    /// @return True if `block.timestamp >= unlockTime`.
    function isUnlocked() external view returns (bool) {
        return block.timestamp >= unlockTime;
    }

    /// @notice Seconds remaining until the vault unlocks.
    /// @return The number of seconds until `unlockTime`, or 0 if it has already been reached.
    function timeUntilUnlock() external view returns (uint256) {
        uint256 unlockAt = unlockTime;
        if (block.timestamp >= unlockAt) return 0;
        unchecked {
            return unlockAt - block.timestamp; // cannot underflow: checked on the line above
        }
    }

    /// @notice The amount of ETH currently held by the vault.
    /// @return The vault balance, in wei.
    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Shared logic for {deposit} and {receive}: rejects empty deposits and logs the inflow.
    ///      No storage is written; the ETH itself is the state.
    function _deposit() internal {
        if (msg.value == 0) revert ZeroDeposit();
        emit Deposit(msg.sender, msg.value);
    }
}
