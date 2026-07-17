// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { DelegationContract } from "../../src/DelegationContract.sol";
import { Utilities } from "../helpers/Utilities.sol";

/// @notice Fuzz handler that mirrors the DelegationContract state machine in ghost variables,
///         so invariants can compare the real contract against an independent reference model.
contract DelegationHandler is CommonBase, StdUtils {
    DelegationContract public immutable DC;
    address public immutable OWNER;
    uint256 public immutable COOLDOWN;

    address public ghostCurrent;
    address public ghostPending;
    uint256 public ghostActiveFrom;
    bool public ghostTerminated;
    /// @notice Every address that was constructor-set or nominated at some point.
    mapping(address => bool) public everDelegate;

    constructor(DelegationContract dc, address owner_, address initialDelegate, uint256 cooldown_) {
        DC = dc;
        OWNER = owner_;
        COOLDOWN = cooldown_;
        ghostCurrent = initialDelegate;
        everDelegate[initialDelegate] = true;
    }

    function assign(uint160 seed) external {
        if (ghostTerminated) return;
        address newDelegate = address(uint160(bound(seed, 1, type(uint160).max)));
        if (newDelegate == OWNER) return;

        vm.prank(OWNER);
        DC.assignDelegate(newDelegate);

        _settleGhost();
        ghostPending = newDelegate;
        ghostActiveFrom = block.timestamp + COOLDOWN;
        everDelegate[newDelegate] = true;
    }

    function revoke() external {
        if (ghostTerminated) return;

        vm.prank(OWNER);
        DC.revokeDelegate();

        ghostCurrent = address(0);
        ghostPending = address(0);
        ghostActiveFrom = 0;
    }

    /// @dev Gated on the seed so termination stays rare and most runs keep exercising rotation.
    function terminate(uint256 seed) external {
        if (ghostTerminated || seed % 25 != 0) return;

        vm.prank(OWNER);
        DC.terminate();

        ghostTerminated = true;
        ghostCurrent = address(0);
        ghostPending = address(0);
        ghostActiveFrom = 0;
    }

    function warp(uint256 secondsForward) external {
        vm.warp(block.timestamp + bound(secondsForward, 1, 30 days));
    }

    /// @notice Reference model of getDelegate().
    function effectiveDelegate() public view returns (address) {
        if (ghostActiveFrom != 0 && block.timestamp >= ghostActiveFrom) return ghostPending;
        return ghostCurrent;
    }

    /// @notice Reference model of getPendingDelegate().
    function pendingDelegate() public view returns (address, uint256) {
        if (ghostActiveFrom != 0 && block.timestamp < ghostActiveFrom) return (ghostPending, ghostActiveFrom);
        return (address(0), 0);
    }

    function _settleGhost() internal {
        if (ghostActiveFrom != 0 && block.timestamp >= ghostActiveFrom) {
            ghostCurrent = ghostPending;
            ghostPending = address(0);
            ghostActiveFrom = 0;
        }
    }
}

contract DelegationContractInvariantTest is Test, Utilities {
    DelegationContract public delegationContract;
    DelegationHandler public handler;

    address internal owner;
    address internal initialDelegate;
    uint256 internal cooldown;

    function setUp() public {
        owner = nextAddress("OWNER");
        initialDelegate = nextAddress("DELEGATE");
        cooldown = 3 days;

        delegationContract = new DelegationContract(owner, initialDelegate, cooldown);
        handler = new DelegationHandler(delegationContract, owner, initialDelegate, cooldown);

        targetContract(address(handler));
    }

    function invariant_getDelegateMatchesModel() public view {
        assertEq(
            delegationContract.getDelegate(),
            handler.effectiveDelegate(),
            "getDelegate() must always match the reference model"
        );
    }

    function invariant_getPendingDelegateMatchesModel() public view {
        (address pending, uint256 activeFrom) = delegationContract.getPendingDelegate();
        (address expectedPending, uint256 expectedActiveFrom) = handler.pendingDelegate();
        assertEq(pending, expectedPending, "getPendingDelegate() delegate must always match the reference model");
        assertEq(activeFrom, expectedActiveFrom, "getPendingDelegate() activeFrom must always match the model");
    }

    function invariant_delegateNeverOwnerAndAlwaysKnown() public view {
        address effective = delegationContract.getDelegate();
        assertTrue(effective != owner, "Owner must never be the effective delegate");
        if (effective != address(0)) {
            assertTrue(
                handler.everDelegate(effective),
                "getDelegate() must only return constructor-set or nominated addresses"
            );
        }
    }

    function invariant_terminatedImpliesNoDelegateForever() public view {
        if (handler.ghostTerminated()) {
            assertTrue(delegationContract.isTerminated());
            assertEq(delegationContract.getDelegate(), address(0), "Terminated contract must never have a delegate");
        }
    }
}
