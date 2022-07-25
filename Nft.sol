// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

contract Nft {

    address public _owner;
    constructor(){
        _owner = msg.sender;
    }

    event NewTokenType(address indexed issuer, uint256 indexed id, string indexed uri);
    event Mint(address indexed to, uint256 indexed tokenTypeID, uint256 indexed tokenID, string uri, uint256 mintCount);
    event Transfer(address indexed to, uint256 indexed tokenID, uint256 indexed tokenTypeID);
    event Burn(address indexed authorizer, uint256 indexed tokenID);
    event AddAuthorizedMinter(address indexed authorizedMinter, address indexed authorizedBy, uint256 indexed tokenTypeID);
    event RemoveAuthorizedMinter(address indexed authorizedMinter, address indexed authorizedBy, uint256 indexed tokenTypeID);

    mapping(uint256 => bool) public tokenTypes;
    mapping(uint256 => mapping(address => bool)) public tokenTypeAuthorizedMinters;
    mapping(uint256 => uint256) public tokenTypeMintCount;
    mapping(uint256 => string) public tokenTypeMetadataURI;
    mapping(uint256 => int) public tokenTypeIssuerTransferTakeRate;

    // immutable
    struct Issued {
        uint256 count;
        uint256[] types;
    }
    function getIssued(address issuer) public view returns (uint256[] memory) {
        return issuerTokenTypes[issuer].types;
    }
    mapping(address => Issued) public issuerTokenTypes;

    struct AuthorizedTypes {
        uint256 count;
        uint256[] types;
    }
    mapping(address => AuthorizedTypes) public tokenTypeAuthorized;

    // getAuthorizedTypes Returns all of the token types @param authorizedAddress has been authorized to mint and
    // is currently authorized to mint.
    function getAuthorizedTypes(address authorizedAddress) public view returns (uint256[] memory) {
        AuthorizedTypes memory authorizedTypes = tokenTypeAuthorized[authorizedAddress];
        uint256[] memory currentAuthorizedTypes = new uint256[](authorizedTypes.count);
        uint256 j=0;
        for(uint256 i=0; i < authorizedTypes.types.length; i++) {
            if(tokenTypeAuthorizedMinters[authorizedTypes.types[i]][authorizedAddress]) {
                currentAuthorizedTypes[j++] = authorizedTypes.types[i];
            }
        }

        return currentAuthorizedTypes;
    }

    mapping(uint256 => address) public tokenTypeIssuer;
    mapping(uint256 => bool) public tokens;
    mapping(uint256 => uint256) public tokenTokenType;
    mapping(uint256 => string) public tokenMetadataURI;
    mapping(uint256 => address) public tokenHolder;

    struct Wallet {
        uint256 count;
        uint256[] tokens;
    }
    mapping(address => Wallet) public wallets;

    // getWalletTokens Returns all of the tokens @param owner has and currently has custody of.
    function getWalletTokens(address owner) public view returns (uint256[] memory) {
        Wallet memory wallet = wallets[owner];
        uint256[] memory currentWalletTokens = new uint256[](wallet.count);
        uint256 j=0;
        for(uint256 i=0; i < wallet.tokens.length; i++) {
            if (tokenHolder[wallet.tokens[i]] == owner) {
                currentWalletTokens[j++] = wallet.tokens[i];
            }
        }
        return currentWalletTokens;
    }

    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function burnToken(uint256 tokenID) external {
        require(tokens[tokenID], "token does not exist");
        require(tokenTypeAuthorizedMinters[tokenTokenType[tokenID]][msg.sender], "caller is not authorized for token type");

        delete tokens[tokenID];
        delete tokenHolder[tokenID];

        emit Burn(msg.sender, tokenID);
    }

    function createTokenType(uint256 tokenTypeID, address issuer, string memory metadataURI, int transferTakeRate) external {
        require(!tokenTypes[tokenTypeID], "token type already exists");
        require(transferTakeRate >= 0 && transferTakeRate <= 100, "issuer take rate must be in range [0,100]");

        Issued storage issued = issuerTokenTypes[issuer];
        issued.types.push(tokenTypeID);
        issuerTokenTypes[issuer] = Issued({
            count: issued.count + 1,
            types: issued.types
        });
        tokenTypeIssuer[tokenTypeID] = issuer;
        tokenTypeAuthorizedMinters[tokenTypeID][issuer] = true;
        tokenTypeMetadataURI[tokenTypeID] = metadataURI;
        tokenTypes[tokenTypeID] = true;
        tokenTypeMintCount[tokenTypeID] = 0;
        tokenTypeIssuerTransferTakeRate[tokenTypeID] = transferTakeRate;

        emit NewTokenType(issuer, tokenTypeID, metadataURI);
    }

    function addAuthorizedMinter(address authorizedMinter, uint256 tokenTypeID) external {
        require(tokenTypeAuthorizedMinters[tokenTypeID][msg.sender], "caller is not token type owner nor approved");

        tokenTypeAuthorizedMinters[tokenTypeID][authorizedMinter] = true;

        AuthorizedTypes storage authorized = tokenTypeAuthorized[authorizedMinter];
        authorized.types.push(tokenTypeID);
        tokenTypeAuthorized[authorizedMinter] = AuthorizedTypes({
            count: authorized.count + 1,
            types: authorized.types
        });

        emit AddAuthorizedMinter(authorizedMinter, msg.sender, tokenTypeID);
    }

    function removeAuthorizedMinter(address authorizedMinter, uint256 tokenTypeID) external {
        require(tokenTypeAuthorizedMinters[tokenTypeID][msg.sender], "caller is not token type owner nor approved");

        delete tokenTypeAuthorizedMinters[tokenTypeID][authorizedMinter];

        emit RemoveAuthorizedMinter(authorizedMinter, msg.sender, tokenTypeID);
    }

    function mintToken(address to, uint256 tokenTypeID, uint256 tokenID, string memory metadataURI) external {
        require(!tokens[tokenID], "token already exists");
        require(tokenTypes[tokenTypeID], "token type does not exist");
        require(tokenTypeAuthorizedMinters[tokenTypeID][msg.sender], "caller is not token type owner nor approved");

        Wallet storage wallet = wallets[to];
        wallet.tokens.push(tokenID);
        wallets[to] = Wallet({
            count: wallet.count + 1,
            tokens: wallet.tokens
        });
        tokenHolder[tokenID] = to;
        tokens[tokenID] = true;
        tokenMetadataURI[tokenID] = metadataURI;

        uint256 mintCount = tokenTypeMintCount[tokenTypeID] + 1;
        tokenTypeMintCount[tokenTypeID] = mintCount;

        tokenTokenType[tokenID] = tokenTypeID;

        emit Mint(to, tokenTypeID, tokenID, metadataURI, mintCount);
    }

    function transferToken(address to, uint256 tokenID) public {
        require(tokens[tokenID], "token does not exist");
        require(tokenHolder[tokenID] == msg.sender, "message sender is not token holder");

        tokenHolder[tokenID] = to;

        uint256 tokenType = tokenTokenType[tokenID];

        emit Transfer(to, tokenID, tokenType);
    }

    function escrowToken(uint256 tokenID) internal {
        require(tokens[tokenID], "token does not exist");

        address owner = tokenHolder[tokenID];

        tokenHolder[tokenID] = address(this);

        uint256 tokenType = tokenTokenType[tokenID];

        emit Transfer(owner, tokenID, tokenType);
    }
}
