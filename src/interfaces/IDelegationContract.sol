// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

/// @title IDelegationContract
/// @notice Interface for the minimal Execution Delegation Framework (EDF) delegation contract:
///         one owner, one active delegate, cooldown-gated reassignment, irreversible termination.
interface IDelegationContract {
    // --- Events ---

    event DelegateNominated(address indexed newDelegate, uint256 activeFrom);
    event DelegateRevoked(address indexed revokedDelegate);
    event Terminated();

    // --- Errors ---

    error NotOwner();
    error NotDelegate();
    error ZeroAddress();
    error OwnerCannotBeDelegate();
    error ContractTerminated();
    error TargetNotContract();
    error CannotCallSelf();

    // --- Owner controls ---

    /// @notice Assign (or reassign) the active delegate.
    ///         Only callable by owner. The new delegate becomes effective only
    ///         after the contract's cooldown (`getCooldown()` seconds, or
    ///         immediately if cooldown is 0). The currently effective delegate
    ///         (if any) stays effective throughout the cooldown and is dropped
    ///         only when the new one activates.
    ///         Reassigning before the cooldown elapses replaces the pending
    ///         delegate and restarts the cooldown; the current one stays
    ///         effective throughout. To drop a (e.g. compromised) delegate
    ///         immediately, use revokeDelegate().
    ///         Reverts if delegate == address(0); removing a delegate is only
    ///         possible via revokeDelegate().
    ///         Reverts if delegate == owner.
    ///         Reverts if the contract is terminated.
    /// @param delegate Address of the incoming delegate.
    function assignDelegate(address delegate) external;

    /// @notice Immediately remove the current and pending delegate.
    ///         Only callable by owner.
    ///         Reverts if the contract is terminated.
    function revokeDelegate() external;

    /// @notice Terminate the contract, permanently disabling execute(), signature
    ///         verification via isValidSignature(), and further delegate reassignment
    ///         via assignDelegate.
    ///         Only callable by owner.
    ///         Also clears the active delegate (as revokeDelegate), so
    ///         getDelegate() returns address(0) after termination.
    ///         Intended for emergency use when the owner is suspected compromised.
    ///         Termination is irreversible.
    ///         Reverts if the contract is already terminated.
    function terminate() external;

    // --- Push integration ---

    /// @notice Execute an arbitrary non-delegate call on behalf of this contract.
    ///         Only callable by the current delegate.
    ///         Reverts if the contract is terminated.
    ///         Reverts if the target call reverts.
    ///         Forwards msg.value to the target.
    /// @param target Address to call.
    /// @param data   Call data.
    /// @return result Return data from the call.
    function execute(address target, bytes calldata data) external payable returns (bytes memory result);

    // --- Pull integration (ERC-1271) ---

    /// @notice ERC-1271 signature validation. Returns the ERC-1271 magic value
    ///         (0x1626ba7e) if `signature` is a valid signature over `hash`
    ///         by the contract's current *effective* delegate; otherwise
    ///         returns 0xffffffff.
    ///         The delegate is resolved via getDelegate(), so validation
    ///         fails closed when there is no effective delegate (never
    ///         assigned, revoked, or terminated → address(0)).
    ///
    ///         NOTE: unlike a raw ECDSA check, this result is state-dependent
    ///         and revocable — it can return valid at one block and invalid at
    ///         the next (e.g. after the delegate is rotated, revoked, or the
    ///         contract is terminated).
    /// @param hash      Message hash that was signed.
    /// @param signature Opaque signature bytes (ECDSA).
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);

    // --- Interface detection (ERC-165) ---

    /// @notice ERC-165 interface detection. Returns true for the ERC-165,
    ///         ERC-1271 (`isValidSignature`), ERC-5313 (`owner`), and
    ///         `IDelegationContract` interface ids.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    // --- Views ---

    /// @notice The contract's owner. Provided as the
    ///         read-only ERC-5313 ownership view so explorers, multisig UIs,
    ///         and generic tooling recognize the controlling party.
    function owner() external view returns (address);

    /// @notice Returns the currently *effective* delegate, or address(0) if
    ///         none. After assignDelegate(), the previously effective delegate
    ///         remains the effective one until the new delegate's cooldown
    ///         elapses; only then does this return the new delegate. Returns
    ///         address(0) when there is no current delegate (never assigned, or
    ///         revoked) and once the contract is terminated.
    function getDelegate() external view returns (address);

    /// @notice Returns the pending (not-yet-effective) delegate and the
    ///         timestamp at which it becomes effective, or (address(0), 0) when
    ///         there is no such pending assignment. The result is
    ///         time-dependent: a scheduled delegate is returned here only while
    ///         block.timestamp < activeFrom. From that moment on it is the
    ///         effective delegate — getDelegate() starts returning it and this
    ///         function returns (address(0), 0), with no transaction needed for
    ///         the transition.
    function getPendingDelegate() external view returns (address delegate, uint256 activeFrom);

    /// @notice Cooldown in seconds between assigning a delegate and it
    ///         becoming effective. Set in the constructor (Solidity immutable)
    ///         and unchangeable thereafter.
    function getCooldown() external view returns (uint256);

    /// @notice Returns true if the contract has been terminated.
    function isTerminated() external view returns (bool);
}
