// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
pragma abicoder v2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

contract NFTAuction is ERC721URIStorage, EIP712, AccessControl{
    address public WETH;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string private constant SIGNING_NAME = "LazyMinting-Voucher";
    string private constant SIGNING_VERSION = "1.0";
    uint public highestBid;
    address public highestBidder;
    bool ended;
    uint public endTime;

    //mapping(address => uint256) pendingWithdrawls;

    struct NFTVoucher{
        uint256 tokenId;
        string uri;
        uint256 minPrice;
        bytes signature;
    }

    struct BidVoucher{
        uint256 tokenId;
        uint256 amount;
        bytes signature;
    }

    NFTVoucher public highestBidderVoucher;

    BidVoucher public highestBidderBidVoucher;

    event HighestBidIncreased(address Bidder, uint amount);
    event AuctionEnded(address winner, uint amount);

    error AuctionHasAlreadyEnded();
    error AuctionIsStillGoingOn();
    error BidIsNotHigher(uint highestBid);
    error AuctionEndAlreadyCalled();
    error SignatureInvalidOrBidderUnauthorized();
    error BidIsLessThanMinimumPriceOfNFT(uint minPrice);
    error BidderHasNotParticipatedInAuction(address bidder);

    constructor(address minter, uint bidTime, address _weth) ERC721("LazyMintNFT", "LMN") EIP712(SIGNING_NAME, SIGNING_VERSION){
        _setupRole(MINTER_ROLE, minter);
        endTime = block.timestamp + bidTime;
        WETH = _weth;
    }

    function bid(uint256 amount, NFTVoucher calldata voucher, BidVoucher calldata bidVoucher) public payable {
        // check the validity of the signature first and get the address of the signer
        //require(_verify(redeemer, voucher), "Verification Failed!");

        NFTVoucher memory mem_voucher = voucher;
        address signer = _verify(voucher);
        //console.log("Address of signer after verification : ", signer);

        BidVoucher memory mem_bidVoucher = bidVoucher;
        address bidSigner = _verifyBid(bidVoucher);

        // check that the signer has minter role or not
        if(hasRole(MINTER_ROLE, signer) == false){
            revert SignatureInvalidOrBidderUnauthorized();
        }

        // check that the auction time has ended or not
        if(block.timestamp > endTime){
            revert AuctionHasAlreadyEnded();
        }

        if(ended){
            revert AuctionEndAlreadyCalled();
        } 

        // check if the redeemer is paying enough to cover the buyer's cost
        if(amount < voucher.minPrice){
            revert BidIsLessThanMinimumPriceOfNFT(voucher.minPrice);
        }

        // check if the bidder is paying enough amount to take over the previous highest bidder or not
        if(amount <= highestBid){
            revert BidIsNotHigher(highestBid);
        }

        // check if no any bidder has bid till now
        if(highestBid >= voucher.minPrice && highestBid < amount){
            highestBidder = bidSigner;
            highestBid = amount;
        }

        highestBidder = bidSigner;
        highestBid = amount;
        highestBidderVoucher = mem_voucher;
        highestBidderBidVoucher = mem_bidVoucher;
        emit HighestBidIncreased(bidSigner, amount);

    }


    function _verify(NFTVoucher memory voucher) internal view returns(address){
        bytes32 digest = _hash(voucher);
        return ECDSA.recover(digest, voucher.signature);
    }

    function _hash(NFTVoucher memory voucher) internal view returns(bytes32){
        return _hashTypedDataV4(keccak256(abi.encode(
            keccak256("NFTVoucher(uint256 tokenId,string uri,uint256 minPrice)"), 
            voucher.tokenId, 
            keccak256(bytes(voucher.uri)),
            voucher.minPrice
        )));
    }

    function _verifyBid(BidVoucher memory bidVoucher) internal view returns(address){
        bytes32 digest = _hashBid(bidVoucher);
        return ECDSA.recover(digest, bidVoucher.signature);
    }

    function _hashBid(BidVoucher memory bidVoucher) internal view returns(bytes32){
        return _hashTypedDataV4(keccak256(abi.encode(
            keccak256("BidVoucher(uint256 tokenId,uint256 amount)"), 
            bidVoucher.tokenId, 
            bidVoucher.amount
        )));
    }

    function getChainId() external view returns(uint256){
        uint256 id;
        assembly{
            id := chainid()
        }
        return id;
    }

    function auctionEnd() external{
        if(block.timestamp > endTime){
            revert AuctionHasAlreadyEnded();
        }
        if(ended){
            revert AuctionEndAlreadyCalled();
        }
        ended = true;
        require(highestBid > 0, "Nobody participated in the bid but auction ended!");
        address signer = _verify(highestBidderVoucher);
        _mint(signer, highestBidderVoucher.tokenId);
        _setTokenURI(highestBidderVoucher.tokenId, highestBidderVoucher.uri);

        // now transfer it to the redeemer's account
        _transfer(signer, highestBidder, highestBidderVoucher.tokenId);

        emit AuctionEnded(highestBidder, highestBid);

        //console.log("Winner of the Auction is :", highestBidder, "with Bid amount :", highestBid);

        //console.log("Transferring highest bid amount :", highestBid, "ETH to the NFT Signer's Account : ", signer);

        IERC20(WETH).transferFrom(highestBidder,signer,highestBid);
    }

    /*function withdrawFundsAfterAuctionEnd() public{
        if(block.timestamp < endTime){
            revert AuctionIsStillGoingOn();
        }

        if(block.timestamp > endTime){
            require(msg.sender != highestBidder, "Winner cannot reclaim the bid amount!");
        }

        if(pendingWithdrawls[msg.sender] <= 0){
            revert BidderHasNotParticipatedInAuction(msg.sender);
        }
        address payable receiver = payable(msg.sender);
        uint amount = pendingWithdrawls[receiver];
        //console.log("Transferring amount :", pendingWithdrawls[receiver], "ETH to Account : ", receiver);
        pendingWithdrawls[receiver] = 0;
        receiver.transfer(amount);
    }*/

    function supportsInterface(bytes4 interfaceId) public view virtual override (AccessControl, ERC721) returns (bool) {
    return ERC721.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
  }
}
