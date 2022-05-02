// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {IHelios, Helios} from '../Helios.sol';
import {XYKswapper} from '../swappers/XYKswapper.sol';

import {ERC20, MockERC20} from '@solmate/test/utils/mocks/MockERC20.sol';

import "@std/Test.sol";

contract HeliosTest is Test {
    Helios helios;
    XYKswapper xykSwapperContract;
    IHelios xykSwapper;
    MockERC20 token0;
    MockERC20 token1;

    /// @dev Users

    uint256 immutable alicesPk = 0x60b919c82f0b4791a5b7c6a7275970ace1748759ebdaa4076d7eeed9dbcff3c3;
    address public immutable alice = 0x503408564C50b43208529faEf9bdf9794c015d52;

    uint256 immutable bobsPk = 0xf8f8a2f43c8376ccb0871305060d7b27b0554d2cc72bccf41b2705608452f315;
    address public immutable bob = 0x001d3F1ef827552Ae1114027BD3ECF1f086bA0F9;

    uint256 immutable charliesPk =
        0xb9dee2522aae4d21136ba441f976950520adf9479a3c0bda0a88ffc81495ded3;
    address public immutable charlie = 0xccc4A5CeAe4D88Caf822B355C02F9769Fb6fd4fd;

    uint256 immutable nullPk =
        0x8b2ed20f3cc3dd482830910365cfa157e7568b9c3fa53d9edd3febd61086b9be;
    address public immutable nully = 0x0ACDf2aC839B7ff4cd5F16e884B2153E902253f2;

    function setUp() public {
        helios = new Helios();
        xykSwapperContract = new XYKswapper();
        xykSwapper = IHelios(address(xykSwapperContract));
        
        token0 = new MockERC20("Token0", "TKN0", 18);
        token1 = new MockERC20("Token1", "TKN1", 18);

        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);

        token0.approve(address(helios), 1_000_000_0 ether);
        token1.approve(address(helios), 1_000_000_0 ether);
    }

    function testHeliosCreation() public {
        helios = new Helios();
    }

    function testXYKpairCreation() public {
        helios.createPair(
            address(this), 
            token0, 
            token1, 
            1_000 ether, 
            1_000 ether, 
            xykSwapper, 
            0, 
            ''
        );
    }
}