import pytest
from ape import networks

from services import FactoryDeployerService


def pytest_configure(config):
    config.addinivalue_line("markers", "fork: run test with mainnet fork")


@pytest.fixture(autouse=True)
def _fork_context(request):
    """Auto-apply mainnet fork context for tests marked with @pytest.mark.fork."""
    if request.node.get_closest_marker("fork"):
        with networks.ethereum.mainnet_fork.use_provider("foundry"):
            yield
    else:
        yield


@pytest.fixture
def deployer(accounts):
    """Pre-funded test account for deploying contracts."""
    return accounts[0]


@pytest.fixture
def admin(accounts):
    """Account to act as delegation contract admin."""
    return accounts[1]


@pytest.fixture
def delegatee(accounts):
    """Account to act as delegation contract delegatee."""
    return accounts[2]


@pytest.fixture
def delegation_factory_contract(deployer):
    """Deploy DelegationFactory via FactoryDeployerService."""
    result = FactoryDeployerService(deployer).execute()
    return result.contract


@pytest.fixture
def delegation_contract(delegation_factory_contract, admin, delegatee, project):
    """Deploy DelegationContract via factory."""
    tx = delegation_factory_contract.deployDelegation(
        admin.address, delegatee.address, sender=admin
    )
    return project.DelegationContract.at(tx.return_value)
