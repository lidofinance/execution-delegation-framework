// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { DeployBase } from "./DeployBase.s.sol";

contract DeployHoodi is DeployBase {
    constructor() DeployBase("hoodi", 560048) {}
}
