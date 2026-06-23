// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { Vm } from "forge-std/Vm.sol";
import { Test } from "forge-std/Test.sol";
import { DelegationContract } from "../../src/DelegationContract.sol";
import { IDelegationContract } from "../../src/interfaces/IDelegationContract.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { CallableMock } from "../helpers/mocks/CallableMock.sol";

contract DelegationContractBaseTest is Test, Utilities {
    DelegationContract public delegationContract;

    address public admin;
    address public delegatee;

    function setUp() public virtual {}
}

contract DelegationContractBaseTestWithDeployment is DelegationContractBaseTest {
    function setUp() public virtual override {
        super.setUp();
        admin = nextAddress("ADMIN");
        delegatee = nextAddress("DELEGATEE");

        delegationContract = new DelegationContract(admin, delegatee);
    }
}

contract DelegationContractConstructorTest is DelegationContractBaseTest {
    function test_constructor() public {
        admin = nextAddress("ADMIN");
        delegatee = nextAddress("DELEGATEE");

        vm.expectEmit();
        emit IDelegationContract.DelegateAssigned(delegatee);

        delegationContract = new DelegationContract(admin, delegatee);

        assertEq(delegationContract.admin(), admin);
        assertEq(delegationContract.delegatee(), delegatee);
    }

    function test_constructor_emptyDelegatee() public {
        admin = nextAddress("ADMIN");
        delegatee = address(0);
        vm.recordLogs();

        delegationContract = new DelegationContract(admin, delegatee);

        assertEq(vm.getRecordedLogs().length, 0, "Expected no logs to be emitted");
        assertEq(delegationContract.admin(), admin);
        assertEq(delegationContract.delegatee(), address(0));
    }

    function test_constructor_revertWhen_ZeroAdmin() public {
        admin = address(0);
        delegatee = nextAddress("DELEGATEE");

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ZeroAddress.selector));
        new DelegationContract(admin, delegatee);
    }

    function test_constructor_revertWhen_AdminIsDelegatee() public {
        admin = nextAddress("ADMIN");
        delegatee = admin;

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.AdminCannotBeDelegatee.selector));
        new DelegationContract(admin, delegatee);
    }
}

contract DelegationContractAssignDelegateTest is DelegationContractBaseTestWithDeployment {
    function test_assignDelegate() public {
        address newDelegatee = nextAddress("NEW_DELEGATEE");

        vm.expectEmit();
        emit IDelegationContract.DelegateAssigned(newDelegatee);

        vm.prank(admin);
        delegationContract.assignDelegate(newDelegatee);

        assertEq(delegationContract.delegatee(), newDelegatee);
    }

    function test_assignDelegate_revertWhen_ZeroAddress() public {
        address newDelegatee = address(0);

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ZeroAddress.selector));
        vm.prank(admin);
        delegationContract.assignDelegate(newDelegatee);
    }

    function test_assignDelegate_revertWhen_SameDelegatee() public {
        address newDelegatee = delegationContract.delegatee();

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.SameDelegatee.selector));
        vm.prank(admin);
        delegationContract.assignDelegate(newDelegatee);
    }

    function test_assignDelegate_revertWhen_AdminIsDelegatee() public {
        address newDelegatee = delegationContract.admin();

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.AdminCannotBeDelegatee.selector));
        vm.prank(admin);
        delegationContract.assignDelegate(newDelegatee);
    }

    function test_assignDelegate_revertWhen_NotAdmin() public {
        address newDelegatee = nextAddress("NEW_DELEGATEE");
        address notAdmin = nextAddress("NOT_ADMIN");

        vm.prank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotAdmin.selector));
        delegationContract.assignDelegate(newDelegatee);
    }
}

contract DelegationContractRevokeDelegateTest is DelegationContractBaseTestWithDeployment {
    function test_revokeDelegate() public {
        vm.expectEmit();
        emit IDelegationContract.DelegateRevoked(delegatee);

        vm.prank(admin);
        delegationContract.revokeDelegate();

        assertEq(delegationContract.delegatee(), address(0));
    }

    function test_revokeDelegate_revertWhen_NoDelegatee() public {
        DelegationContract delegationContractNoDelegatee = new DelegationContract(admin, address(0));

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NoDelegatee.selector));
        vm.prank(admin);
        delegationContractNoDelegatee.revokeDelegate();
    }

    function test_revokeDelegate_revertWhen_NotAdmin() public {
        address notAdmin = nextAddress("NOT_ADMIN");

        vm.prank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotAdmin.selector));
        delegationContract.revokeDelegate();
    }
}

