// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { IDelegationContract } from "../../../src/interfaces/IDelegationContract.sol";

/// @notice Execute() target that calls back into the DelegationContract mid-call,
///         probing that neither delegate nor owner permissions are ambient during execute().
contract ReentrantMock {
    IDelegationContract public immutable DC;

    constructor(IDelegationContract dc) {
        DC = dc;
    }

    function reenterExecute() external {
        DC.execute(address(this), "");
    }

    function reenterAssignDelegate() external {
        DC.assignDelegate(address(0xbeef));
    }

    function reenterRevokeDelegate() external {
        DC.revokeDelegate();
    }

    function reenterTerminate() external {
        DC.terminate();
    }
}
