// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

/// @notice A generic interface for a contract which properly accepts ERC-1155 tokens
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
/// License-Identifier: AGPL-3.0-only
interface ERC1155TokenReceiver {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external returns (bytes4);
}

/// @notice Modern, minimalist, and gas efficient standard ERC-1155 implementation with meta-tx support
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
/// License-Identifier: AGPL-3.0-only
abstract contract HeliosERC1155 {
    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error ArrayParity();
    error InvalidOperator();
    error InvalidReceiver();
    error SigExpired();
    error InvalidSig();

    /// -----------------------------------------------------------------------
    /// ERC-1155 Storage
    /// -----------------------------------------------------------------------

    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /// -----------------------------------------------------------------------
    /// EIP-2612-like Storage
    /// -----------------------------------------------------------------------

    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /// -----------------------------------------------------------------------
    /// Metadata
    /// -----------------------------------------------------------------------

    string public baseURI = "PLACEHOLDER";
    string public constant name = "Helios";
    string public constant symbol = "HELI";

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------
    
    constructor() {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /// -----------------------------------------------------------------------
    /// ERC-165 Logic
    /// -----------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC-165 Interface ID for ERC-165
            interfaceId == 0xd9b67a26 || // ERC-165 Interface ID for ERC-1155
            interfaceId == 0x0e89341c; // ERC-165 Interface ID for ERC-1155 MetadataURI
    }

    /// -----------------------------------------------------------------------
    /// ERC-1155 Logic
    /// -----------------------------------------------------------------------

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory balances)
    {
        uint256 ownersLength = owners.length; // saves MLOADs

        if (ownersLength != ids.length) revert ArrayParity();

        balances = new uint256[](ownersLength);

        for (uint256 i; i < ownersLength;) {
            balances[i] = balanceOf[owners[i]][ids[i]];
            // unchecked because the only math done is incrementing
            // the array index counter which cannot possibly overflow
            unchecked {
                ++i;
            }
        }
    }

    function uri(uint256) external view returns (string memory) {
        return baseURI;
    }

    function setApprovalForAll(address operator, bool approved) external payable {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external payable {
        if (msg.sender != from && !isApprovedForAll[from][msg.sender]) revert InvalidOperator();

        balanceOf[from][id] -= amount;
        balanceOf[to][id] += amount;

        emit TransferSingle(msg.sender, from, to, id, amount);

        if (to.code.length == 0 ? to == address(0) :
            ERC1155TokenReceiver(to).onERC1155Received(msg.sender, from, id, amount, data) !=
                ERC1155TokenReceiver.onERC1155Received.selector
        ) revert InvalidReceiver();
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external payable {
        uint256 idsLength = ids.length; // saves MLOADs

        if (idsLength != amounts.length) revert ArrayParity();
        if (msg.sender != from && !isApprovedForAll[from][msg.sender]) revert InvalidOperator();

        uint256 id;
        uint256 amount;
        for (uint256 i; i < idsLength;) {
            id = ids[i];
            amount = amounts[i];

            balanceOf[from][id] -= amount;
            balanceOf[to][id] += amount;
            // an array can't have a total length
            // larger than the max uint256 value
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        if (to.code.length == 0 ? to == address(0) :
            ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data) !=
                ERC1155TokenReceiver.onERC1155BatchReceived.selector
        ) revert InvalidReceiver();
    }

    /// -----------------------------------------------------------------------
    /// EIP-2612-like Logic
    /// -----------------------------------------------------------------------

    function permit(
        address owner,
        address operator,
        bool approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        if (block.timestamp > deadline) revert SigExpired();
        // unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow
        unchecked {
            address signer = ecrecover(
                keccak256(
                    abi.encodePacked(
                        '\x19\x01',
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(keccak256('Permit(address owner,address operator,bool approved,uint256 nonce,uint256 deadline)'), 
                            owner, operator, approved, ++nonces[owner], deadline))
                    )
                ), 
                v, r, s
            );

            if (signer != owner 
                && !isApprovedForAll[owner][signer]
                || signer == address(0)
            ) revert InvalidSig(); 
        }

        isApprovedForAll[owner][operator] = approved;

        emit ApprovalForAll(owner, operator, approved);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    function _computeDomainSeparator() private view returns (bytes32) {
        return 
            keccak256(
                abi.encode(
                    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                    keccak256(bytes(name)),
                    bytes('1'),
                    block.chainid,
                    address(this)
                )
            );
    }

    /// -----------------------------------------------------------------------
    /// Mint/Burn Logic
    /// -----------------------------------------------------------------------

    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) private {
        balanceOf[to][id] += amount;

        emit TransferSingle(msg.sender, address(0), to, id, amount);

        if (to.code.length == 0 ? to == address(0) :
            ERC1155TokenReceiver(to).onERC1155Received(msg.sender, address(0), id, amount, data) !=
               ERC1155TokenReceiver.onERC1155Received.selector
        ) revert InvalidReceiver();
    }

    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) private {
        balanceOf[from][id] -= amount;
        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }
}
