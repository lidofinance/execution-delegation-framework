#!/usr/bin/env python3
"""
Deploy DelegationFactory contract.

Usage:
    uv run ape run deploy_factory --network ethereum:mainnet:node
    uv run ape run deploy_factory --network ethereum:hoodi:node --publish
"""

import click
from ape.cli import ConnectedProviderCommand, account_option, network_option

from services import FactoryDeployerService


@click.command(cls=ConnectedProviderCommand)
@network_option(required=True)
@account_option()
@click.option(
    "--publish", is_flag=True, help="Verify and publish contract source on block explorer"
)
def cli(account, publish):
    """Deploy DelegationFactory to the specified network."""
    result = FactoryDeployerService(account).execute(publish=publish)

    click.echo(f"Contract deployed: {result.contract.address}")
    click.echo(f"Transaction: {result.tx_hash}")
