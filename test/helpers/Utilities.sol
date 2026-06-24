// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { CommonBase } from "forge-std/Base.sol";

contract Utilities is CommonBase {
    bytes32 internal seed = keccak256("seed sEed seEd");

    function nextAddress() internal returns (address) {
        bytes32 buf = keccak256(abi.encodePacked(seed));
        address a = address(uint160(uint256(buf)));
        seed = buf;
        return a;
    }

    function nextAddress(string memory label) internal returns (address) {
        address a = nextAddress();
        vm.label(a, label);
        return a;
    }
}
