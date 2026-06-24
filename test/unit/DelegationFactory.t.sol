// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { Vm } from "forge-std/Vm.sol";
import { Test } from "forge-std/Test.sol";

import { DelegationFactory } from "../../src/DelegationFactory.sol";
import { IDelegationFactory } from "../../src/interfaces/IDelegationFactory.sol";
import { Utilities } from "../helpers/Utilities.sol";

contract DelegationFactoryBaseTest is Test, Utilities {
    DelegationFactory public delegationFactory;

    function setUp() public virtual {
        delegationFactory = new DelegationFactory();
    }
}

contract DelegationFactoryTest is DelegationFactoryBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_deployDelegationContract() public {
        address admin = nextAddress("ADMIN");
        address delegatee = nextAddress("DELEGATEE");

        vm.expectEmit(true, false, false, false, address(delegationFactory));
        emit IDelegationFactory.DelegationDeployed(admin, address(0));
        vm.recordLogs();

        address delegationContract = delegationFactory.deployDelegation(admin, delegatee);

        assertEq(delegationContract.code.length > 0, true);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2, "Expected two logs to be emitted");
        assertEq(logs[1].topics[0], keccak256("DelegationDeployed(address,address)"));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(admin))));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(delegationContract))));
    }
}
