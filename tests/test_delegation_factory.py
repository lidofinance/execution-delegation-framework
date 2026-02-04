import ape
import pytest
from ape import project

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"


@pytest.mark.fork
class TestDelegationFactory:
    def test_deploy_delegation__valid_admin_and_delegatee__creates_contract(
        self, delegation_factory_contract, admin, delegatee
    ):
        tx = delegation_factory_contract.deployDelegation(
            admin.address, delegatee.address, sender=admin
        )
        delegation_address = tx.return_value

        delegation = project.DelegationContract.at(delegation_address)
        assert delegation.admin() == admin.address
        assert delegation.delegatee() == delegatee.address

        logs = list(tx.decode_logs(delegation_factory_contract.DelegationDeployed))
        assert len(logs) == 1
        assert logs[0].admin == admin.address
        assert logs[0].delegation == delegation_address

    def test_deploy_delegation__zero_delegatee__creates_contract_without_delegatee(
        self, delegation_factory_contract, admin
    ):
        tx = delegation_factory_contract.deployDelegation(admin.address, ZERO_ADDRESS, sender=admin)
        delegation_address = tx.return_value

        delegation = project.DelegationContract.at(delegation_address)
        assert delegation.admin() == admin.address
        assert delegation.delegatee() == ZERO_ADDRESS

    def test_deploy_delegation__zero_admin__reverts(self, delegation_factory_contract, delegatee):
        with ape.reverts(project.DelegationContract.ZeroAddress):
            delegation_factory_contract.deployDelegation(
                ZERO_ADDRESS, delegatee.address, sender=delegatee
            )

    def test_deploy_delegation__admin_equals_delegatee__reverts(
        self, delegation_factory_contract, admin
    ):
        with ape.reverts(project.DelegationContract.AdminCannotBeDelegatee):
            delegation_factory_contract.deployDelegation(admin.address, admin.address, sender=admin)

    def test_deploy_delegation__multiple_deployments__creates_unique_contracts(
        self, delegation_factory_contract, admin, delegatee, deployer
    ):
        tx1 = delegation_factory_contract.deployDelegation(
            admin.address, delegatee.address, sender=admin
        )
        tx2 = delegation_factory_contract.deployDelegation(
            deployer.address, admin.address, sender=deployer
        )

        delegation1_address = tx1.return_value
        delegation2_address = tx2.return_value

        assert delegation1_address != delegation2_address

        delegation1 = project.DelegationContract.at(delegation1_address)
        delegation2 = project.DelegationContract.at(delegation2_address)

        assert delegation1.admin() == admin.address
        assert delegation2.admin() == deployer.address
