// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC5313 } from "@openzeppelin/contracts/interfaces/IERC5313.sol";

import { DelegationContract } from "../../src/DelegationContract.sol";
import { IDelegationContract } from "../../src/interfaces/IDelegationContract.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { CallableMock } from "../helpers/mocks/CallableMock.sol";
import { ERC1271WalletMock, ERC1271RevertingWalletMock } from "../helpers/mocks/ERC1271WalletMock.sol";
import { ReentrantMock } from "../helpers/mocks/ReentrantMock.sol";

contract DelegationContractBaseTest is Test, Utilities {
    /// @notice EIP-1271 magic value returned on valid signature
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    /// @notice Value returned on invalid signature
    bytes4 internal constant EIP1271_INVALID = 0xffffffff;

    DelegationContract public delegationContract;

    address public owner;
    address public delegate;
    uint256 public cooldown;

    function setUp() public virtual {}
}

contract DelegationContractBaseTestWithDeployment is DelegationContractBaseTest {
    function setUp() public virtual override {
        super.setUp();
        owner = nextAddress("OWNER");
        delegate = nextAddress("DELEGATE");
        cooldown = 3 days;

        delegationContract = new DelegationContract(owner, delegate, cooldown);
    }
}

contract DelegationContractConstructorTest is DelegationContractBaseTest {
    function test_constructor() public {
        owner = nextAddress("OWNER");
        delegate = nextAddress("DELEGATE");
        cooldown = 7 days;

        delegationContract = new DelegationContract(owner, delegate, cooldown);

        assertEq(delegationContract.owner(), owner);
        assertEq(delegationContract.getDelegate(), delegate, "Initial delegate should be effective immediately");
        assertEq(delegationContract.getCooldown(), cooldown);
        assertEq(delegationContract.isTerminated(), false);

        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        assertEq(pending, address(0), "Expected no pending delegate right after deployment");
        assertEq(activeFrom, 0);
    }

    function test_constructor_emptyDelegate() public {
        owner = nextAddress("OWNER");
        delegate = address(0);

        delegationContract = new DelegationContract(owner, delegate, 1 days);

        assertEq(delegationContract.owner(), owner);
        assertEq(delegationContract.getDelegate(), address(0));
    }

    function test_constructor_zeroCooldown() public {
        owner = nextAddress("OWNER");
        delegate = nextAddress("DELEGATE");

        delegationContract = new DelegationContract(owner, delegate, 0);

        assertEq(delegationContract.getCooldown(), 0);
    }

    function test_constructor_revertWhen_ZeroOwner() public {
        owner = address(0);
        delegate = nextAddress("DELEGATE");

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ZeroAddress.selector));
        new DelegationContract(owner, delegate, 1 days);
    }

    function test_constructor_revertWhen_OwnerIsDelegate() public {
        owner = nextAddress("OWNER");
        delegate = owner;

        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.OwnerCannotBeDelegate.selector));
        new DelegationContract(owner, delegate, 1 days);
    }
}

