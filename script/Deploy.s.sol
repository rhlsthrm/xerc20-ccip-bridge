// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {CCIPxERC20Bridge} from "../src/CCIPxERC20Bridge.sol";
import {IERC20} from "ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IXERC20} from "xERC20/solidity/interfaces/IXERC20.sol";
import {IXERC20Lockbox} from "xERC20/solidity/interfaces/IXERC20Lockbox.sol";
import "forge-std/Test.sol";

contract Config {
    IERC20 _mainnetErc20 = IERC20(0x7D225c4cc612E61d26523B099b0718d03152eDEf);
    IXERC20Lockbox _lockbox =
        IXERC20Lockbox(0x50C7CB0FAC5d72cBF4917E0c013f4785308903D7);

    mapping(uint256 => address) public routers;
    mapping(uint256 => address) public links;
    mapping(uint256 => address payable) public ccipBridges;
    mapping(uint256 => IXERC20) public xerc20s;
    uint256 public feeBps = 10;
    constructor() {
        routers[1] = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
        links[1] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        routers[8453] = 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;
        links[8453] = 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196;
        xerc20s[1] = IXERC20(0x81A3D0677aEf7FF6fbF40e874dDD5E8A94B77ca0);
        xerc20s[8453] = IXERC20(0x6e05b1c7F694Fc383067164a33573b05Ba0500e8);
        ccipBridges[1] = payable(0x77680848810fA3410983abDC5FbF23Ee3cF9E3f1);
        ccipBridges[8453] = payable(0x740De8fE9D75F5eD5585C1e8e5Fd6971844B5689);
    }
}

contract Deploy is Script, Config {
    function setUp() public {}

    function run() public {
        address _router = routers[block.chainid];
        address _link = links[block.chainid];

        vm.startBroadcast();
        new CCIPxERC20Bridge(_router, _link, feeBps);
        vm.stopBroadcast();
    }
}

contract ConfigureMainnet is Script, Config {
    function setUp() public {}

    function run() public {
        CCIPxERC20Bridge _bridge = CCIPxERC20Bridge(ccipBridges[1]);

        vm.startBroadcast();
        xerc20s[1].setLimits(
            address(_bridge),
            10000000000000 ether,
            10000000000000 ether
        );

        _bridge.addXERC20ForOriginChain(
            _bridge.chainIdToChainSelector(8453),
            address(xerc20s[8453]),
            address(xerc20s[1])
        );
        _bridge.addXERC20Config(xerc20s[1], _mainnetErc20, _lockbox);
        _bridge.addBridgeForChain(
            _bridge.chainIdToChainSelector(8453),
            ccipBridges[8453]
        );
        vm.stopBroadcast();
    }
}

contract ConfigureBase is Script, Config {
    function setUp() public {}

    function run() public {
        CCIPxERC20Bridge _bridge = CCIPxERC20Bridge(ccipBridges[8453]);

        vm.startBroadcast();
        xerc20s[8453].setLimits(
            address(_bridge),
            10000000000000 ether,
            10000000000000 ether
        );

        _bridge.addXERC20ForOriginChain(
            _bridge.chainIdToChainSelector(1),
            address(xerc20s[1]),
            address(xerc20s[8453])
        );
        _bridge.addBridgeForChain(
            _bridge.chainIdToChainSelector(1),
            ccipBridges[1]
        );
        vm.stopBroadcast();
    }
}
