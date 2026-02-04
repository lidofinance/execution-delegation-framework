from dataclasses import dataclass

from ape import project
from ape.api import AccountAPI
from ape.contracts import ContractInstance


@dataclass
class DeploymentResult:
    contract: ContractInstance
    deployer_address: str
    tx_hash: str


class FactoryDeployerService:
    def __init__(self, account: AccountAPI):
        self._account = account

    def execute(self, publish: bool = False) -> DeploymentResult:
        factory = project.DelegationFactory.deploy(
            sender=self._account,
            publish=publish,
        )
        return DeploymentResult(
            contract=factory,
            deployer_address=self._account.address,
            tx_hash=factory.txn_hash,
        )
