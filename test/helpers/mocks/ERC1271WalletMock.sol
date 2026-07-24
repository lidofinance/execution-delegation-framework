// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Minimal ERC-1271 smart wallet: a signature is valid iff it is an ECDSA
///         signature over `hash` by the wallet's designated signer.
contract ERC1271WalletMock is IERC1271 {
    address public immutable SIGNER;

    constructor(address signer) {
        SIGNER = signer;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == SIGNER) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }
}

/// @notice ERC-1271 wallet that always reverts on validation.
contract ERC1271RevertingWalletMock is IERC1271 {
    error ValidationReverted();

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        revert ValidationReverted();
    }
}
