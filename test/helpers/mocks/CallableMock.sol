// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

contract CallableMock {
    error AlwaysReverts();

    function isOdd(uint256 number) external pure returns (bool) {
        return number % 2 == 1;
    }

    function revertsWhenCalled() external pure {
        revert AlwaysReverts();
    }

    function returnsMsgSender() external view returns (address) {
        return msg.sender;
    }
}
