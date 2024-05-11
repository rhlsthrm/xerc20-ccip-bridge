pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Client} from "ccip/src/v0.8/ccip/libraries/Client.sol";
import {Config} from "../script/Deploy.s.sol";
import {CCIPxERC20Bridge} from "../src/CCIPxERC20Bridge.sol";
import {IERC20} from "ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract ForkTest is Config, Test {
    // the identifiers of the forks
    uint256 mainnetFork;
    uint256 baseFork;

    //Access variables from .env file via vm.envString("varname")
    //Replace ALCHEMY_KEY by your alchemy key or Etherscan key, change RPC url if need
    //inside your .env file e.g:
    //MAINNET_RPC_URL = 'https://eth-mainnet.g.alchemy.com/v2/ALCHEMY_KEY'
    string MAINNET_RPC = vm.envString("MAINNET_RPC");
    string BASE_RPC = vm.envString("BASE_RPC");

    address XTOKEN_OWNER = 0xFaDede2cFbfA7443497acacf76cFc4Fe59112DbB;

    // create two _different_ forks during setup
    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC);
        baseFork = vm.createFork(BASE_RPC, 14319053);
    }

    // select a specific fork
    function testBaseDelivery() public {
        Client.EVMTokenAmount[] memory destTokenAmounts;
        // select the fork
        vm.selectFork(baseFork);
        assertEq(vm.activeFork(), baseFork);
        CCIPxERC20Bridge bridge = CCIPxERC20Bridge(ccipBridges[8453]);
        vm.startPrank(0x881e3A65B4d4a04dD529061dd0071cf975F58bCD);
        bridge.ccipReceive(
            Client.Any2EVMMessage({
                messageId: 0xfe0664f09209f5d4b94df216424d59f37e0dd6e735017bf60d5b86e991b6e097,
                sourceChainSelector: bridge.chainIdToChainSelector(1),
                sender: hex"0000000000000000000000003a943e8b77d59d29804c2afa218d7fc7e7d5adca",
                data: hex"00000000000000000000000081a3d0677aef7ff6fbf40e874ddd5e8a94b77ca0000000000000000000000000000000000000000000000003bc9c1b49b4738000000000000000000000000000fadede2cfbfa7443497acacf76cfc4fe59112dbb",
                destTokenAmounts: destTokenAmounts
            })
        );
        vm.stopPrank();
    }

    function testBaseDeliveryNewDeploy() public {
        Client.EVMTokenAmount[] memory destTokenAmounts;
        // select the fork
        vm.selectFork(baseFork);
        assertEq(vm.activeFork(), baseFork);
        vm.selectFork(baseFork);
        assertEq(vm.activeFork(), baseFork);
        CCIPxERC20Bridge bridge = new CCIPxERC20Bridge(
            routers[8453],
            links[8453],
            feeBps
        );
        vm.prank(XTOKEN_OWNER);
        xerc20s[8453].setLimits(address(bridge), 10000000000000 ether, 10000000000000 ether);
        bridge.addXERC20ForOriginChain(
            bridge.chainIdToChainSelector(1),
            address(xerc20s[1]),
            address(xerc20s[8453])
        );
        bridge.addBridgeForChain(
            bridge.chainIdToChainSelector(1),
            ccipBridges[1]
        );

        vm.startPrank(routers[8453]);
        bridge.ccipReceive(
            Client.Any2EVMMessage({
                messageId: 0xfe0664f09209f5d4b94df216424d59f37e0dd6e735017bf60d5b86e991b6e097,
                sourceChainSelector: bridge.chainIdToChainSelector(1),
                sender: hex"0000000000000000000000003a943e8b77d59d29804c2afa218d7fc7e7d5adca",
                data: hex"00000000000000000000000081a3d0677aef7ff6fbf40e874ddd5e8a94b77ca0000000000000000000000000000000000000000000000003bc9c1b49b4738000000000000000000000000000fadede2cfbfa7443497acacf76cfc4fe59112dbb",
                destTokenAmounts: destTokenAmounts
            })
        );
        vm.stopPrank();

        uint balance = IERC20(address(xerc20s[8453])).balanceOf(XTOKEN_OWNER);
        assertGt(balance, 0);
    }
}
