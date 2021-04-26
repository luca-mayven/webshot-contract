
import NonFungibleToken from "./NonFungibleToken.cdc"
import FungibleToken from "./FungibleToken.cdc"
import FlowToken from "./FlowToken.cdc"
//import FungibleToken from 0x9a0766d93b6608b7
//import FUSD from 0xe223d8a629e49c68
import Webshot from "./Webshot.cdc"

/*

 The main contract in the Webshot marketplace system.

 This contract is a mix of 2 other contracts:

 - The Versus Auction contract created by Bjartek and Alchemist
 https://github.com/versus-flow/auction-flow-contract

 - The Kitty items demo from the Flow team
 https://github.com/onflow/kitty-items


 Webshot NFT are minted only by the contract admins and placed on an Auction using the website owner address.

 Users can place bids on auctions or directly buy and sell Webshot that have been purchased from an auction.


 The contract applies a cut to Auction sales for the marketplace (% set as property on the NFT when it is minted)

 The contract applies a cut to direct sales for both the marketplace and the website owner (also set as property on the NFT)

 */


pub contract Auction {

    //A set of capability and storage paths used in this contract
    pub let WebshotAdminPrivatePath: PrivatePath
    pub let WebshotAdminStoragePath: StoragePath
    pub let WebshotAdminClientPublicPath: PublicPath
    pub let WebshotAdminClientStoragePath: StoragePath
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let CollectionPrivatePath: PrivatePath


    //counter for drops that is incremented every time there is a new auction
    pub var totalAuctions: UInt64



    //emitted when a drop is extended
    pub event AuctionExtended(auctionId: UInt64, name: String, owner: String, extendWith: Fix64, extendTo: Fix64)

    //emitted when a bid is made
    pub event Bid(auctionId: UInt64, name: String, owner: String, bidder: Address, price: UFix64)

    //emitted when an Auction is created
    pub event AuctionCreated(auctionId: UInt64, name: String, owner: String, ownerAddress: Address)

    //emitted when an Auction is settled
    pub event Settled(auctionId: UInt64, name: String, owner: String, price:UFix64)

    //emitted when an Auction is destroyed
    pub event AuctionDestroyed(auctionId:UInt64)




    // SaleOfferPublicView
    // An interface providing a read-only view of a SaleOffer
    //
    pub resource interface SaleOfferPublicView {
        pub let webshotId: UInt64
        pub let price: UFix64

        pub fun getMetadata(): Webshot.Metadata
        pub fun getRoyalty(): {String: Webshot.Royalty}
    }




    // SaleOffer
    // A Webshot NFT being offered to sale for a price.
    //
    pub resource SaleOffer: SaleOfferPublicView {
        // Whether the sale has completed with someone purchasing the item.
        pub var saleCompleted: Bool

        // The Webshot NFT ID for sale.
        pub let webshotId: UInt64

        // The sale payment price.
        pub let price: UFix64

        //The Item that is sold at this auction
        access(contract) var NFT: @Webshot.NFT?

        //the capability for the owner of the NFT to return the item to if the saleoffer is cancelled
        access(contract) let ownerCollectionCap: Capability<&{Webshot.CollectionPublic}>

        //the capability to pay the owner of the item when the sale offer has been accepted
        access(contract) let ownerVaultCap: Capability<&{FungibleToken.Receiver}>



        pub fun getMetadata(): Webshot.Metadata {
            return self.NFT?.metadata!
        }
        pub fun getRoyalty(): {String: Webshot.Royalty} {
            return self.NFT?.royalty!
        }

        // Called by a purchaser to accept the sale offer.
        //
        pub fun accept(
            buyerCollectionCap: Capability<&{Webshot.CollectionPublic}>,
            buyerPayment: @FungibleToken.Vault
        ) {
            pre {
                buyerPayment.balance == self.price: "Payment does not equal offer price"
                self.saleCompleted == false: "The sale offer has already been accepted"
                self.NFT != nil: "Webshot not present in the sale offer"
                self.NFT?.royalty != nil: "Royalty not present in the Webshot"
            }


            self.saleCompleted = true


            let royalty: {String: Webshot.Royalty} = self.NFT?.royalty!

            if let royaltyMarket: Webshot.Royalty = royalty["market"] {
                //Withdraw cutPercentage to market and put it in their vault
                let amountMarketCut = self.price * royaltyMarket.cut

                if let marketVaultRef = royaltyMarket.wallet.borrow() {
                    let beneficiaryMarketCut <- buyerPayment.withdraw(amount: amountMarketCut)
                    marketVaultRef.deposit(from: <- beneficiaryMarketCut)

                    emit MarketplaceEarned(amount: amountMarketCut) //, owner: royaltyMarket.wallet)
                } else {
                    panic("Could not send tokens to non existant market receiver")
                }
            }

            if let royaltyOwner: Webshot.Royalty = royalty["owner"] {
                //Withdraw cutPercentage to owner and put it in their vault
                let amountOwnerCut = self.price * royaltyOwner.cut

                if let ownerVaultRef = royaltyOwner.wallet.borrow() {
                    let beneficiaryOwnerCut <- buyerPayment.withdraw(amount: amountOwnerCut)
                    ownerVaultRef.deposit(from: <- beneficiaryOwnerCut)

                    emit OwnerEarned(amount: amountOwnerCut) //, owner: royaltyOwner.wallet)
                } else {
                    panic("Could not send tokens to non existant market receiver")
                }
            }


            self.ownerVaultCap.borrow()!.deposit(from: <- buyerPayment)
            self.sendNFT(buyerCollectionCap)
            //let NFT <- self.NFT <- nil
            //buyerCollection.deposit(token: <- NFT!)

            emit SaleOfferAccepted(webshotId: self.NFT?.id!, metadata: self.NFT?.metadata!, price: self.price)
        }



        // sendNFT sends the NFT to the Collection belonging to the provided Capability
        access(contract) fun sendNFT(_ capability: Capability<&{Webshot.CollectionPublic}>) {
            if let collectionRef = capability.borrow() {
                let NFT <- self.NFT <- nil
                collectionRef.deposit(token: <- NFT!)
                return
            }
            panic("Could not send NFT to non existing capability")
        }

        // destructor
        //
        destroy() {
            if self.NFT != nil {
                self.sendNFT(self.ownerCollectionCap)
            }
            // Whether the sale completed or not, publicize that it is being withdrawn.
            emit SaleOfferFinished(webshotId: self.NFT?.id!, metadata: self.NFT?.metadata!, price: self.price)

            destroy self.NFT
        }

        // initializer
        // Take the information required to create a sale offer, notably the capability
        // to transfer the KittyItems NFT and the capability to receive Kibble in payment.
        //
        init(
            NFT: @Webshot.NFT,
            price: UFix64,
            ownerCollectionCap: Capability<&{Webshot.CollectionPublic}>,
            ownerVaultCap: Capability<&{FungibleToken.Receiver}>
        ) {
            pre {
                ownerVaultCap.borrow() != nil: "Cannot borrow ownerVaultCap"
            }

            self.saleCompleted = false
            self.webshotId = NFT.id
            self.NFT <- NFT
            self.price = price
            self.ownerCollectionCap = ownerCollectionCap
            self.ownerVaultCap = ownerVaultCap

            emit SaleOfferCreated(webshotId: self.NFT?.id!, metadata: self.NFT?.metadata!, price: self.price)
        }
    }


    // createSaleOffer
    // Make creating a SaleOffer publicly accessible.
    //
    pub fun createSaleOffer (
            NFT: @Webshot.NFT,
            price: UFix64,
            ownerCollectionCap: Capability<&{Webshot.CollectionPublic}>,
            ownerVaultCap: Capability<&{FungibleToken.Receiver}>): @SaleOffer {
        return <-create SaleOffer(
            NFT: <-NFT,
            price: price,
            ownerCollectionCap: ownerCollectionCap,
            ownerVaultCap: ownerVaultCap
        )
    }






    pub resource interface AuctionPublicView {
        pub let id: UInt64
        pub let auctionStatus : AuctionStatus
    }


    // This struct aggreates status for the auction and is exposed in order to create websites using auction information
    pub struct AuctionStatus{
        pub let id: UInt64
        pub let webshotId: UInt64
        pub let price : UFix64
        pub let bidIncrement : UFix64
        pub let bids : UInt64
        pub let timeRemaining : Fix64
        pub let endTime : Fix64
        pub let startTime : Fix64
        pub let metadata: Webshot.Metadata?
        pub let owner: Address
        pub let leader: Address?
        pub let minNextBid: UFix64
        pub let completed: Bool
        pub let expired: Bool
        pub let active: Bool
        pub let firstBidBlock: UInt64?
        pub let settledAt: UInt64?

        init(id:UInt64,
            webshotId:UInt64,
            price: UFix64,
            bids:UInt64,
            timeRemaining:Fix64,
            metadata: Webshot.Metadata?,
            leader:Address?,
            bidIncrement: UFix64,
            owner: Address,
            startTime: Fix64,
            endTime: Fix64,
            minNextBid:UFix64,
            completed: Bool,
            expired:Bool,
            firstBidBlock: UInt64?,
            settledAt: UInt64?
        ) {
            self.id = id
            self.webshotId = webshotId
            self.price = price
            self.bids = bids
            self.timeRemaining = timeRemaining
            self.metadata = metadata
            self.leader = leader
            self.bidIncrement = bidIncrement
            self.owner = owner
            self.startTime = startTime
            self.endTime = endTime
            self.minNextBid = minNextBid
            self.completed = completed
            self.expired = expired
            self.firstBidBlock = firstBidBlock
            self.settledAt = settledAt
            self.active = !(expired || completed)
        }

    }


   //A Drop in versus represents a single auction vs an editioned auction
    pub resource Auction {


        //this is used to be able to query events for a drop from a given start point
        access(contract) var firstBidBlock: UInt64?
        access(contract) var settledAt: UInt64?


        //Number of bids made, that is aggregated to the status struct
        access(contract) var numberOfBids: UInt64

        //The Item that is sold at this auction
        access(contract) var NFT: @Webshot.NFT?

        //This is the escrow vault that holds the tokens for the current largest bid
        access(contract) let bidVault: @FungibleToken.Vault

        //The id of this individual auction
        pub let auctionId: UInt64

        //The minimum increment for a bid. This is an english auction style system where bids increase
        access(contract) let minimumBidIncrement: UFix64

        //the time the acution should start at
        access(contract) var auctionStartTime: UFix64

        //The length in seconds for this auction
        access(contract) var auctionLength: UFix64

        //Right now the dropitem is not moved from the collection when it ends, it is just marked here that it has ended
        access(contract) var auctionSettled: Bool

        // Auction State
        access(contract) var startPrice: UFix64
        access(contract) var currentPrice: UFix64

        //the capability that points to the resource where you want the NFT transfered to if you win this bid.
        access(contract) var recipientCollectionCap: Capability<&{Webshot.CollectionPublic}>?

        //the capablity to send the escrow bidVault to if you are outbid
        access(contract) var recipientVaultCap: Capability<&{FungibleToken.Receiver}>?

        //the capability for the owner of the NFT to return the item to if the auction is cancelled
        access(contract) let ownerCollectionCap: Capability<&{Webshot.CollectionPublic}>

        //the capability to pay the owner of the item when the auction is done
        access(contract) let ownerVaultCap: Capability<&{FungibleToken.Receiver}>

        access(contract) var extentionOnLateBid: UFix64

        init(
            NFT: @Webshot.NFT,
            minimumBidIncrement: UFix64,
            auctionStartTime: UFix64,
            startPrice: UFix64,
            auctionLength: UFix64,
            extentionOnLateBid: UFix64,
            ownerCollectionCap: Capability<&{Webshot.CollectionPublic}>,
            ownerVaultCap: Capability<&{FungibleToken.Receiver}>) {

            WebshotMarket.totalAuctions = WebshotMarket.totalAuctions + (1 as UInt64)
            self.auctionId = WebshotMarket.totalAuctions
            self.firstBidBlock = nil
            self.settledAt = nil
            self.NFT <- NFT
            self.bidVault <- FlowToken.createEmptyVault()
            self.minimumBidIncrement = minimumBidIncrement
            self.auctionLength = auctionLength
            self.startPrice = startPrice
            self.currentPrice = 0.0
            self.auctionStartTime = auctionStartTime
            self.auctionSettled = false
            self.recipientCollectionCap = nil
            self.recipientVaultCap = nil
            self.ownerCollectionCap = ownerCollectionCap
            self.ownerVaultCap = ownerVaultCap
            self.numberOfBids = 0
            self.extentionOnLateBid = extentionOnLateBid
        }


        pub fun metadata() : Webshot.Metadata? {
            return self.NFT?.getMetadata()
        }

        // sendNFT sends the NFT to the Collection belonging to the provided Capability
        access(contract) fun sendNFT(_ capability: Capability<&{Webshot.CollectionPublic}>) {
            if let collectionRef = capability.borrow() {
                let NFT <- self.NFT <- nil
                collectionRef.deposit(token: <-NFT!)
                return
            }
            panic("Could not send NFT to non existing capability")
        }

        // sendBidTokens sends the bid tokens to the Vault Receiver belonging to the provided Capability
        access(contract) fun sendBidTokens(_ capability: Capability<&{FungibleToken.Receiver}>) {
            // borrow a reference to the owner's NFT receiver
            if let vaultRef = capability.borrow() {
                let bidVaultRef = &self.bidVault as &FungibleToken.Vault
                vaultRef.deposit(from: <-bidVaultRef.withdraw(amount: bidVaultRef.balance))
                return
            }
            panic("Could not send tokens to non existant receiver")
        }

        pub fun releasePreviousBid() {
            if let vaultCap = self.recipientVaultCap {
                self.sendBidTokens(self.recipientVaultCap!)
                return
            }
        }

        //This method should probably use preconditions more
        pub fun settle(cutPercentage: UFix64, cutVault:Capability<&{FungibleToken.Receiver}> )  {
            pre {
                !self.auctionSettled : "The auction is already settled"
                self.NFT != nil: "NFT in auction does not exist"
                self.isAuctionExpired() : "Auction has not completed yet"
            }

            // return if there are no bids to settle
            if self.currentPrice == 0.0{
                self.returnAuctionItemToOwner()
                return
            }

            //Withdraw cutPercentage to marketplace and put it in their vault
            let amountMarketplaceCut = self.currentPrice*cutPercentage
            let beneficiaryCut <- self.bidVault.withdraw(amount: amountMarketplaceCut)

            let cutVault=cutVault.borrow()!
            emit MarketplaceEarned(amount: amountMarketplaceCut) //, owner: cutVault.owner!.address)
            cutVault.deposit(from: <- beneficiaryCut)

            self.sendNFT(self.recipientCollectionCap!)
            self.sendBidTokens(self.ownerVaultCap)

            self.auctionSettled = true

            self.settledAt=getCurrentBlock().height
            let auctionStatus = self.getAuctionStatus()

            emit TSettled(id: self.auctionId, price: self.currentPrice)
            emit Settled(name: auctionStatus.metadata!.name, owner: auctionStatus.metadata!.owner, price: self.currentPrice)
        }

        pub fun returnAuctionItemToOwner() {

            // release the bidder's tokens
            self.releasePreviousBid()

            // deposit the NFT into the owner's collection
            self.sendNFT(self.ownerCollectionCap)
         }

         pub fun cancelAuction() {
            self.returnAuctionItemToOwner()
            emit Canceled(id: self.auctionId)
        }

        //this can be negative if is expired
        pub fun timeRemaining() : Fix64 {
            let auctionLength = self.auctionLength

            let startTime = self.auctionStartTime
            let currentTime = getCurrentBlock().timestamp

            let remaining= Fix64(startTime+auctionLength) - Fix64(currentTime)
            return remaining
        }


        pub fun isAuctionExpired(): Bool {
            let timeRemaining= self.timeRemaining()
            return timeRemaining < Fix64(0.0)
        }

        pub fun minNextBid() :UFix64{
            //If there are bids then the next min bid is the current price plus the increment
            if self.currentPrice != 0.0 {
                return self.currentPrice+self.minimumBidIncrement
            }
            //else start price
            return self.startPrice
        }

        //Extend an auction with a given set of blocks
        pub fun extendWith(_ amount: UFix64) {
            self.auctionLength= self.auctionLength + amount
        }

        // This method should probably use preconditions more
        pub fun placeBid(
            bidTokens: @FungibleToken.Vault,
            vaultCap: Capability<&{FungibleToken.Receiver}>,
            collectionCap: Capability<&{Webshot.CollectionPublic}>) {

            pre {
                collectionCap.check() == true : "Collection capability must be linked"
                vaultCap.check() == true : "Vault capability must be linked"
                !self.isAuctionExpired() : "The auction is already expired"
                !self.auctionSettled : "The auction is already settled"
                self.NFT != nil: "NFT in auction does not exist"
                bidTokens.balance >= self.minNextBid() : "bid amount must be larger or equal to the current price + minimum bid increment"
            }

            if self.bidVault.balance != 0.0 {
                if let vaultCap = self.recipientVaultCap {
                    self.sendBidTokens(self.recipientVaultCap!)
                } else {
                    panic("unable to get recipient Vault capability")
                }
            }


            let auctionStatus = self.getAuctionStatus()

            let block=getCurrentBlock()
            let time=Fix64(block.timestamp)

            if auctionStatus.startTime > time {
                panic("The drop has not started")
            }

            if auctionStatus.endTime < time  {
                panic("This drop has ended")
            }

            //we save the time of the first bid so that it can be used to fetch events from that given block
            if self.firstBidBlock == nil {
                self.firstBidBlock=block.height
            }

            let bidEndTime = time + Fix64(self.extentionOnLateBid)

            //We need to extend the auction since there is too little time left. If we did not do this a late user could potentially win with a cheecky bid
            if auctionStatus.endTime < bidEndTime {
                let extendWith=bidEndTime - auctionStatus.endTime
                emit TAuctionExtended(id: self.auctionId, extendWith: extendWith, extendTo: bidEndTime)
                emit AuctionExtended(name: auctionStatus.metadata!.name, owner: auctionStatus.metadata!.owner)
                self.extendWith(UFix64(extendWith))
            }


            // Update the auction item
            self.bidVault.deposit(from: <-bidTokens)

            //update the capability of the wallet for the address with the current highest bid
            self.recipientVaultCap = vaultCap

            // Update the current price of the token
            self.currentPrice = self.bidVault.balance

            // Add the bidder's Vault and NFT receiver references
            self.recipientCollectionCap = collectionCap
            self.numberOfBids = self.numberOfBids+(1 as UInt64)


            let bidderAddress = vaultCap.borrow()!.owner!.address
            emit TBid(auctionId: self.auctionId, bidderAddress: bidderAddress , bidPrice: self.currentPrice, time: time, blockHeight: block.height)
            emit Bid(name: auctionStatus.metadata!.name, owner: auctionStatus.metadata!.owner, bidder: bidderAddress, price: self.currentPrice)
        }

        pub fun getAuctionStatus() :AuctionStatus {

            var leader:Address?= nil
            if let recipient = self.recipientVaultCap {
                leader=recipient.borrow()!.owner!.address
            }

            return AuctionStatus(
                id: self.auctionId,
                webshotId: self.NFT?.id!,
                price: self.currentPrice,
                bids: self.numberOfBids,
                timeRemaining: self.timeRemaining(),
                metadata: self.NFT?.metadata,
                leader: leader,
                bidIncrement: self.minimumBidIncrement,
                owner: self.ownerVaultCap.borrow()!.owner!.address,
                startTime: Fix64(self.auctionStartTime),
                endTime: Fix64(self.auctionStartTime+self.auctionLength),
                minNextBid: self.minNextBid(),
                completed: self.auctionSettled,
                expired: self.isAuctionExpired(),
                firstBidBlock: self.firstBidBlock,
                settledAt: self.settledAt
            )
        }

        destroy() {
            log("destroy auction")
            // send the NFT back to auction owner
            if self.NFT != nil {
                self.sendNFT(self.ownerCollectionCap)
            }

            // if there's a bidder...
            if let vaultCap = self.recipientVaultCap {
                // ...send the bid tokens back to the bidder
                self.sendBidTokens(vaultCap)
            }

            destroy self.NFT
            destroy self.bidVault
        }

    }





    // An interface to allow listing and borrowing SaleOffers, and purchasing items via SaleOffers in a collection.
    pub resource interface SaleOfferPublic {
        pub fun getSaleOfferIDs(): [UInt64]
        pub fun borrowSaleItem(webshotId: UInt64): &SaleOffer{SaleOfferPublicView}?
        pub fun purchase(
            webshotId: UInt64,
            buyerCollectionCap: Capability<&{Webshot.CollectionPublic}>,
            buyerPayment: @FungibleToken.Vault
        )
   }

    // An interface for adding and removing SaleOffers to a collection, intended for
    // use by the collection's owner.
    pub resource interface SaleOfferAdmin {
        pub fun insert(offer: @WebshotMarket.SaleOffer)
        pub fun remove(webshotId: UInt64): @SaleOffer
    }

    // A resource that allows its owner to manage a list of SaleOffers, and purchasers to interact with them.
    //
    pub resource SaleOfferCollection : SaleOfferAdmin, SaleOfferPublic {
        pub var saleOffers: @{UInt64: SaleOffer}

        // insert
        // Insert a SaleOffer into the collection, replacing one with the same webshotId if present.
        //
         pub fun insert(offer: @WebshotMarket.SaleOffer) {
            let webshotId: UInt64 = offer.NFT?.id!
            let metadata: Webshot.Metadata = offer.NFT?.metadata!
            let price: UFix64 = offer.price

            // add the new offer to the dictionary which removes the old one
            let oldOffer <- self.saleOffers[webshotId] <- offer
            destroy oldOffer

            emit CollectionInsertedSaleOffer(
              webshotId: webshotId,
              metadata: metadata,
              owner: self.owner?.address!,
              price: price
            )
        }

        // remove
        // Remove and return a SaleOffer from the collection.
        pub fun remove(webshotId: UInt64): @SaleOffer {
            emit CollectionRemovedSaleOffer(webshotId: webshotId, owner: self.owner?.address!)
            return <-(self.saleOffers.remove(key: webshotId) ?? panic("missing SaleOffer"))
        }

        // purchase
        // If the caller passes a valid webshotId and the item is still for sale, and passes a FungibleToken vault
        // typed as a FungibleToken.Vault containing the correct payment amount, this will transfer the Webshot to the caller's
        // Webshot collection.
        // It will then remove and destroy the offer.
        // Note that is means that events will be emitted in this order:
        //   1. Collection.CollectionRemovedSaleOffer
        //   2. KittyItems.Withdraw
        //   3. KittyItems.Deposit
        //   4. SaleOffer.SaleOfferFinished
        //
        pub fun purchase(
            webshotId: UInt64,
            buyerCollectionCap: Capability<&{Webshot.CollectionPublic}>,
            buyerPayment: @FungibleToken.Vault
        ) {
            pre {
                self.saleOffers[webshotId] != nil: "SaleOffer does not exist in the collection!"
            }
            let offer <- self.remove(webshotId: webshotId)
            offer.accept(buyerCollectionCap: buyerCollectionCap, buyerPayment: <- buyerPayment)
            //FIXME: Is this correct? Or should we return it to the caller to dispose of?
            destroy offer
        }

        // getSaleOfferIDs
        // Returns an array of the IDs that are in the collection
        //
        pub fun getSaleOfferIDs(): [UInt64] {
            return self.saleOffers.keys
        }

        // borrowSaleItem
        // Returns an Optional read-only view of the SaleItem for the given itemID if it is contained by this collection.
        // The optional will be nil if the provided itemID is not present in the collection.
        //
        pub fun borrowSaleItem(webshotId: UInt64): &SaleOffer{SaleOfferPublicView}? {
            if self.saleOffers[webshotId] == nil {
                return nil
            } else {
                return &self.saleOffers[webshotId] as &SaleOffer{SaleOfferPublicView}
            }
        }

        // destructor
        //
        destroy () {
            destroy self.saleOffers
        }

        // constructor
        //
        init () {
            self.saleOffers <- {}
        }
    }

    // createEmptyCollection
    // Make creating a Collection publicly accessible.
    //
    pub fun createEmptyCollection(): @SaleOfferCollection {
        return <-create SaleOfferCollection()
    }






    //An resource interface that everybody can access through a public capability.
    pub resource interface AuctionPublic {

        pub fun getAllStatuses(): {UInt64: AuctionStatus}
        pub fun getStatus(auctionId: UInt64): AuctionStatus

        pub fun getWebshot(auctionId: UInt64): Webshot.Metadata

        pub fun placeBid(
            auctionId:UInt64,
            bidTokens: @FungibleToken.Vault,
            vaultCap: Capability<&{FungibleToken.Receiver}>,
            collectionCap: Capability<&{Webshot.CollectionPublic}>
        )


    }

    pub resource interface AuctionAdmin {

        pub fun createAuction(
             nft: @NonFungibleToken.NFT,
             minimumBidIncrement: UFix64,
             startTime: UFix64,
             startPrice: UFix64,
             vaultCap: Capability<&{FungibleToken.Receiver}>,
             webshotAdmin: &Webshot.Administrator,
             auctionLength: UFix64,
             extentionOnLateBid:UFix64)

        pub fun settle(_ auctionId: UInt64)
    }


    pub resource AuctionCollection: AuctionPublic, AuctionAdmin {

        pub var auctions: @{UInt64: Auction}

        //it is possible to adjust the cutPercentage if you own a Webshot.AuctionCollection
        pub(set) var cutPercentage:UFix64

        pub let marketplaceVault: Capability<&{FungibleToken.Receiver}>

        //NFTs that are not sold are put here when a bid is settled.
        pub let marketplaceNFTUnsold: Capability<&{Webshot.CollectionPublic}>


        init(
            marketplaceVault: Capability<&{FungibleToken.Receiver}>,
            marketplaceNFTUnsold: Capability<&{Webshot.CollectionPublic}>,
            cutPercentage: UFix64,
        ) {
            self.marketplaceNFTUnsold=marketplaceNFTUnsold
            self.cutPercentage = cutPercentage
            self.marketplaceVault = marketplaceVault
            self.auctions <- {}
        }



        pub fun createAuction(
             nft: @NonFungibleToken.NFT,
             minimumBidIncrement: UFix64,
             startTime: UFix64,
             startPrice: UFix64,
             vaultCap: Capability<&{FungibleToken.Receiver}>,
             webshotAdmin: &Webshot.Administrator,
             auctionLength: UFix64,
             extentionOnLateBid:UFix64) {

            pre {
                vaultCap.check() == true : "Vault capability should exist"
            }

            let webshot <- nft as! @Webshot.NFT
            let metadata = webshot.metadata


            let auction <- create Auction(
                NFT: <- webshot,
                minimumBidIncrement: minimumBidIncrement,
                auctionStartTime: startTime,
                startPrice: startPrice,
                auctionLength: auctionLength,
                extentionOnLateBid: extentionOnLateBid,
                ownerCollectionCap: self.marketplaceNFTUnsold,
                ownerVaultCap: vaultCap
            )

            emit TAuctionCreated(id: auction.auctionId, owner: vaultCap.borrow()!.owner!.address)
            emit AuctionCreated(name: metadata.name, owner: metadata.owner)

            let oldAuction <- self.auctions[auction.auctionId] <- auction
            destroy oldAuction
        }



        //Get all the auction statuses
        pub fun getAllStatuses(): {UInt64: AuctionStatus} {
            var AuctionStatus: {UInt64: AuctionStatus }= {}
            for id in self.auctions.keys {
                let itemRef = &self.auctions[id] as? &Auction
                AuctionStatus[id] = itemRef.getAuctionStatus()
            }
            return AuctionStatus

        }

        access(contract) fun getAuction(_ auctionId: UInt64) : &Auction {
            pre {
                self.auctions[auctionId] != nil:
                    "auction doesn't exist"
            }
            return &self.auctions[auctionId] as &Auction
        }

        pub fun getStatus(auctionId:UInt64): AuctionStatus {
            return self.getAuction(auctionId).getAuctionStatus()
        }

        //get the webshot for this auction
        pub fun getWebshot(auctionId: UInt64) : Webshot.Metadata {
            let auction= self.getAuction(auctionId)
            return auction.metadata()!
        }

        //settle an auction
        pub fun settle(_ auctionId: UInt64) {
            self.getAuction(auctionId).settle(cutPercentage: self.cutPercentage, cutVault: self.marketplaceVault)
       }

        //place a bid, will just delegate to the method in the drop collection
        pub fun placeBid(
            auctionId:UInt64,
            bidTokens: @FungibleToken.Vault,
            vaultCap: Capability<&{FungibleToken.Receiver}>,
            collectionCap: Capability<&{Webshot.CollectionPublic}>
        ) {
            self.getAuction(auctionId).placeBid(
                bidTokens: <- bidTokens,
                vaultCap: vaultCap,
                collectionCap:collectionCap
            )
        }

        destroy() {
            destroy self.auctions
        }
    }





    //An Administrator resource that is stored as a private capability. That capability will be given to another account using a capability receiver
    pub resource Administrator {
        pub fun createAuctionCollection(
            marketplaceVault: Capability<&{FungibleToken.Receiver}>,
            marketplaceNFTUnsold: Capability<&{Webshot.CollectionPublic}>,
            cutPercentage: UFix64): @AuctionCollection {
            let collection <- create AuctionCollection(
                marketplaceVault: marketplaceVault,
                marketplaceNFTUnsold: marketplaceNFTUnsold,
                cutPercentage: cutPercentage
            )
            return <- collection
        }
    }


    //The interface used to add a Administrator capability to a client
    pub resource interface WebshotMarketAdminClient {
        pub fun addCapability(_ cap: Capability<&Administrator>)
    }

    //The versus admin resource that a client will create and store, then link up a public VersusAdminClient
    pub resource WebshotMarketAdmin: WebshotMarketAdminClient {

        access(self) var server: Capability<&Administrator>?

        init() {
            self.server = nil
        }

         pub fun addCapability(_ cap: Capability<&Administrator>) {
            pre {
                cap.check() : "Invalid server capablity"
                self.server == nil : "Server already set"
            }
            self.server = cap
        }

        //make it possible to create a auction marketplace. Will just delegate to the administrator
        pub fun createAuctionMarketplace(
            marketplaceVault: Capability<&{FungibleToken.Receiver}>,
            marketplaceNFTUnsold: Capability<&{Webshot.CollectionPublic}>,
            cutPercentage: UFix64) :@AuctionCollection {

            pre {
                self.server != nil:
                    "Cannot create versus marketplace if server is not set"
            }
            return <- self.server!.borrow()!.createAuctionCollection(
                marketplaceVault: marketplaceVault,
                marketplaceNFTUnsold: marketplaceNFTUnsold,
                cutPercentage: cutPercentage
            )
        }
    }

    //make it possible for a user that wants to be a versus admin to create the client
    pub fun createAdminClient(): @WebshotMarketAdmin {
        return <- create WebshotMarketAdmin()
    }



    //initialize all the paths and create and link up the admin proxy
    init() {
        self.totalAuctions = (0 as UInt64)

        //TODO: REMOVE SUFFIX BEFORE RELEASE
        self.CollectionPublicPath= /public/WebshotMarketCollection001
        self.CollectionStoragePath= /storage/WebshotMarketCollection001
        self.SaleOfferCollectionPublicPath= /public/WebshotSaleOfferCollection001
        self.SaleOfferCollectionStoragePath= /storage/WebshotSaleOfferCollection001
        self.WebshotMarketAdminClientPublicPath= /public/WebshotMarketAdminClient001
        self.WebshotMarketAdminClientStoragePath=/storage/WebshotMarketAdminClient001
        self.WebshotMarketAdministratorStoragePath=/storage/WebshotMarketAdmin001
        self.WebshotMarketAdministratorPrivatePath=/private/WebshotMarketAdmin001

        self.account.save(<- create Administrator(), to: self.WebshotMarketAdministratorStoragePath)
        self.account.link<&Administrator>(self.WebshotMarketAdministratorPrivatePath, target: self.WebshotMarketAdministratorStoragePath)
    }

}
