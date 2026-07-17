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

    /// @notice Accepts ETH and keeps all of it.
    function payableNoop() external payable {}

    /// @notice Accepts ETH, keeps `keep` wei, and immediately returns the rest to the caller.
    function payableWithChange(uint256 keep) external payable {
        if (msg.value > keep) {
            uint256 change = msg.value - keep;
            // solhint-disable-next-line avoid-low-level-calls
            (bool sent, ) = msg.sender.call{ value: change }("");
            require(sent, "change transfer failed");
        }
    }
}