contract DelegationContractAssignDelegateTest is DelegationContractBaseTestWithDeployment {
    function test_assignDelegate_schedulesPending() public {
        address newDelegate = nextAddress("NEW_DELEGATE");
        uint256 expectedActiveFrom = block.timestamp + cooldown;

        vm.expectEmit();
        emit IDelegationContract.DelegateNominated(newDelegate, expectedActiveFrom);

        vm.prank(owner);
        delegationContract.assignDelegate(newDelegate);

        assertEq(delegationContract.getDelegate(), delegate, "Old delegate should remain effective during cooldown");

        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        assertEq(pending, newDelegate);
        assertEq(activeFrom, expectedActiveFrom);
    }

    function test_assignDelegate_becomesEffectiveAfterCooldown() public {
        address newDelegate = nextAddress("NEW_DELEGATE");

        vm.prank(owner);
        delegationContract.assignDelegate(newDelegate);

        vm.warp(block.timestamp + cooldown);

        assertEq(delegationContract.getDelegate(), newDelegate);

        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        assertEq(pending, address(0), "Matured delegate should no longer be reported as pending");
        assertEq(activeFrom, 0);
    }

    function test_assignDelegate_zeroCooldown_effectiveImmediately() public {
        DelegationContract dc = new DelegationContract(owner, delegate, 0);
        address newDelegate = nextAddress("NEW_DELEGATE");

        vm.prank(owner);
        dc.assignDelegate(newDelegate);

        assertEq(dc.getDelegate(), newDelegate, "Delegate should activate immediately when cooldown is 0");
    }

    function test_assignDelegate_reassignBeforeMaturity_restartsCooldownAndDropsFirstPending() public {
        address firstNewDelegate = nextAddress("FIRST_NEW_DELEGATE");
        address secondNewDelegate = nextAddress("SECOND_NEW_DELEGATE");

        vm.prank(owner);
        delegationContract.assignDelegate(firstNewDelegate);

        vm.warp(block.timestamp + cooldown / 2);

        vm.prank(owner);
        delegationContract.assignDelegate(secondNewDelegate);

        assertEq(delegationContract.getDelegate(), delegate, "Original delegate should still be effective");

        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        assertEq(pending, secondNewDelegate);
        assertEq(activeFrom, block.timestamp + cooldown);

        // Warp past the first (discarded) delegate's original activation time: it must never
        // become effective, since it was replaced before maturing.
        vm.warp(block.timestamp + cooldown / 2 + 1);
        assertEq(delegationContract.getDelegate(), delegate, "Discarded pending delegate must never activate");

        vm.warp(activeFrom);
        assertEq(delegationContract.getDelegate(), secondNewDelegate);
    }

    function test_assignDelegate_reassignAfterMaturity_settlesMaturedDelegateFirst() public {
        address firstNewDelegate = nextAddress("FIRST_NEW_DELEGATE");
        address secondNewDelegate = nextAddress("SECOND_NEW_DELEGATE");

        vm.prank(owner);
        delegationContract.assignDelegate(firstNewDelegate);

        vm.warp(block.timestamp + cooldown);
        assertEq(delegationContract.getDelegate(), firstNewDelegate);

        vm.prank(owner);
        delegationContract.assignDelegate(secondNewDelegate);

        assertEq(
            delegationContract.getDelegate(),
            firstNewDelegate,
            "Matured delegate must settle as current, never reverting to the original delegate"
        );

        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        assertEq(pending, secondNewDelegate);
        assertEq(activeFrom, block.timestamp + cooldown);

        vm.warp(activeFrom);
        assertEq(delegationContract.getDelegate(), secondNewDelegate);
    }

    function test_assignDelegate_revertWhen_ZeroDelegate() public {
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ZeroAddress.selector));
        vm.prank(owner);
        delegationContract.assignDelegate(address(0));
    }

    function test_assignDelegate_revertWhen_OwnerIsDelegate() public {
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.OwnerCannotBeDelegate.selector));
        vm.prank(owner);
        delegationContract.assignDelegate(owner);
    }

    function test_assignDelegate_revertWhen_NotOwner() public {
        address newDelegate = nextAddress("NEW_DELEGATE");
        address notOwner = nextAddress("NOT_OWNER");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotOwner.selector));
        delegationContract.assignDelegate(newDelegate);
    }

    function test_assignDelegate_revertWhen_Terminated() public {
        vm.prank(owner);
        delegationContract.terminate();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ContractTerminated.selector));
        delegationContract.assignDelegate(nextAddress("NEW_DELEGATE"));
    }
}

contract DelegationContractRevokeDelegateTest is DelegationContractBaseTestWithDeployment {
    function test_revokeDelegate_clearsCurrentImmediately() public {
        vm.expectEmit();
        emit IDelegationContract.DelegateRevoked(delegate);

        vm.prank(owner);
        delegationContract.revokeDelegate();

        assertEq(delegationContract.getDelegate(), address(0));
    }

    function test_revokeDelegate_clearsPendingAssignmentToo() public {
        address newDelegate = nextAddress("NEW_DELEGATE");

        vm.prank(owner);
        delegationContract.assignDelegate(newDelegate);

        vm.prank(owner);
        delegationContract.revokeDelegate();

        assertEq(delegationContract.getDelegate(), address(0));

        vm.warp(block.timestamp + cooldown);
        assertEq(delegationContract.getDelegate(), address(0), "Revoked pending assignment must never activate");

        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        assertEq(pending, address(0));
        assertEq(activeFrom, 0);
    }

    function test_revokeDelegate_noOpWhenNoDelegate() public {
        vm.prank(owner);
        delegationContract.revokeDelegate();

        vm.expectEmit();
        emit IDelegationContract.DelegateRevoked(address(0));

        vm.prank(owner);
        delegationContract.revokeDelegate();

        assertEq(delegationContract.getDelegate(), address(0));
    }

    function test_revokeDelegate_revertWhen_NotOwner() public {
        address notOwner = nextAddress("NOT_OWNER");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotOwner.selector));
        delegationContract.revokeDelegate();
    }

    function test_revokeDelegate_revertWhen_Terminated() public {
        vm.prank(owner);
        delegationContract.terminate();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ContractTerminated.selector));
        delegationContract.revokeDelegate();
    }
}

