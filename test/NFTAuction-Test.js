const { expect } = require("chai");
const hardhat = require("hardhat");
const { ethers } = hardhat;
const { LazyMintLibrary, LazyBid } = require('../lib')

async function deploy() {
    const [minter, bidder1, bidder2, bidder3] = await ethers.getSigners()

    const tokenfactory = await ethers.getContractFactory("WETH")
    const tokencontract = await tokenfactory.connect(bidder1).deploy();
    await tokencontract.deployed();
    await tokencontract.mint(bidder2.address, 4);
    //console.log("WETH is delployed at :",tokencontract.address)
    const bal = await tokencontract.balanceOf(bidder2.address);
    //console.log("Balance of WETH in Bidder2's Account :",bal)

    const factory = await ethers.getContractFactory("NFTAuction")
    const contract = await factory.deploy(minter.address, 120, tokencontract.address)
    await contract.deployed();
    //console.log("NFTAuction is delployed at :",contract.address)

  // the redeemerContract is an instance of the contract that's wired up to the redeemer's signing key
    const bidderFactory1 = factory.connect(bidder1)
    const bidderContract1 = bidderFactory1.attach(contract.address)
    //console.log("Redeemer Contract is deployed at :", redeemerContract.address)

    const bidderFactory2 = factory.connect(bidder2)
    const bidderContract2 = bidderFactory2.attach(contract.address)

    const bidderFactory3 = factory.connect(bidder3)
    const bidderContract3 = bidderFactory3.attach(contract.address)

  return {
    minter,
    bidder1,
    bidder2,
    bidder3,
    contract,
    bidderContract1,
    bidderContract2,
    bidderContract3,
    tokencontract,
    tokenfactory
  }
}

describe("NFTAuction", () => {
    it("Should deploy", async function () {
      const [minter, bidder1, bidder2, bidder3] = await ethers.getSigners()
      const tokenfactory = await ethers.getContractFactory("WETH")
      const tokencontract = await tokenfactory.connect(bidder1).deploy();
      await tokencontract.deployed();
      //console.log("WETH is delployed at :",tokencontract.address)
      const bal = await tokencontract.balanceOf(bidder1.address);
      //console.log("Balance of WETH in Bidder1's Account :",bal)

      const factory = await ethers.getContractFactory("NFTAuction")
      const contract = await factory.deploy(minter.address, 120, tokencontract.address)
      await contract.deployed();
      //console.log("NFTAuction is delployed at :",contract.address)
    });

    it("Should create a signature of NFT and a bidder can bid his amount using a signature", async function(){
      const {minter, bidder1, bidder2, bidder3, contract, bidderContract1, bidderContract2, bidderContract3, tokencontract} = await deploy();

      const lazyMinter = new LazyMintLibrary({contract, signer: minter})
      const voucher = await lazyMinter.createVoucher(1, "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", 2)

      const lazyBidder = new LazyBid({contract, signer: bidder1})
      const bidvoucher = await lazyBidder.createBid(1, 3);

      await expect(bidderContract1.bid(3, voucher, bidvoucher))
          .to.emit(bidderContract1, 'HighestBidIncreased')
      
      await tokencontract.connect(bidder1).approve(contract.address, 3)
      
      await expect(bidderContract1.auctionEnd())
      .to.emit(contract, 'Transfer') // transfer from null address to minter
      .withArgs('0x0000000000000000000000000000000000000000', minter.address, voucher.tokenId)
      .and.to.emit(contract, 'Transfer') // transfer from minter to redeemer
      .withArgs(minter.address, bidder1.address, voucher.tokenId)
      .and.to.emit(bidderContract1, 'AuctionEnded');

      expect(await tokencontract.balanceOf(minter.address))
      .to.equal('3');
    });

    it("Should make the higgest bidder as the winner, transfer the NFT to his account and send the highest bid to signer", async function(){
      const {minter, bidder1, bidder2, bidder3, contract, bidderContract1, bidderContract2, bidderContract3, tokencontract} = await deploy();

      const lazyMinter = new LazyMintLibrary({contract, signer: minter})
      const voucher = await lazyMinter.createVoucher(1, "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", 2)

      const lazyBidder1 = new LazyBid({contract, signer: bidder1})
      const bidvoucher1 = await lazyBidder1.createBid(1, 3);

      await expect(bidderContract1.bid(3, voucher, bidvoucher1))
          .to.emit(bidderContract1, 'HighestBidIncreased')
      
      await tokencontract.connect(bidder1).approve(contract.address, 3)

      const lazyBidder2 = new LazyBid({contract, signer: bidder2})
      const bidvoucher2 = await lazyBidder2.createBid(1, 4);

      await expect(bidderContract2.bid(4, voucher, bidvoucher2))
          .to.emit(bidderContract2, 'HighestBidIncreased')
      
      await tokencontract.connect(bidder2).approve(contract.address, 4)
      
      await expect(bidderContract2.auctionEnd())
      .to.emit(contract, 'Transfer') // transfer from null address to minter
      .withArgs('0x0000000000000000000000000000000000000000', minter.address, voucher.tokenId)
      .and.to.emit(contract, 'Transfer') // transfer from minter to redeemer
      .withArgs(minter.address, bidder2.address, voucher.tokenId)
      .and.to.emit(bidderContract2, 'AuctionEnded');

      expect(await tokencontract.balanceOf(minter.address))
      .to.equal('4');

      expect(await contract.ownerOf(1))
      .to.equal(bidder2.address);
    });
      
});
