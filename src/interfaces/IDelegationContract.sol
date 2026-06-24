// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

/// @title IDelegationContract
/// @author Lido
/// @notice Interface for delegation contracts that allow hot key rotation without governance
interface IDelegationContract {
    /// @notice Emitted when a new delegate is assigned
    /// @param delegate The address of the newly assigned delegate
    event DelegateAssigned(address indexed delegate);

    /// @notice Emitted when a delegate is revoked
    /// @param delegate The address of the revoked delegate
    event DelegateRevoked(address indexed delegate);

    error NotAdmin();
    error NotDelegatee();
    error ZeroAddress();
    error SameDelegatee();
    error SameAdmin();
    error NoDelegatee();
    error InvalidSignature();
    error TargetNotContract();
    error CannotCallSelf();
    error AdminCannotBeDelegatee();

    /// @notice Assigns a new delegate
    /// @param delegate The address to assign as delegate
    function assignDelegate(address delegate) external;

    /// @notice Revokes the current delegate
    function revokeDelegate() external;

    /// @notice Execute a call to a target contract on behalf of this delegation contract
    /// @param target The target contract address
    /// @param callData The calldata to execute on the target contract
    /// @return result The return data from the call
    function execute(address target, bytes calldata callData) external returns (bytes memory result);

    /// @notice EIP-1271 signature validation
    /// @param hash The hash of the data to be signed
    /// @param signature The signature bytes
    /// @return magicValue Returns 0x1626ba7e if valid, 0xffffffff otherwise
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);

    /// @notice Returns the admin address
    /// @return The address of the admin (cold wallet or multisig owner)
    function admin() external view returns (address);

    /// @notice Returns the delegatee address
    /// @return The address of the delegatee (hot wallet owner)
    function delegatee() external view returns (address);
}