contract DelegationContractTerminateTest is DelegationContractBaseTestWithDeployment {
    function test_terminate_clearsDelegateAndSetsFlag() public {
        vm.expectEmit();
        emit IDelegationContract.Terminated();

        vm.prank(owner);
        delegationContract.terminate();

        assertEq(delegationContract.isTerminated(), true);
        assertEq(delegationContract.getDelegate(), address(0));
    }

    function test_terminate_clearsPendingAssignment() public {
        address newDelegate = nextAddress("NEW_DELEGATE");

        vm.prank(owner);
        delegationContract.assignDelegate(newDelegate);

        vm.prank(owner);
        delegationContract.terminate();

        vm.warp(block.timestamp + cooldown);
        assertEq(
            delegationContract.getDelegate(),
            address(0),
            "Pending assignment must never activate post-termination"
        );
    }

    function test_terminate_revertWhen_NotOwner() public {
        address notOwner = nextAddress("NOT_OWNER");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotOwner.selector));
        delegationContract.terminate();
    }

    function test_terminate_revertWhen_AlreadyTerminated() public {
        vm.prank(owner);
        delegationContract.terminate();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ContractTerminated.selector));
        delegationContract.terminate();
    }

    function test_terminate_thenAssignDelegate_reverts() public {
        vm.prank(owner);
        delegationContract.terminate();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ContractTerminated.selector));
        delegationContract.assignDelegate(nextAddress("NEW_DELEGATE"));
    }

    function test_terminate_thenRevokeDelegate_reverts() public {
        vm.prank(owner);
        delegationContract.terminate();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ContractTerminated.selector));
        delegationContract.revokeDelegate();
    }

    function test_terminate_thenExecute_reverts() public {
        CallableMock callableMock = new CallableMock();
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(owner);
        delegationContract.terminate();

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ContractTerminated.selector));
        delegationContract.execute(address(callableMock), callData);
    }

    function test_terminate_isValidSignatureReturnsInvalid() public {
        uint256 privateKey = 0xdeadbeef154;
        address signer = vm.addr(privateKey);
        DelegationContract dc = new DelegationContract(owner, signer, cooldown);

        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(owner);
        dc.terminate();

        bytes4 magicValue = dc.isValidSignature(hash, signature);
        assertEq(magicValue, EIP1271_INVALID);
    }
}

