// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.35;

import { Script } from "forge-std/Script.sol";

import { DelegationFactory } from "../src/DelegationFactory.sol";

import { JsonObj, Json } from "./utils/Json.sol";

abstract contract DeployBase is Script {
    string internal gitRef;
    string internal artifactDir;
    string internal chainName;
    uint256 internal chainId;

    address internal deployer;
    DelegationFactory public delegationFactory;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    }

    function run(string memory _gitRef) external virtual {
        _run(_gitRef, chainId);
    }

    function _run(string memory _gitRef, uint256 _chainId) internal {
        gitRef = _gitRef;
        if (_chainId != block.chainid) revert ChainIdMismatch({ actual: block.chainid, expected: _chainId });
        artifactDir = vm.envOr("ARTIFACTS_DIR", string("./artifacts/local/"));

        vm.startBroadcast();

        (, deployer, ) = vm.readCallers();
        vm.label(deployer, "DEPLOYER");
        // {salt: bytes32(0)}
        delegationFactory = new DelegationFactory();

        JsonObj memory deployJson = Json.newObj("artifact");
        deployJson.set("ChainId", _chainId);
        deployJson.set("DelegationFactory", address(delegationFactory));
        deployJson.set("git-ref", gitRef);
        if (!vm.exists(artifactDir)) {
            vm.createDir(artifactDir, true);
        }
        vm.writeJson(deployJson.str, _deployJsonFilename());

        vm.stopBroadcast();
    }

    function _deployJsonFilename() internal view returns (string memory) {
        return string(abi.encodePacked(artifactDir, "deploy-", chainName, ".json"));
    }
}
