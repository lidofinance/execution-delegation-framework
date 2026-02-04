from typing import Any, ContextManager

from ape.contracts import ContractContainer, ContractInstance

class ProjectManager:
    DelegationFactory: ContractContainer
    DelegationContract: ContractContainer

class NetworkManager:
    ethereum: "EthereumNetwork"

class EthereumNetwork:
    mainnet_fork: "NetworkAPI"

class NetworkAPI:
    def use_provider(self, provider: str) -> ContextManager[Any]: ...

class CompilerManager:
    def compile_source(
        self, compiler: str, source: str, contractName: str = ...
    ) -> ContractContainer: ...

project: ProjectManager
networks: NetworkManager
compilers: CompilerManager

def reverts(*args: Any, **kwargs: Any) -> ContextManager[Any]: ...