contract DelegationContractIsValidSignatureTest is DelegationContractBaseTest {
    uint256 private privateKeyForDelegate = 0xdeadbeef154;
    uint256 private privateKeyForNewDelegate = 0xdeadbeef155;

    function setUp() public override {
        super.setUp();
        owner = nextAddress("OWNER");
        delegate = vm.addr(privateKeyForDelegate);
        vm.label(delegate, "DELEGATE");
        cooldown = 3 days;

        delegationContract = new DelegationContract(owner, delegate, cooldown);
    }

    function test_isValidSignature() public view {
        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeyForDelegate, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 magicValue = delegationContract.isValidSignature(hash, signature);

        assertEq(magicValue, EIP1271_MAGIC_VALUE, "Expected valid signature to return correct magic value");
    }

    function test_isValidSignature_invalid() public view {
        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeyForDelegate + 1, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 magicValue = delegationContract.isValidSignature(hash, signature);

        assertEq(magicValue, EIP1271_INVALID, "Expected invalid signature to return correct value");
    }

    function test_isValidSignature_malformedSignatureReturnsInvalidWithoutReverting() public view {
        bytes32 hash = keccak256("TEST_HASH");
        bytes memory signature = abi.encodePacked(uint256(0x01), uint256(0x02), uint8(3)); // Malformed signature

        bytes4 magicValue = delegationContract.isValidSignature(hash, signature);

        assertEq(magicValue, EIP1271_INVALID, "Malformed signatures must fail closed, not revert");
    }

    function test_isValidSignature_invalidIfDelegateIsZero() public {
        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeyForDelegate, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(owner);
        delegationContract.revokeDelegate();

        bytes4 magicValue = delegationContract.isValidSignature(hash, signature);

        assertEq(magicValue, EIP1271_INVALID, "Expected invalid signature to return correct magic value");
    }

    function test_isValidSignature_contractDelegate_valid() public {
        uint256 walletSignerKey = 0xdeadbeef156;
        ERC1271WalletMock wallet = new ERC1271WalletMock(vm.addr(walletSignerKey));
        DelegationContract dc = new DelegationContract(owner, address(wallet), cooldown);

        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletSignerKey, hash);

        assertEq(
            dc.isValidSignature(hash, abi.encodePacked(r, s, v)),
            EIP1271_MAGIC_VALUE,
            "Contract delegate must be validated via its own ERC-1271 check"
        );
    }

    function test_isValidSignature_contractDelegate_invalidSigner() public {
        uint256 walletSignerKey = 0xdeadbeef156;
        ERC1271WalletMock wallet = new ERC1271WalletMock(vm.addr(walletSignerKey));
        DelegationContract dc = new DelegationContract(owner, address(wallet), cooldown);

        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletSignerKey + 1, hash);

        assertEq(
            dc.isValidSignature(hash, abi.encodePacked(r, s, v)),
            EIP1271_INVALID,
            "Signature rejected by the delegate wallet must be rejected here too"
        );
    }

    function test_isValidSignature_contractDelegate_revertingWalletFailsClosed() public {
        ERC1271RevertingWalletMock wallet = new ERC1271RevertingWalletMock();
        DelegationContract dc = new DelegationContract(owner, address(wallet), cooldown);

        bytes32 hash = keccak256("TEST_HASH");

        assertEq(
            dc.isValidSignature(hash, hex"1234"),
            EIP1271_INVALID,
            "A reverting delegate wallet must fail closed, not revert"
        );
    }

    function test_isValidSignature_oldDelegateStillValidDuringCooldown() public {
        address newDelegate = vm.addr(privateKeyForNewDelegate);

        vm.prank(owner);
        delegationContract.assignDelegate(newDelegate);

        bytes32 hash = keccak256("TEST_HASH");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeyForDelegate, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(delegationContract.isValidSignature(hash, signature), EIP1271_MAGIC_VALUE);
    }

    function test_isValidSignature_newDelegateValidOldInvalidAfterCooldown() public {
        address newDelegate = vm.addr(privateKeyForNewDelegate);

        vm.prank(owner);
        delegationContract.assignDelegate(newDelegate);

        vm.warp(block.timestamp + cooldown);

        bytes32 hash = keccak256("TEST_HASH");
        (uint8 vOld, bytes32 rOld, bytes32 sOld) = vm.sign(privateKeyForDelegate, hash);
        (uint8 vNew, bytes32 rNew, bytes32 sNew) = vm.sign(privateKeyForNewDelegate, hash);

        assertEq(
            delegationContract.isValidSignature(hash, abi.encodePacked(rOld, sOld, vOld)),
            EIP1271_INVALID,
            "Old delegate signature must be rejected once rotated out"
        );
        assertEq(
            delegationContract.isValidSignature(hash, abi.encodePacked(rNew, sNew, vNew)),
            EIP1271_MAGIC_VALUE,
            "New delegate signature must validate once effective"
        );
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

        vm.prank(delegate);
        bytes memory resultOdd = delegationContract.execute(address(callableMock), callDataOdd);

        bool isOddResult = abi.decode(resultOdd, (bool));
        assertEq(isOddResult, true, "Expected isOdd(3) to return true");

        vm.prank(delegate);
        bytes memory resultEven = delegationContract.execute(address(callableMock), callDataEven);

        bool isEvenResult = abi.decode(resultEven, (bool));
        assertEq(isEvenResult, false, "Expected isOdd(4) to return false");
    }

    function test_execute_targetSeesDelegationContractAsMessageSender() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.returnsMsgSender.selector);

        vm.prank(delegate);
        bytes memory result = delegationContract.execute(address(callableMock), callData);

        address msgSender = abi.decode(result, (address));
        assertEq(msgSender, address(delegationContract), "Expected msg.sender to be the delegation contract");
    }

    function test_execute_revertWhen_NotDelegate() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);
        address notDelegate = nextAddress("NOT_DELEGATE");

        vm.prank(notDelegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotDelegate.selector));
        delegationContract.execute(address(callableMock), callData);
    }

    function test_execute_revertWhen_PendingDelegateNotYetActive() public {
        address newDelegate = nextAddress("NEW_DELEGATE");

        vm.prank(owner);
        delegationContract.assignDelegate(newDelegate);

        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(newDelegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotDelegate.selector));
        delegationContract.execute(address(callableMock), callData);
    }

    function test_execute_revertWhen_TargetReverts() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.revertsWhenCalled.selector);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(CallableMock.AlwaysReverts.selector));
        delegationContract.execute(address(callableMock), callData);
    }

    function test_execute_revertWhen_ZeroTarget() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ZeroAddress.selector));
        delegationContract.execute(address(0), callData);
    }

    function test_execute_revertWhen_SelfCall() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.CannotCallSelf.selector));
        delegationContract.execute(address(delegationContract), callData);
    }

    function test_execute_revertWhen_TargetNotContract() public {
        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.TargetNotContract.selector));
        delegationContract.execute(address(0x123), callData);
    }

    function test_execute_revertWhen_Terminated() public {
        vm.prank(owner);
        delegationContract.terminate();

        bytes memory callData = abi.encodeWithSelector(callableMock.isOdd.selector, 3);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.ContractTerminated.selector));
        delegationContract.execute(address(callableMock), callData);
    }

    function test_execute_forwardsValue() public {
        uint256 value = 1 ether;
        vm.deal(delegate, value);

        bytes memory callData = abi.encodeWithSelector(callableMock.payableNoop.selector);

        vm.prank(delegate);
        delegationContract.execute{ value: value }(address(callableMock), callData);

        assertEq(delegate.balance, 0, "execute() never refunds any value back to the delegate");
        assertEq(address(callableMock).balance, value, "Target should have received the full value");
        assertEq(address(delegationContract).balance, 0);
    }

    function test_execute_revertWhen_TargetSendsChangeBack() public {
        // The contract has no receive()/fallback and never refunds any value, so it cannot
        // accept ETH sent back to it. If a target tries to refund unspent value to msg.sender
        // (this contract), that transfer fails and execute() reverts atomically instead of
        // losing the funds. Integrations must route any refund directly to the delegate's own
        // address instead.
        uint256 value = 1 ether;
        uint256 keep = 0.4 ether;
        vm.deal(delegate, value);

        bytes memory callData = abi.encodeWithSelector(callableMock.payableWithChange.selector, keep);

        vm.prank(delegate);
        vm.expectRevert(bytes("change transfer failed"));
        delegationContract.execute{ value: value }(address(callableMock), callData);
    }

    function test_execute_reentrantExecute_revertsWithNotDelegate() public {
        ReentrantMock reentrant = new ReentrantMock(delegationContract);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotDelegate.selector));
        delegationContract.execute(address(reentrant), abi.encodeWithSelector(ReentrantMock.reenterExecute.selector));
    }

    function test_execute_reentrantAssignDelegate_revertsWithNotOwner() public {
        ReentrantMock reentrant = new ReentrantMock(delegationContract);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotOwner.selector));
        delegationContract.execute(
            address(reentrant),
            abi.encodeWithSelector(ReentrantMock.reenterAssignDelegate.selector)
        );
    }

    function test_execute_reentrantRevokeDelegate_revertsWithNotOwner() public {
        ReentrantMock reentrant = new ReentrantMock(delegationContract);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotOwner.selector));
        delegationContract.execute(
            address(reentrant),
            abi.encodeWithSelector(ReentrantMock.reenterRevokeDelegate.selector)
        );
    }

    function test_execute_reentrantTerminate_revertsWithNotOwner() public {
        ReentrantMock reentrant = new ReentrantMock(delegationContract);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(IDelegationContract.NotOwner.selector));
        delegationContract.execute(address(reentrant), abi.encodeWithSelector(ReentrantMock.reenterTerminate.selector));
    }

    function test_execute_doesNotTouchPreExistingBalance() public {
        uint256 preExisting = 2 ether;
        vm.deal(address(delegationContract), preExisting);

        uint256 value = 1 ether;
        vm.deal(delegate, value);

        bytes memory callData = abi.encodeWithSelector(callableMock.payableNoop.selector);

        vm.prank(delegate);
        delegationContract.execute{ value: value }(address(callableMock), callData);

        assertEq(delegate.balance, 0, "execute() never refunds any value back to the delegate");
        assertEq(address(delegationContract).balance, preExisting, "Pre-existing balance must remain untouched");
    }
}

