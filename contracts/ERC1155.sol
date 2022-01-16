// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.4;

/// @notice A generic interface for a contract which properly accepts ERC1155 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
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

/// @notice Modern and gas-optimized ERC-1155 implementation.
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
abstract contract ERC1155 {
    /*///////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*///////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error ArrayParity();

    error InvalidOperator();

    error InvalidReceiver();

    error SigExpired();

    error InvalidSig();

    error InvalidSigner();

    /*///////////////////////////////////////////////////////////////
                            ERC-1155 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*///////////////////////////////////////////////////////////////
                            EIP-2612-LIKE STORAGE
    //////////////////////////////////////////////////////////////*/
    
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256('Permit(address owner,address operator,bool approved,uint256 nonce,uint256 deadline)');
    
    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*///////////////////////////////////////////////////////////////
                            METADATA
    //////////////////////////////////////////////////////////////*/

    string public baseURI = "PLACEHOLDER";

    string public constant name = "Helios";

    string public constant symbol = "HELI";

    /*///////////////////////////////////////////////////////////////
                            SUPPLY STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => uint256) totalSupplyForId;

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor() {
        INITIAL_CHAIN_ID = block.chainid;

        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /*///////////////////////////////////////////////////////////////
                            ERC-1155 LOGIC
    //////////////////////////////////////////////////////////////*/

    function balanceOfBatch(address[] memory owners, uint256[] memory ids)
        public
        view
        virtual
        returns (uint256[] memory balances)
    {
        uint256 ownersLength = owners.length; // saves MLOADs

        if (owners.length != ids.length) revert ArrayParity();

        balances = new uint256[](owners.length);

        // unchecked because the only math done is incrementing
        // the array index counter which cannot possibly overflow
        unchecked {
            for (uint256 i = 0; i < ownersLength; i++) {
                balances[i] = balanceOf[owners[i]][ids[i]];
            }
        }
    }

    function uri(uint256) public view virtual returns (string memory) {
        return baseURI;
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual {
        if (msg.sender != from || !isApprovedForAll[from][msg.sender]) revert InvalidOperator();

        balanceOf[from][id] -= amount;

        balanceOf[to][id] += amount;

        emit TransferSingle(msg.sender, from, to, id, amount);

        if (to.code.length != 0 &&
            ERC1155TokenReceiver(to).onERC1155Received(msg.sender, from, id, amount, data) !=
                ERC1155TokenReceiver.onERC1155Received.selector
        ) revert InvalidReceiver();
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual {
        uint256 idsLength = ids.length; // saves MLOADs

        if (idsLength != amounts.length) revert ArrayParity();

        if (msg.sender != from || !isApprovedForAll[from][msg.sender]) revert InvalidOperator();

        for (uint256 i = 0; i < idsLength; ) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            balanceOf[from][id] -= amount;
            balanceOf[to][id] += amount;

            // an array can't have a total length
            // larger than the max uint256 value
            unchecked {
                i++;
            }
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        if (to.code.length != 0 &&
            ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data) !=
                ERC1155TokenReceiver.onERC1155BatchReceived.selector
        ) revert InvalidReceiver();
    }

    /*///////////////////////////////////////////////////////////////
                            EIP-2612-LIKE LOGIC
    //////////////////////////////////////////////////////////////*/
    
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) {
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

    function permit(
        address owner,
        address operator,
        bool approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) revert SigExpired();
   
        // this is reasonably safe from overflow because incrementing `nonces` beyond
        // 'type(uint256).max' is exceedingly unlikely compared to optimization benefits
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    '\x19\x01',
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, operator, approved, nonces[owner]++, deadline))
                )
            );

            address recoveredAddress = ecrecover(digest, v, r, s);

            if (recoveredAddress == address(0)) revert InvalidSig();

            if (recoveredAddress != owner) revert InvalidSigner();
        }

        isApprovedForAll[owner][operator] = approved;

        emit ApprovalForAll(owner, operator, approved);
    }

    /*///////////////////////////////////////////////////////////////
                              ERC-165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC-165 Interface ID for ERC-165
            interfaceId == 0xd9b67a26 || // ERC-165 Interface ID for ERC-1155
            interfaceId == 0x0e89341c; // ERC-165 Interface ID for ERC-1155 MetadataURI
    }

    /*///////////////////////////////////////////////////////////////
                            MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal {
        balanceOf[to][id] += amount;

        totalSupplyForId[id] += amount;

        emit TransferSingle(msg.sender, address(0), to, id, amount);

        if (to.code.length != 0 &&
            ERC1155TokenReceiver(to).onERC1155Received(msg.sender, address(0), id, amount, data) !=
                ERC1155TokenReceiver.onERC1155Received.selector
        ) revert InvalidReceiver();
    }

    function _batchMint(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal {
        uint256 idsLength = ids.length; // saves MLOADs

        require(idsLength == amounts.length, "LENGTH_MISMATCH");

        for (uint256 i = 0; i < idsLength; ) {
            balanceOf[to][ids[i]] += amounts[i];

            // an array can't have a total length
            // larger than the max uint256 value
            unchecked {
                i++;
            }

            totalSupplyForId[ids[i]] += amounts[i];
        }

        emit TransferBatch(msg.sender, address(0), to, ids, amounts);

        if (to.code.length != 0 &&
            ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, address(0), ids, amounts, data) !=
                ERC1155TokenReceiver.onERC1155Received.selector
        ) revert InvalidReceiver();
    }

    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) internal {
        balanceOf[from][id] -= amount;

        totalSupplyForId[id] -= amount;

        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }

    function _batchBurn(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal {
        uint256 idsLength = ids.length; // Saves MLOADs.

        require(idsLength == amounts.length, "LENGTH_MISMATCH");

        for (uint256 i = 0; i < idsLength; ) {
            balanceOf[from][ids[i]] -= amounts[i];

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                i++;
            }

            totalSupplyForId[ids[i]] -= amounts[i];
        }

        emit TransferBatch(msg.sender, from, address(0), ids, amounts);
    }
}
