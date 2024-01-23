// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "@forge/Test.sol";
import {Helios} from "../src/Helios.sol";

contract HeliosTest is Test {
    Helios immutable helios = new Helios();

    function setUp() public payable {
        // vm.createSelectFork(vm.rpcUrl('main')); // Ethereum mainnet fork.
    }

    function testDeploy() public payable {
        new Helios();
    }
}
