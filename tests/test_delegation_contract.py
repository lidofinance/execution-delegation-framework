import ape
import pytest
from ape import compilers, project
from eth_abi.abi import encode
from eth_account import Account

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
EIP1271_MAGIC_VALUE = "0x1626ba7e"
EIP1271_INVALID = "0xffffffff"

MOCK_HASH_CONSENSUS_SOURCE = """
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract MockHashConsensus {
    mapping(address => bool) public members;
    mapping(uint256 => mapping(address => bytes32)) public reports;

    event MemberAdded(address indexed addr);
    event ReportSubmitted(uint256 indexed slot, address indexed member, bytes32 report);

    error NotMember();

    function addMember(address addr) external {
        members[addr] = true;
        emit MemberAdded(addr);
    }

    function getIsMember(address addr) external view returns (bool) {
        return members[addr];
    }

    function submitReport(uint256 slot, bytes32 report, uint256 consensusVersion) external {
        if (!members[msg.sender]) revert NotMember();
        reports[slot][msg.sender] = report;
        emit ReportSubmitted(slot, msg.sender, report);
    }
}
"""


@pytest.fixture
def mock_hash_consensus(deployer):
    """Deploy MockHashConsensus contract compiled from source."""
    container = compilers.compile_source(
        "solidity",
        MOCK_HASH_CONSENSUS_SOURCE,
        contractName="MockHashConsensus",
    )
    return container.deploy(sender=deployer)


@pytest.mark.fork
class TestAssignDelegate:
    def test_assign_delegate__valid_delegate__updates_delegatee(
        self, delegation_contract, admin, accounts
    ):
        new_delegatee = accounts[3]

        tx = delegation_contract.assignDelegate(new_delegatee.address, sender=admin)

        assert delegation_contract.delegatee() == new_delegatee.address
        logs = list(tx.decode_logs(delegation_contract.DelegateAssigned))
        assert len(logs) == 1
        assert logs[0].delegate == new_delegatee.address

    def test_assign_delegate__zero_address__reverts(self, delegation_contract, admin):
        with ape.reverts(project.DelegationContract.ZeroAddress):
            delegation_contract.assignDelegate(ZERO_ADDRESS, sender=admin)

    def test_assign_delegate__same_delegatee__reverts(self, delegation_contract, admin, delegatee):
        with ape.reverts(project.DelegationContract.SameDelegatee):
            delegation_contract.assignDelegate(delegatee.address, sender=admin)

    def test_assign_delegate__admin_as_delegatee__reverts(self, delegation_contract, admin):
        with ape.reverts(project.DelegationContract.AdminCannotBeDelegatee):
            delegation_contract.assignDelegate(admin.address, sender=admin)

    def test_assign_delegate__not_admin__reverts(self, delegation_contract, delegatee, accounts):
        new_delegatee = accounts[3]
        with ape.reverts(project.DelegationContract.NotAdmin):
            delegation_contract.assignDelegate(new_delegatee.address, sender=delegatee)


@pytest.mark.fork
class TestRevokeDelegate:
    def test_revoke_delegate__has_delegatee__clears_delegatee(
        self, delegation_contract, admin, delegatee
    ):
        tx = delegation_contract.revokeDelegate(sender=admin)

        assert delegation_contract.delegatee() == ZERO_ADDRESS
        logs = list(tx.decode_logs(delegation_contract.DelegateRevoked))
        assert len(logs) == 1
        assert logs[0].delegate == delegatee.address

    def test_revoke_delegate__no_delegatee__reverts(self, delegation_factory_contract, admin):
        tx = delegation_factory_contract.deployDelegation(admin.address, ZERO_ADDRESS, sender=admin)
        delegation = project.DelegationContract.at(tx.return_value)

        with ape.reverts(project.DelegationContract.NoDelegatee):
            delegation.revokeDelegate(sender=admin)

    def test_revoke_delegate__not_admin__reverts(self, delegation_contract, delegatee):
        with ape.reverts(project.DelegationContract.NotAdmin):
            delegation_contract.revokeDelegate(sender=delegatee)


@pytest.mark.fork
class TestChangeAdmin:
    def test_change_admin__valid_new_admin__updates_admin(
        self, delegation_contract, admin, accounts
    ):
        new_admin = accounts[3]

        tx = delegation_contract.changeAdmin(new_admin.address, sender=admin)

        assert delegation_contract.admin() == new_admin.address
        logs = list(tx.decode_logs(delegation_contract.AdminChanged))
        assert len(logs) == 1
        assert logs[0].oldAdmin == admin.address
        assert logs[0].newAdmin == new_admin.address

    def test_change_admin__zero_address__reverts(self, delegation_contract, admin):
        with ape.reverts(project.DelegationContract.ZeroAddress):
            delegation_contract.changeAdmin(ZERO_ADDRESS, sender=admin)

    def test_change_admin__same_admin__reverts(self, delegation_contract, admin):
        with ape.reverts(project.DelegationContract.SameAdmin):
            delegation_contract.changeAdmin(admin.address, sender=admin)

    def test_change_admin__not_admin__reverts(self, delegation_contract, delegatee, accounts):
        new_admin = accounts[3]
        with ape.reverts(project.DelegationContract.NotAdmin):
            delegation_contract.changeAdmin(new_admin.address, sender=delegatee)


