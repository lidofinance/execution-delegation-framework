// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

/// @title IDelegationFactory
/// @author Lido
/// @notice Interface for factory that deploys DelegationContract instances
interface IDelegationFactory {
    /// @notice Emitted when a new DelegationContract is deployed
    /// @param admin The admin address of the deployed contract
    /// @param delegation The address of the deployed DelegationContract
    event DelegationDeployed(address indexed admin, address indexed delegation);

    /// @notice Deploys a new DelegationContract
    /// @param admin The admin address for the new contract
    /// @param delegatee The initial delegatee address (can be address(0))
    /// @return delegation The address of the deployed DelegationContract
    function deployDelegation(address admin, address delegatee) external returns (address delegation);
}
