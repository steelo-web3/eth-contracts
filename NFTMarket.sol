pragma solidity ^0.8.0;

import "./Nft.sol";

contract NFTMarket is Nft {

    enum AuctionStatus {
        Open,
        Closed
    }

    enum BidStatus {
        Open,
        Canceled,
        Fulfilled
    }

    enum AskStatus {
        Open,
        Canceled,
        Fulfilled
    }

    event OpenAuction(uint256 indexed tokenTypeID, uint256 indexed auctionID);
    event Ask(uint256 indexed auctionID, uint256 amount, address indexed asker, uint256 indexed tokenID, uint256 askID);
    event CancelAsk(uint256 askID, uint256 indexed auctionID, address indexed asker, uint256 indexed tokenID);
    event Bid(uint256 indexed auctionID, uint256 amount, address indexed bidder, uint256 indexed bidID);
    event CancelBid(uint256 bidID, uint256 indexed auctionID, address indexed bidder, uint256 amount);
    event CloseAuction(uint256 indexed tokenTypeID, uint256 auctionID);
    event OrderExecution(uint256 indexed auctionID, uint256 price);

    struct Market {
        uint256 auctionID;
        uint256[] bids;
        uint256[] asks;
    }

    mapping(uint256 => Market) public markets;

    function getAuctionBids(uint256 auctionID) public view returns (uint256[] memory) {
        return markets[auctionID].bids;
    }

    function getAuctionAsks(uint256 auctionID) public view returns (uint256[] memory) {
        return markets[auctionID].asks;
    }

    // auction-id -> creation-status
    mapping(uint256 => bool) public auctions;
    // auction-id -> token-type-id
    mapping(uint256 => uint256) public auctionTokenType;
    // auction-id -> auction-status
    mapping(uint256 => AuctionStatus) public auctionStatus;
    // auction-id -> price
    mapping(uint256 => uint256) public auctionPrice;
    // auction-id -> address -> auction-owner-status
    mapping(uint256 => mapping(address => bool)) public auctionAuthorized;

    struct Bidder {
        address payable bidder;
        // bid IDs
        uint256[] bids;
    }

    mapping(address => Bidder) public addressBids;

    function getAddressBids(address bidder) public view returns (uint256[] memory) {
        return addressBids[bidder].bids;
    }

    // address -> auction-id -> has-bid-status
    mapping(address => mapping(uint256 => bool)) public addressAuctionBids;
    // bid-id -> bid-exists-status
    mapping(uint256 => bool) public bids;
    // bid-id -> bid-owner-address-payable
    mapping(uint256 => address payable) public bidOwner;
    // bid-id -> bid-amount
    mapping(uint256 => uint256) public bidAmount;
    // bid-id -> auction-id
    mapping(uint256 => uint256) public bidAuction;
    // bid-id -> bid-status
    mapping(uint256 => BidStatus) public bidStatus;


    struct Asker {
        address payable asker;
        // ask IDs
        uint256[] asks;
    }

    mapping(address => Asker) public addressAsks;

    function getAddressAsks(address asker) public view returns (uint256[] memory) {
        return addressAsks[asker].asks;
    }

    // address -> auctionID -> has-ask-status
    mapping(address => mapping(uint256 => bool)) public addressAuctionAsks;
    // ask-id -> status
    mapping(uint256 => bool) public asks;
    // ask-id -> ask-owner-address-payable
    mapping(uint256 => address payable) public askOwner;
    // ask-id-> ask-amount
    mapping(uint256 => uint256) public askAmount;
    // ask-id -> auction-id
    mapping(uint256 => uint256) public askAuction;
    // ask-id -> tokenID
    mapping(uint256 => uint256) public askToken;
    // ask-id -> ask-status
    mapping(uint256 => AskStatus) public askStatus;

    // createAuction Creates an auction for tokens issued of the type @param tokenTypeID
    function createAuction(uint256 tokenTypeID, uint256 auctionID) external {
        require(!auctions[auctionID], "exisiting auction found");
        require(msg.sender == _owner, "unauthorized auction creator");

        auctions[auctionID] = true;
        auctionStatus[auctionID] = AuctionStatus.Open;
        auctionTokenType[auctionID] = tokenTypeID;

        emit OpenAuction(tokenTypeID, auctionID);
    }

    function closeAuction(uint256 auctionID) external {
        require(msg.sender == _owner, "unauthorized auction closer");
        require(auctions[auctionID], "auction not found");

        auctionStatus[auctionID] = AuctionStatus.Closed;

        Market memory market = markets[auctionID];

        uint256[] memory openBids = market.bids;
        for (uint256 i = 0; i < openBids.length; i++) {
            if (bidStatus[openBids[i]] != BidStatus.Open) {
                continue;
            }
            address payable bidder = bidOwner[openBids[i]];
            bidder.send(bidAmount[openBids[i]]);
        }

        uint256[] memory openAsks = market.asks;
        for (uint256 i = 0; i < openAsks.length; i++) {
            if (askStatus[openAsks[i]] != AskStatus.Open) {
                continue;
            }
            address asker = askOwner[openAsks[i]];
            transferToken(asker, askToken[openAsks[i]]);
        }

        emit CloseAuction(auctionTokenType[auctionID], auctionID);
    }

    function bid(uint256 bidID, uint256 auctionID, uint256 amount) public payable {
        require(msg.value == amount, "insufficient eth for bid");
        require(!bids[bidID], "bid id already exists");
        require(!addressAuctionBids[msg.sender][auctionID], "bid already exists from this address for this auction");

        Bidder storage bidder = addressBids[msg.sender];
        bidder.bids.push(bidID);
        addressBids[msg.sender] = Bidder({
            bidder : payable(msg.sender),
            bids : bidder.bids
        });

        bids[bidID] = true;
        bidOwner[bidID] = payable(msg.sender);
        bidAmount[bidID] = amount;
        addressAuctionBids[msg.sender][auctionID] = true;

        if (execute(auctionID)) {
            emit OrderExecution(auctionID, auctionPrice[auctionID]);
        }

        emit Bid(auctionID, amount, msg.sender, bidID);
    }

    function cancelBid(uint256 bidID) external {
        require(bids[bidID], "bid not found");
        require(bidOwner[bidID] == msg.sender, "message sender is not bid owner");
        require(bidStatus[bidID] == BidStatus.Open, "bid is not open");

        bidStatus[bidID] = BidStatus.Canceled;

        emit CancelBid(bidID, bidAuction[bidID], bidOwner[bidID], bidAmount[bidID]);
    }

    function ask(uint256 askID, uint256 auctionID, uint256 tokenID, uint256 amount) external {
        require(!asks[askID], "ask id already exists");
        require(!addressAuctionAsks[msg.sender][auctionID], "ask already exists from this address for this auction");
        require(tokenTokenType[tokenID] == auctionTokenType[auctionID], "token type does not match the token type for the auction");
        require(tokenHolder[tokenID] == msg.sender, "token holder is not messsage sender");

        escrowToken(tokenID);

        Asker storage asker = addressAsks[msg.sender];
        asker.asks.push(askID);
        addressAsks[msg.sender] = Asker({
            asker : payable(msg.sender),
            asks : asker.asks
        });

        asks[askID] = true;
        askOwner[askID] = payable(msg.sender);
        askAmount[askID] = amount;
        addressAuctionAsks[msg.sender][auctionID] = true;

        if (execute(auctionID)) {
            emit OrderExecution(auctionID, auctionPrice[auctionID]);
        }

        emit Ask(auctionID, amount, msg.sender, tokenID, askID);
    }

    function cancelAsk(uint256 askID) external {
        require(asks[askID], "ask not found");
        require(askOwner[askID] == msg.sender, "message sender is not ask owner");
        require(askStatus[askID] == AskStatus.Open, "ask is not open");

        askStatus[askID] = AskStatus.Canceled;

        emit CancelAsk(askID, askAuction[askID], askOwner[askID], askToken[askID]);
    }

    function execute(uint256 auctionID) internal returns (bool) {
        uint256 lowestAsk = getLowestAsk(auctionID);
        uint256 highestBid = getHighestBid(auctionID);

        if (bidAmount[highestBid] >= askAmount[lowestAsk]) {
            uint256 price = bidAmount[highestBid];

            askOwner[lowestAsk].send(price);
            transferToken(bidOwner[highestBid], askToken[lowestAsk]);

            auctionPrice[auctionID] = price;

            bidStatus[highestBid] = BidStatus.Fulfilled;
            askStatus[lowestAsk] = AskStatus.Fulfilled;
            return true;
        }

        return false;
    }

    function getLowestAsk(uint256 auctionID) public view returns (uint256) {
        uint256[] memory _asks = getAuctionAsks(auctionID);
        if (_asks.length == 0) {
            return 0;
        }
        uint256 lowestAsk = _asks[0];
        for (uint256 i = 1; i < _asks.length; i++) {
            if (askStatus[_asks[i]] != AskStatus.Open) {
                continue;
            }

            if (askAmount[_asks[i]] < askAmount[lowestAsk]) {
                lowestAsk = _asks[i];
            }
        }
        return lowestAsk;
    }

    function getHighestBid(uint256 auctionID) public view returns (uint256) {
        uint256[] memory _bids = getAuctionBids(auctionID);
        if (_bids.length == 0) {
            return 0;
        }
        uint256 highestBid = _bids[0];
        for (uint256 i = 1; i < _bids.length; i++) {
            if (bidStatus[_bids[i]] != BidStatus.Open) {
                continue;
            }

            if (bidAmount[_bids[i]] > bidAmount[highestBid]) {
                highestBid = _bids[i];
            }
        }
        return highestBid;
    }
}