contract DelegationContractIntrospectionTest is DelegationContractBaseTestWithDeployment {
    function test_supportsInterface_erc165() public view {
        assertTrue(delegationContract.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_erc1271() public view {
        assertTrue(delegationContract.supportsInterface(type(IERC1271).interfaceId));
    }

    function test_supportsInterface_erc5313() public view {
        assertTrue(delegationContract.supportsInterface(type(IERC5313).interfaceId));
    }

    function test_supportsInterface_iDelegationContract() public view {
        assertTrue(delegationContract.supportsInterface(type(IDelegationContract).interfaceId));
    }

    function test_supportsInterface_falseForRandomId() public view {
        assertFalse(delegationContract.supportsInterface(bytes4(0xdeadbeef)));
    }

    function test_owner_returnsOwner() public view {
        assertEq(delegationContract.owner(), owner);
    }
}

contract DelegationContractFuzzTest is DelegationContractBaseTestWithDeployment {
    function testFuzz_getDelegate_pendingActivatesExactlyAtActiveFrom(uint256 cooldown_, uint256 warpBy) public {
        cooldown_ = bound(cooldown_, 1, 365 days);
        warpBy = bound(warpBy, 0, 2 * 365 days);

        DelegationContract dc = new DelegationContract(owner, delegate, cooldown_);
        address newDelegate = nextAddress("NEW_DELEGATE");

        vm.prank(owner);
        dc.assignDelegate(newDelegate);
        uint256 activeFrom = block.timestamp + cooldown_;

        vm.warp(block.timestamp + warpBy);

        if (block.timestamp >= activeFrom) {
            assertEq(dc.getDelegate(), newDelegate, "Nominee must be effective once activeFrom is reached");
        } else {
            assertEq(dc.getDelegate(), delegate, "Old delegate must stay effective before activeFrom");
        }
    }

    function testFuzz_replacedPendingDelegateNeverActivates(uint256 replaceAfter, uint256 warpBy) public {
        // Replace the first nominee strictly before it matures, then check it never activates.
        replaceAfter = bound(replaceAfter, 0, cooldown - 1);
        warpBy = bound(warpBy, 0, 4 * 365 days);

        address firstNominee = nextAddress("FIRST_NOMINEE");
        address secondNominee = nextAddress("SECOND_NOMINEE");

        vm.prank(owner);
        delegationContract.assignDelegate(firstNominee);

        vm.warp(block.timestamp + replaceAfter);
        vm.prank(owner);
        delegationContract.assignDelegate(secondNominee);
        uint256 secondActiveFrom = block.timestamp + cooldown;

        vm.warp(block.timestamp + warpBy);

        address effective = delegationContract.getDelegate();
        assertTrue(effective != firstNominee, "Replaced pending delegate must never become effective");
        assertEq(effective, block.timestamp >= secondActiveFrom ? secondNominee : delegate);
    }

    function testFuzz_terminated_noDelegateForever(uint256 warpBy) public {
        warpBy = bound(warpBy, 0, 10 * 365 days);

        vm.prank(owner);
        delegationContract.assignDelegate(nextAddress("NEW_DELEGATE"));

        vm.prank(owner);
        delegationContract.terminate();

        vm.warp(block.timestamp + warpBy);

        assertEq(delegationContract.getDelegate(), address(0), "Terminated contract must never have a delegate");

        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        assertEq(pending, address(0), "Terminated contract must never report a pending delegate");
        assertEq(activeFrom, 0);
    }
}
