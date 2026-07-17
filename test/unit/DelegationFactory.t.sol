// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { Vm } from "forge-std/Vm.sol";
import { Test } from "forge-std/Test.sol";

import { DelegationFactory } from "../../src/DelegationFactory.sol";
import { DelegationContract } from "../../src/DelegationContract.sol";
import { IDelegationFactory } from "../../src/interfaces/IDelegationFactory.sol";
import { IDelegationContract } from "../../src/interfaces/IDelegationContract.sol";
import { Utilities } from "../helpers/Utilities.sol";

contract DelegationFactoryBaseTest is Test, Utilities {
    DelegationFactory public delegationFactory;

    function setUp() public virtual {
        delegationFactory = new DelegationFactory();
    }
}

contract DelegationFactoryTest is DelegationFactoryBaseTest {
    function test_deploy() public {
        address owner = nextAddress("OWNER");
        address delegate = nextAddress("DELEGATE");
        uint256 cooldown = 3 days;

        vm.expectEmit(false, true, true, true, address(delegationFactory));
        emit IDelegationFactory.DelegationContractDeployed(address(0), owner, delegate, cooldown);
        vm.recordLogs();

        address instance = delegationFactory.deploy(owner, delegate, cooldown);

        assertGt(instance.code.length, 0);

        DelegationContract dc = DelegationContract(payable(instance));
        assertEq(dc.owner(), owner);
        assertEq(dc.getDelegate(), delegate);
        assertEq(dc.getCooldown(), cooldown);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1, "Expected exactly one log to be emitted");
        assertEq(logs[0].topics[0], keccak256("DelegationContractDeployed(address,address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(instance))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(owner))));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(delegate))));
        assertEq(abi.decode(logs[0].data, (uint256)), cooldown);
    }

    function test_deploy_zeroDelegate() public {
        address owner = nextAddress("OWNER");
        uint256 cooldown = 1 days;

        address instance = delegationFactory.deploy(owner, address(0), cooldown);

        DelegationContract dc = DelegationContract(payable(instance));
        assertEq(dc.getDelegate(), address(0));
    }

    function test_deploy_revertWhen_ZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ZeroAddress.selector));
        delegationFactory.deploy(address(0), nextAddress("DELEGATE"), 1 days);
    }

    function test_deploy_revertWhen_OwnerIsDelegate() public {
        address owner = nextAddress("OWNER");

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.OwnerCannotBeDelegate.selector));
        delegationFactory.deploy(owner, owner, 1 days);
    }

    function test_deploy_independentInstances() public {
        address ownerA = nextAddress("OWNER_A");
        address ownerB = nextAddress("OWNER_B");

        address instanceA = delegationFactory.deploy(ownerA, address(0), 0);
        address instanceB = delegationFactory.deploy(ownerB, address(0), 0);

        assertTrue(instanceA != instanceB);
    }
}
