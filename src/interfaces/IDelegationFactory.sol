// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

/// @title IDelegationFactory
/// @author Lido
/// @notice Interface for the factory that deploys DelegationContract instances
interface IDelegationFactory {
    /// @notice Emitted for each DelegationContract deployed by the factory.
    event DelegationContractDeployed(
        address indexed instance,
        address indexed owner,
        address indexed delegate,
        uint256 cooldown
    );

    /// @notice Deploy a new DelegationContract.
    /// @param owner     The contract's owner, set as a constructor immutable.
    ///                   Fixed for the lifetime of the contract; replacing
    ///                   the owner requires deploying a new contract.
    /// @param delegate   Initial active delegate, set in the constructor (and
    ///                   effective immediately — the cooldown applies only to
    ///                   later reassignments). Mutable thereafter via
    ///                   assignDelegate(). Pass address(0) to deploy with no
    ///                   delegate.
    /// @param cooldown   Seconds a reassigned delegate waits before becoming
    ///                   effective (see assignDelegate). Set as a constructor
    ///                   immutable; may be 0 to disable the cooldown.
    /// @return instance Address of the newly deployed DelegationContract.
    function deploy(address owner, address delegate, uint256 cooldown) external returns (address instance);
}
