// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { IDelegationContract } from "./interfaces/IDelegationContract.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC5313 } from "@openzeppelin/contracts/interfaces/IERC5313.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title DelegationContract
/// @notice Minimal, non-upgradeable delegation contract implementing the Execution Delegation
///         Framework (EDF): one owner, one active delegate. The owner assigns and revokes
///         the delegate; the delegate dispatches calls via execute() (push) or
///         signs messages verified via ERC-1271 isValidSignature (pull).
/// @dev The owner can never execute() or sign on the contract's behalf. Delegate assignment
///      is cooldown-gated so a compromised-owner reassignment is visible before it takes
///      effect; revocation and termination are immediate.
contract DelegationContract is IDelegationContract, IERC1271, IERC5313, IERC165 {
    /// @notice EIP-1271 magic value returned on valid signature
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    /// @notice Value returned on invalid signature
    bytes4 internal constant EIP1271_INVALID = 0xffffffff;

    /// @notice The owner address. Fixed for the contract's lifetime.
    address internal immutable OWNER;

    /// @notice Seconds a reassigned delegate waits before becoming effective. May be 0.
    uint256 internal immutable COOLDOWN;

    /// @notice The currently effective delegate, once any matured pending assignment is settled.
    address private _currentDelegate;

    /// @notice The scheduled (not-yet-effective) delegate, or address(0) if none is pending.
    address private _pendingDelegate;

    /// @notice Timestamp at which `_pendingDelegate` becomes effective, or 0 if none is pending.
    uint256 private _pendingActiveFrom;

    /// @notice Whether the contract has been irreversibly terminated.
    bool private _terminated;

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier notTerminated() {
        _notTerminated();
        _;
    }

    /// @notice Creates a new DelegationContract.
    /// @param owner_    The contract's owner, fixed for the lifetime of the contract.
    /// @param delegate_ Initial active delegate, effective immediately. Pass address(0) for none.
    /// @param cooldown_ Seconds a reassigned delegate waits before becoming effective. May be 0.
    constructor(address owner_, address delegate_, uint256 cooldown_) {
        if (owner_ == address(0)) revert ZeroAddress();
        if (delegate_ == owner_) revert OwnerCannotBeDelegate();

        OWNER = owner_;
        COOLDOWN = cooldown_;
        _currentDelegate = delegate_;
    }

    /// @inheritdoc IDelegationContract
    function assignDelegate(address delegate) external onlyOwner notTerminated {
        if (delegate == address(0)) revert ZeroAddress();
        if (delegate == OWNER) revert OwnerCannotBeDelegate();

        _settle();

        uint256 activeFrom = block.timestamp + COOLDOWN;
        _pendingDelegate = delegate;
        _pendingActiveFrom = activeFrom;

        emit DelegateNominated(delegate, activeFrom);
    }

    /// @inheritdoc IDelegationContract
    function revokeDelegate() external onlyOwner notTerminated {
        address revoked = getDelegate();

        _currentDelegate = address(0);
        _pendingDelegate = address(0);
        _pendingActiveFrom = 0;

        emit DelegateRevoked(revoked);
    }

    /// @inheritdoc IDelegationContract
    function terminate() external onlyOwner notTerminated {
        _terminated = true;
        _currentDelegate = address(0);
        _pendingDelegate = address(0);
        _pendingActiveFrom = 0;

        emit Terminated();
    }

    /// @inheritdoc IDelegationContract
    /// @dev Only the effective delegate can execute calls through this contract.
    ///      Uses a regular call so that msg.sender to the target is this contract's address.
    ///      This contract has no receive()/fallback and never refunds any value: it cannot
    ///      passively accept ETH, so if the target tries to send value back to it (e.g. a fee
    ///      refund), that transfer fails and execute() reverts atomically. Integrations that
    ///      refund unspent value (e.g. an overpaid protocol fee) must route the refund directly
    ///      to the delegate's own address rather than to this contract.
    function execute(address target, bytes calldata data) external payable notTerminated returns (bytes memory result) {
        if (msg.sender != getDelegate()) revert NotDelegate();
        if (target == address(0)) revert ZeroAddress();
        if (target == address(this)) revert CannotCallSelf();
        if (target.code.length == 0) revert TargetNotContract();

        bool success;
        // solhint-disable-next-line avoid-low-level-calls
        (success, result) = target.call{ value: msg.value }(data);

        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly ("memory-safe") {
                // Bubble up the revert reason from the target contract
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @inheritdoc IDelegationContract
    /// @dev Validates that the signature was created by the currently effective delegate.
    // solhint-disable-next-line gas-calldata-parameters
    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view override(IDelegationContract, IERC1271) returns (bytes4 magicValue) {
        address delegate = getDelegate();
        if (delegate != address(0) && SignatureChecker.isValidSignatureNow(delegate, hash, signature)) {
            return EIP1271_MAGIC_VALUE;
        }
        return EIP1271_INVALID;
    }

    /// @inheritdoc IDelegationContract
    function owner() external view override(IDelegationContract, IERC5313) returns (address) {
        return OWNER;
    }

    /// @inheritdoc IDelegationContract
    function getPendingDelegate() external view returns (address delegate, uint256 activeFrom) {
        if (_pendingActiveFrom != 0 && block.timestamp < _pendingActiveFrom) {
            return (_pendingDelegate, _pendingActiveFrom);
        }
        return (address(0), 0);
    }

    /// @inheritdoc IDelegationContract
    function getCooldown() external view returns (uint256) {
        return COOLDOWN;
    }

    /// @inheritdoc IDelegationContract
    function isTerminated() external view returns (bool) {
        return _terminated;
    }

    /// @inheritdoc IDelegationContract
    function supportsInterface(bytes4 interfaceId) external pure override(IDelegationContract, IERC165) returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC1271).interfaceId ||
            interfaceId == type(IERC5313).interfaceId ||
            interfaceId == type(IDelegationContract).interfaceId;
    }

    /// @inheritdoc IDelegationContract
    function getDelegate() public view returns (address) {
        if (_pendingActiveFrom != 0 && block.timestamp >= _pendingActiveFrom) {
            return _pendingDelegate;
        }
        return _currentDelegate;
    }

    /// @notice Folds a matured pending assignment into `_currentDelegate` before a new
    ///         state-changing assignment is applied, so a later rotation never reverts to
    ///         an earlier delegate.
    function _settle() internal {
        if (_pendingActiveFrom != 0 && block.timestamp >= _pendingActiveFrom) {
            _currentDelegate = _pendingDelegate;
            _pendingDelegate = address(0);
            _pendingActiveFrom = 0;
        }
    }

    function _onlyOwner() internal view {
        if (msg.sender != OWNER) revert NotOwner();
    }

    function _notTerminated() internal view {
        if (_terminated) revert ContractTerminated();
    }
}