contract DelegationContractIsValidSignatureTest is DelegationContractBaseTest {
    /// @notice EIP-1271 magic value returned on valid signature
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    /// @notice Value returned on invalid signature
    bytes4 internal constant EIP1271_INVALID = 0xffffffff;

    uint256 private privateKeyForDelegatee = 0xdeadbeef154;

    function setUp() public override {
        super.setUp();
        admin = nextAddress("ADMIN");
        delegatee = vm.addr(privateKeyForDelegatee);
        vm.label(delegatee, "DELEGATEE");

        delegationContract = new DelegationContract(admin, delegatee);
    }

    function test_isValidSignature() public {
        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeyForDelegatee, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 magicValue = delegationContract.isValidSignature(hash, signature);

        assertEq(magicValue, EIP1271_MAGIC_VALUE, "Expected valid signature to return correct magic value");
    }

    function test_isValidSignature_invalid() public {
        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeyForDelegatee + 1, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 magicValue = delegationContract.isValidSignature(hash, signature);

        assertEq(magicValue, EIP1271_INVALID, "Expected invalid signature to return correct magic value");
    }

    function test_isValidSignature_invalidIfDelegateeIsZero() public {
        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeyForDelegatee, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Revoke the delegatee to set it to zero address
        vm.prank(admin);
        delegationContract.revokeDelegate();

        bytes4 magicValue = delegationContract.isValidSignature(hash, signature);

        assertEq(magicValue, EIP1271_INVALID, "Expected invalid signature to return correct magic value");
    }
}

contract DelegationContractExecuteTest is DelegationContractBaseTestWithDeployment {
    CallableMock callableMock;

    function setUp() public override {
        super.setUp();
        callableMock = new CallableMock();
    }

    function test_execute() public {
        bytes memory callDataOdd = abi.encodeWithSelector(callableMock.isOdd.selector, 3);
        bytes memory callDataEven = abi.encodeWithSelector(callableMock.isOdd.selector, 4);

        vm.prank(delegatee);
        bytes memory resultOdd = delegationContract.execute(address(callableMock), callDataOdd);

        bool isOddResult = abi.decode(resultOdd, (bool));
        assertEq(isOddResult, true, "Expected isOdd(3) to return true");

        vm.prank(delegatee);
        bytes memory resultEven = delegationContract.execute(address(callableMock), callDataEven);

        bool isEvenResult = abi.decode(resultEven, (bool));
        assertEq(isEvenResult, false, "Expected isOdd(4) to return false");
    }

    function test_execute_targetSeeDelegationContractsAsMessageSender() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.returnsMsgSender.selector);

        vm.prank(delegatee);
        bytes memory result = delegationContract.execute(address(callableMock), callData);

        address msgSender = abi.decode(result, (address));
        assertEq(msgSender, address(delegationContract), "Expected msg.sender to be the delegation contract");
    }

    function test_execute_revertWhen_NotDelegatee() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);
        address notDelegatee = nextAddress("NOT_DELEGATEE");

        vm.prank(notDelegatee);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotDelegatee.selector));
        delegationContract.execute(address(callableMock), callData);
    }

    function test_execute_revertWhen_TargetReverts() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.revertsWhenCalled.selector);

        vm.prank(delegatee);
        vm.expectRevert(abi.encodeWithSelector(CallableMock.AlwaysReverts.selector));
        delegationContract.execute(address(callableMock), callData);
    }

    function test_execute_revertWhen_ZeroTarget() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(delegatee);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ZeroAddress.selector));
        delegationContract.execute(address(0), callData);
    }

    function test_execute_revertWhen_SelfCall() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(delegatee);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.CannotCallSelf.selector));
        delegationContract.execute(address(delegationContract), callData);
    }

    function test_execute_revertWhen_TargetNotContract() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(delegatee);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.TargetNotContract.selector));
        delegationContract.execute(address(0x123), callData);
    }
}
