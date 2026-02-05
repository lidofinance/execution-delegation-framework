// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IDelegationContract} from "./interfaces/IDelegationContract.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title DelegationContract
/// @author Lido
/// @notice A delegation contract that allows an admin to delegate signing authority to a hot key
/// @dev Implements EIP-1271 for signature validation, allowing protocols to verify
///      that a signature was made by the authorized delegatee
contract DelegationContract is IDelegationContract {
    using ECDSA for bytes32;

    /// @notice EIP-1271 magic value returned on valid signature
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    /// @notice Value returned on invalid signature
    bytes4 internal constant EIP1271_INVALID = 0xffffffff;

    /// @notice The admin address (owner of cold wallet or multisig)
    address public admin;

    /// @notice The delegatee address (owner of hot wallet)
    address public delegatee;

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyDelegatee() {
        if (msg.sender != delegatee) revert NotDelegatee();
        _;
    }

    /// @notice Creates a new DelegationContract
    /// @param _admin The admin address that controls this contract
    /// @param _delegatee The initial delegatee (can be address(0) if not set initially)
    constructor(address _admin, address _delegatee) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_delegatee == _admin) revert AdminCannotBeDelegatee();

        admin = _admin;
        emit AdminChanged(address(0), _admin);

        if (_delegatee != address(0)) {
            delegatee = _delegatee;
            emit DelegateAssigned(_delegatee);
        }
    }

    /// @inheritdoc IDelegationContract
    function assignDelegate(address _delegate) external onlyAdmin {
        if (_delegate == address(0)) revert ZeroAddress();
        if (_delegate == delegatee) revert SameDelegatee();
        if (_delegate == admin) revert AdminCannotBeDelegatee();

        delegatee = _delegate;
        emit DelegateAssigned(_delegate);
    }

    /// @inheritdoc IDelegationContract
    function revokeDelegate() external onlyAdmin {
        if (delegatee == address(0)) revert NoDelegatee();

        address oldDelegatee = delegatee;
        delegatee = address(0);
        emit DelegateRevoked(oldDelegatee);
    }

    /// @inheritdoc IDelegationContract
    function changeAdmin(address _newAdmin) external onlyAdmin {
        if (_newAdmin == address(0)) revert ZeroAddress();
        if (_newAdmin == admin) revert SameAdmin();
        if (_newAdmin == delegatee) revert AdminCannotBeDelegatee();

        address oldAdmin = admin;
        admin = _newAdmin;
        emit AdminChanged(oldAdmin, _newAdmin);
    }

    /// @inheritdoc IDelegationContract
    /// @dev Validates that the signature was created by the current delegatee
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue) {
        if (delegatee == address(0)) return EIP1271_INVALID;

        address recovered = hash.recover(signature);

        if (recovered == address(0)) return EIP1271_INVALID;

        if (recovered == delegatee) {
            return EIP1271_MAGIC_VALUE;
        }

        return EIP1271_INVALID;
    }

    /// @inheritdoc IDelegationContract
    /// @dev Only the delegatee can execute calls through this contract.
    ///      Uses a regular call so that msg.sender to the target is this contract's address.
    function execute(bytes calldata data) external onlyDelegatee returns (bytes memory result) {
        (address target, bytes memory callData) = abi.decode(data, (address, bytes));

        if (target == address(0)) revert ZeroAddress();
        if (target == address(this)) revert CannotCallSelf();
        if (target.code.length == 0) revert TargetNotContract();

        bool success;
        // solhint-disable-next-line avoid-low-level-calls
        (success, result) = target.call(callData);

        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // Bubble up the revert reason from the target contract
                revert(add(result, 32), mload(result))
            }
        }
    }
}
