// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { IDelegationFactory } from "./interfaces/IDelegationFactory.sol";
import { DelegationContract } from "./DelegationContract.sol";

/// @title DelegationFactory
/// @notice Factory for deploying DelegationContract instances
contract DelegationFactory is IDelegationFactory {
    /// @inheritdoc IDelegationFactory
    function deploy(address owner, address delegate, uint256 cooldown) external returns (address instance) {
        instance = address(new DelegationContract(owner, delegate, cooldown));

        emit DelegationContractDeployed(instance, owner, delegate, cooldown);
    }
}