@pytest.mark.fork
class TestIsValidSignature:
    def test_is_valid_signature__valid_signature__returns_magic_value(
        self, delegation_contract, delegatee
    ):
        message_hash = b"\x11" * 32
        private_key = delegatee.private_key
        acc = Account.from_key(private_key)
        signed = acc.unsafe_sign_hash(message_hash)

        result = delegation_contract.isValidSignature(message_hash, signed.signature)

        assert result.hex() == EIP1271_MAGIC_VALUE[2:]

    def test_is_valid_signature__invalid_signature__returns_invalid(
        self, delegation_contract, admin
    ):
        message_hash = b"\x11" * 32
        private_key = admin.private_key
        acc = Account.from_key(private_key)
        signed = acc.unsafe_sign_hash(message_hash)

        result = delegation_contract.isValidSignature(message_hash, signed.signature)

        assert result.hex() == EIP1271_INVALID[2:]

    def test_is_valid_signature__no_delegatee__returns_invalid(
        self, delegation_factory_contract, admin
    ):
        tx = delegation_factory_contract.deployDelegation(admin.address, ZERO_ADDRESS, sender=admin)
        delegation = project.DelegationContract.at(tx.return_value)

        message_hash = b"\x11" * 32
        private_key = admin.private_key
        acc = Account.from_key(private_key)
        signed = acc.unsafe_sign_hash(message_hash)

        result = delegation.isValidSignature(message_hash, signed.signature)

        assert result.hex() == EIP1271_INVALID[2:]


@pytest.mark.fork
class TestExecute:
    def test_execute__submit_report_as_member__succeeds(
        self, delegation_contract, mock_hash_consensus, delegatee, deployer
    ):
        # Add delegation contract as member
        mock_hash_consensus.addMember(delegation_contract.address, sender=deployer)

        # Prepare submitReport call
        slot = 123
        report = b"\x01" * 32
        consensus_version = 1
        call_data = mock_hash_consensus.submitReport.encode_input(slot, report, consensus_version)
        data = encode(["address", "bytes"], [mock_hash_consensus.address, call_data])

        # Execute via delegation
        delegation_contract.execute(data, sender=delegatee)

        # Verify report was submitted from delegation contract
        assert mock_hash_consensus.reports(slot, delegation_contract.address) == report

    def test_execute__zero_target__reverts(self, delegation_contract, delegatee):
        data = encode(["address", "bytes"], [ZERO_ADDRESS, b""])

        with ape.reverts(project.DelegationContract.ZeroAddress):
            delegation_contract.execute(data, sender=delegatee)

    def test_execute__self_call__reverts(self, delegation_contract, delegatee):
        data = encode(["address", "bytes"], [delegation_contract.address, b""])

        with ape.reverts(project.DelegationContract.CannotCallSelf):
            delegation_contract.execute(data, sender=delegatee)

    def test_execute__non_contract_target__reverts(self, delegation_contract, delegatee):
        # Use a random address that definitely has no code
        random_eoa = "0x1234567890123456789012345678901234567890"
        data = encode(["address", "bytes"], [random_eoa, b""])

        with ape.reverts(project.DelegationContract.TargetNotContract):
            delegation_contract.execute(data, sender=delegatee)

    def test_execute__not_delegatee__reverts(
        self, delegation_contract, mock_hash_consensus, admin, deployer
    ):
        mock_hash_consensus.addMember(delegation_contract.address, sender=deployer)
        call_data = mock_hash_consensus.submitReport.encode_input(123, b"\x01" * 32, 1)
        data = encode(["address", "bytes"], [mock_hash_consensus.address, call_data])

        with ape.reverts(project.DelegationContract.NotDelegatee):
            delegation_contract.execute(data, sender=admin)

    def test_execute__target_reverts__bubbles_up_error(
        self, delegation_contract, mock_hash_consensus, delegatee
    ):
        # Don't add delegation as member - submitReport should revert with NotMember
        call_data = mock_hash_consensus.submitReport.encode_input(123, b"\x01" * 32, 1)
        data = encode(["address", "bytes"], [mock_hash_consensus.address, call_data])

        with ape.reverts():
            delegation_contract.execute(data, sender=delegatee)

    def test_execute__submit_report__caller_is_delegation_not_hot_key(
        self, delegation_contract, mock_hash_consensus, delegatee, deployer
    ):
        mock_hash_consensus.addMember(delegation_contract.address, sender=deployer)

        slot = 456
        report = b"\xab" * 32
        consensus_version = 1
        call_data = mock_hash_consensus.submitReport.encode_input(slot, report, consensus_version)
        data = encode(["address", "bytes"], [mock_hash_consensus.address, call_data])

        tx = delegation_contract.execute(data, sender=delegatee)

        logs = list(tx.decode_logs(mock_hash_consensus.ReportSubmitted))
        assert len(logs) == 1
        assert logs[0].member == delegation_contract.address
        assert logs[0].member != delegatee.address
