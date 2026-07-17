// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { DeployBase } from "./DeployBase.s.sol";

contract DeployLocalDevnet is DeployBase {
    error ChainIdRequired();

    constructor() DeployBase("local-devnet", 0) {}

    function run(string memory) external pure override {
        revert ChainIdRequired();
    }

    function run(string memory _gitRef, uint256 _chainId) external {
        _run(_gitRef, _chainId);
    }
}
