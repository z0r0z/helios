// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Modern and gas-optimized ERC-1155 implementation.
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
abstract contract ERC1155 {
    /*///////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);

    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] amounts);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*///////////////////////////////////////////////////////////////
                            ERC1155 STORAGE
    //////////////////////////////////////////////////////////////*/

    string public baseURI;

    string public name = "Helios";

    mapping (address => mapping(uint256 => uint256)) internal balances;

    mapping (address => mapping(address => bool)) internal operators;

    /*///////////////////////////////////////////////////////////////
                            EIP-2612-LIKE STORAGE
    //////////////////////////////////////////////////////////////*/
    
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256('Permit(address spender,uint256 id,uint256 nonce,uint256 deadline)');

    bytes32 public constant PERMIT_ALL_TYPEHASH = 
        keccak256('Permit(address owner,address spender,uint256 nonce,uint256 deadline)');
    
    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(uint256 => uint256) public nonces;

    mapping(address => uint256) public noncesForAll;

    /*///////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error ArrayParity();

    error InvalidOperator();

    error NullAddress();

    error InvalidReceiver();

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor() {
        INITIAL_CHAIN_ID = block.chainid;

        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /*///////////////////////////////////////////////////////////////
                            ERC1155 LOGIC
    //////////////////////////////////////////////////////////////*/

    /* GETTERS */

    function balanceOf(address owner, uint256 id) external view returns (uint256 balance) {
        balance = balances[owner][id];
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids) external view returns (uint256[] memory batchBalances) {
        if (owners.length != ids.length) revert ArrayParity();

        batchBalances = new uint256[](owners.length);

        for (uint256 i = 0; i < owners.length; i++) {
            batchBalances[i] = balances[owners[i]][ids[i]];
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool supported) {
        supported = interfaceId == 0xd9b67a26 || interfaceId == 0x0e89341c;
    }

    function uri(uint256) external view returns (string memory meta) {
        meta = baseURI;
    }

    /* APPROVALS */

    function isApprovedForAll(address owner, address operator) public view returns (bool isOperator) {
        isOperator = operators[owner][operator];
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        operators[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /* TRANSFERS */

    function safeTransferFrom(
        address from, 
        address to, 
        uint256 id, 
        uint256 amount, 
        bytes calldata data
    ) external {
        if (msg.sender != from || !isApprovedForAll(from, msg.sender)) revert InvalidOperator();

        if (to == address(0)) revert NullAddress();

        balances[from][id] = balances[from][id] - amount;

        balances[to][id] = balances[to][id] + amount;

        _callonERC1155Received(from, to, id, amount, gasleft(), data);

        emit TransferSingle(msg.sender, from, to, id, amount);
    }

    function safeBatchTransferFrom(
        address from, 
        address to, 
        uint256[] calldata ids, 
        uint256[] calldata amounts, 
        bytes calldata data
    ) external {
        if (msg.sender != from || !isApprovedForAll(from, msg.sender)) revert InvalidOperator();

        if (to == address(0)) revert NullAddress();

        if (ids.length != amounts.length) revert ArrayParity();

        for (uint256 i = 0; i < ids.length; i++) {
            balances[from][ids[i]] = balances[from][ids[i]] - amounts[i];

            balances[to][ids[i]] = balances[to][ids[i]] + amounts[i];
        }

        _callonERC1155BatchReceived(from, to, ids, amounts, gasleft(), data);

        emit TransferBatch(msg.sender, from, to, ids, amounts);
    }

    function _callonERC1155Received(
        address from, 
        address to, 
        uint256 id, 
        uint256 amount, 
        uint256 gasLimit, 
        bytes calldata data
    ) internal view {
        if (to.code.length != 0) {
            // selector = `bytes4(keccak256('onERC1155Received(address,address,uint256,uint256,bytes)'))`
            (, bytes memory returned) = to.staticcall{gas: gasLimit}(abi.encodeWithSelector(0xf23a6e61,
                msg.sender, from, id, amount, data));
                
            bytes4 selector = abi.decode(returned, (bytes4));

            if (selector != 0xf23a6e61) revert InvalidReceiver();
        }
    }

    function _callonERC1155BatchReceived(
        address from, 
        address to, 
        uint256[] calldata ids, 
        uint256[] calldata amounts, 
        uint256 gasLimit, 
        bytes calldata data
    ) internal view {
        if (to.code.length != 0) {
            // selector = `bytes4(keccak256('onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)'))`
            (, bytes memory returned) = to.staticcall{gas: gasLimit}(abi.encodeWithSelector(0xbc197c81,
                msg.sender, from, ids, amounts, data));
                
            bytes4 selector = abi.decode(returned, (bytes4));

            if (selector != 0xbc197c81) revert InvalidReceiver();
        }
    }

    /*///////////////////////////////////////////////////////////////
                            EIP-2612-LIKE LOGIC
    //////////////////////////////////////////////////////////////*/
    
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32 domainSeparator) {
        domainSeparator = block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32 domainSeparator) {
        domainSeparator = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                block.chainid,
                address(this)
            )
        );
    }

    /*///////////////////////////////////////////////////////////////
                            MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(
        address to, 
        uint256 id, 
        uint256 amount, 
        bytes calldata data
    ) internal {
        balances[to][id] += amount;

        if (to.code.length != 0) _callonERC1155Received(address(0), to, id, amount, gasleft(), data);

        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }

    function _batchMint(
        address to, 
        uint256[] calldata ids, 
        uint256[] calldata amounts, 
        bytes calldata data
    ) internal {
        if (ids.length != amounts.length) revert ArrayParity();

        for (uint256 i = 0; i < ids.length; i++) {
            balances[to][ids[i]] += amounts[i];
        }

        if (to.code.length != 0) _callonERC1155BatchReceived(address(0x0), to, ids, amounts, gasleft(), data);

        emit TransferBatch(msg.sender, address(0), to, ids, amounts);
    }

    function _burn(
        address from, 
        uint256 id, 
        uint256 amount
    ) internal {
        balances[from][id] -= amount;

        emit TransferSingle(msg.sender, from, address(0x0), id, amount);
    }

    function _batchBurn(
        address from, 
        uint256[] calldata ids, 
        uint256[] calldata amounts
    ) internal {
        if (ids.length != amounts.length) revert ArrayParity();

        for (uint256 i = 0; i < ids.length; i++) {
            balances[from][ids[i]] -= amounts[i];
        }

        emit TransferBatch(msg.sender, from, address(0x0), ids, amounts);
    }
}
