// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {CCIPReceiver} from "ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "ccip/src/v0.8/ccip/libraries/Client.sol";
import {OwnerIsCreator} from "ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC20} from "ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IXERC20} from "xERC20/solidity/interfaces/IXERC20.sol";
import {IXERC20Lockbox} from "xERC20/solidity/interfaces/IXERC20Lockbox.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/// @title - A simple messenger contract for sending/receving string data across chains.
contract CCIPxERC20Bridge is CCIPReceiver, OwnerIsCreator {
    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error SenderNotAllowlistedBySourceChain(
        uint64 sourceChainSelector,
        address sender
    ); // Used when the sender has not been allowlisted by the contract owner.
    error NoReceiverForDestinationChain(uint64 destinationChainSelector); // Used when the receiver has not been allowlisted by the contract owner.

    // Event emitted when a message is sent to another chain.
    event MessageSent(
        // The unique ID of the CCIP message.
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address recipient,
        uint256 amount,
        address feeToken,
        uint256 fees
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        // The unique ID of the CCIP message.
        // The chain selector of the source chain.
        // The address of the sender from the source chain.
        // The text that was received.
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        uint256 amount,
        address recipient
    );

    bytes32 private _lastReceivedMessageId; // Store the last received messageId.
    string private _lastReceivedText; // Store the last received text.

    // Mapping to keep track of allowlisted senders by source chain.
    mapping(uint64 => address) public bridgesByChain;

    IERC20 public linkToken;

    struct XERC20Config {
        IERC20 erc20;
        IXERC20Lockbox lockbox;
    }

    mapping(IXERC20 => XERC20Config) public xerc20s;

    mapping(uint64 => mapping(address => address)) public xerc20sByChain;

    mapping(uint32 => uint64) public chainIdToChainSelector;

    uint256 public feeBps; // fee in basis pts, i.e. 10 = 0.1%

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(
        address _router,
        address _link,
        uint256 _feeBps
    ) CCIPReceiver(_router) {
        linkToken = IERC20(_link);
        feeBps = _feeBps;

        // testnets
        chainIdToChainSelector[11_155_111] = 16_015_286_601_757_825_753;
        chainIdToChainSelector[421_614] = 3_478_487_238_524_512_106;
        chainIdToChainSelector[80_001] = 12_532_609_583_862_916_517;

        // mainnets
        chainIdToChainSelector[1] = 5_009_297_550_715_157_269;
        chainIdToChainSelector[10] = 3_734_403_246_176_062_136;
        chainIdToChainSelector[56] = 11_344_663_589_394_136_015;
        chainIdToChainSelector[137] = 4_051_577_828_743_386_545;
        chainIdToChainSelector[8453] = 15_971_525_489_660_198_786;
        chainIdToChainSelector[43_114] = 6_433_500_567_565_415_381;
        chainIdToChainSelector[42_161] = 4_949_039_107_694_359_620;
    }

    /// @dev Modifier to make a function callable only when the sender is allowlisted by the contract owner.
    modifier onlyAllowlistedSenderBySourceChain(
        uint64 _sourceChainSelector,
        address _sender
    ) {
        if (bridgesByChain[_sourceChainSelector] != _sender) {
            revert SenderNotAllowlistedBySourceChain(
                _sourceChainSelector,
                _sender
            );
        }
        _;
    }

    modifier validReceiver(uint64 _destinationChainSelector) {
        if (bridgesByChain[_destinationChainSelector] == address(0)) {
            revert NoReceiverForDestinationChain(_destinationChainSelector);
        }
        _;
    }

    function addXERC20ForOriginChain(
        uint64 _chainSelector,
        address _xerc20remote,
        address _xerc20local
    ) external onlyOwner {
        xerc20sByChain[_chainSelector][_xerc20remote] = _xerc20local;
    }

    function addXERC20Config(
        IXERC20 _xerc20,
        IERC20 _erc20,
        IXERC20Lockbox _lockbox
    ) external onlyOwner {
        xerc20s[IXERC20(_xerc20)] = XERC20Config({
            erc20: IERC20(_erc20),
            lockbox: IXERC20Lockbox(_lockbox)
        });
    }

    function addBridgeForChain(
        uint64 _chainSelector,
        address _bridge
    ) external onlyOwner {
        bridgesByChain[_chainSelector] = _bridge;
    }

    function addChainIdToChainSelector(
        uint32 _chainId,
        uint64 _chainSelector
    ) external onlyOwner {
        chainIdToChainSelector[_chainId] = _chainSelector;
    }

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        feeBps = _feeBps;
    }

    function getFee(
        address _xerc20,
        uint32 _destinationChainId,
        uint256 _amount,
        bool _feeInLINK
    ) external view returns (uint256) {
        uint64 _destinationChainSelector = chainIdToChainSelector[
            _destinationChainId
        ];
        address _receiver = bridgesByChain[_destinationChainSelector];
        IRouterClient router = IRouterClient(this.getRouter());
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _xerc20,
            _receiver,
            _amount,
            msg.sender,
            _feeInLINK ? address(linkToken) : address(0)
        );
        return router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    function bridgeTokens(
        address _xerc20,
        uint32 _destinationChainId,
        address _receipient,
        uint256 _amount
    ) external payable returns (bytes32 messageId) {
        return
            _bridgeTokens(
                _xerc20,
                _destinationChainId,
                _receipient,
                _amount,
                false
            );
    }

    function bridgeTokensWithLINK(
        address _xerc20,
        uint32 _destinationChainId,
        address _receipient,
        uint256 _amount
    ) external returns (bytes32 messageId) {
        return
            _bridgeTokens(
                _xerc20,
                _destinationChainId,
                _receipient,
                _amount,
                true
            );
    }

    function _bridgeTokens(
        address _xerc20,
        uint32 _destinationChainId,
        address _receipient,
        uint256 _amount,
        bool _feeInLINK
    )
        internal
        validReceiver(chainIdToChainSelector[_destinationChainId])
        returns (bytes32 messageId)
    {
        uint64 _destinationChainSelector = chainIdToChainSelector[
            _destinationChainId
        ];
        address _receiver = bridgesByChain[_destinationChainSelector];

        if (address(xerc20s[IXERC20(_xerc20)].lockbox) == address(0)) {
            // no lockbox, use xerc20 directly
            IERC20(address(_xerc20)).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
        } else {
            // transfer erc20 here then lock it in lockbox
            xerc20s[IXERC20(_xerc20)].erc20.transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            xerc20s[IXERC20(_xerc20)].erc20.approve(
                address(xerc20s[IXERC20(_xerc20)].lockbox),
                _amount
            );
            // deposit to lockbox
            xerc20s[IXERC20(_xerc20)].lockbox.deposit(_amount);
            // xerc20 will be minted to this contract
        }

        // Burn the tokens minus the fee
        uint256 _bridgedAmount = _amount - ((_amount * feeBps) / 10_000);
        IXERC20(_xerc20).burn(address(this), _bridgedAmount);

        address _feeToken = _feeInLINK ? address(linkToken) : address(0);

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _xerc20,
            _receiver,
            _bridgedAmount,
            _receipient,
            _feeToken
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (_feeInLINK) {
            linkToken.transferFrom(msg.sender, address(this), fees);
            linkToken.approve(address(router), fees);
        } else {
            if (msg.value < fees) {
                revert NotEnoughBalance(address(this).balance, fees);
            }
            uint256 _refund = msg.value - fees;
            if (_refund > 0) {
                payable(msg.sender).transfer(_refund);
            }
        }
        // Send the CCIP message through the router and store the returned CCIP message ID
        messageId = router.ccipSend{value: _feeInLINK ? 0 : fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );

        // Emit an event with message details
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _receipient,
            _bridgedAmount,
            _feeToken,
            fees
        );

        // Return the CCIP message ID
        return messageId;
    }

    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlistedSenderBySourceChain(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        ) // Make sure source chain and sender are allowlisted
    {
        _lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        (address _xerc20, uint256 _amount, address _recipient) = abi.decode(
            any2EvmMessage.data,
            (address, uint256, address)
        ); // abi-decoding of the sent text

        address localXERC20 = xerc20sByChain[
            any2EvmMessage.sourceChainSelector
        ][address(_xerc20)];

        XERC20Config memory xerc20Config = xerc20s[IXERC20(localXERC20)];

        if (address(xerc20Config.lockbox) == address(0)) {            // no lockbox, mint directly to recipient
            IXERC20(localXERC20).mint(_recipient, _amount);

        } else {            // withdraw from lockbox
            // mint to this contract
            IXERC20(localXERC20).mint(address(this), _amount);
            // withdraw from lockbox, erc20 will be transferred to this contract
            xerc20Config.lockbox.withdraw(_amount);
            // transfer erc20s to recipient
            IERC20(address(xerc20Config.erc20)).transfer(_recipient, _amount);
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            _amount,
            _recipient
        );
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for sending a text.
    /// @param _receiver The address of the receiver on the destination chain.
    /// @param _amount The amount of tokens to be transferred.
    /// @param _receipient The address of the receipient on the destination chain.
    /// @param _feeTokenAddress The address of the token to be used for paying fees.
    function _buildCCIPMessage(
        address _xerc20,
        address _receiver,
        uint256 _amount,
        address _receipient,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), // ABI-encoded receiver address
                data: abi.encode(_xerc20, _amount, _receipient), // ABI-encoded string
                tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array aas no tokens are transferred
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit
                    Client.EVMExtraArgsV1({gasLimit: 200_000})
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: _feeTokenAddress
            });
    }

    /// @notice Fetches the details of the last received message.
    /// @return messageId The ID of the last received message.
    /// @return text The last received text.
    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, string memory text)
    {
        return (_lastReceivedMessageId, _lastReceivedText);
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is sent to the contract without any data.
    receive() external payable {}

    /// @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
    /// @dev This function reverts if there are no funds to withdraw or if the transfer fails.
    /// It should only be callable by the owner of the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    function withdraw(address _beneficiary) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = IERC20(_token).balanceOf(address(this));

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).transfer(_beneficiary, amount);
    }
}
