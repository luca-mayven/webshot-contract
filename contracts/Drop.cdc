
import NonFungibleToken from "./NonFungibleToken.cdc"
import FungibleToken from "./FungibleToken.cdc"
import FlowToken from "./FlowToken.cdc"
//import FungibleToken from 0x9a0766d93b6608b7
//import FUSD from 0xe223d8a629e49c68
import Webshot from "./Webshot.cdc"
import Website from "./Website.cdc"

/*

 The main contract in the Webshot marketplace system.

 This contract based on the following git repo

 - The Versus Auction contract created by Bjartek and Alchemist
 https://github.com/versus-flow/auction-flow-contract

 Webshot NFT are minted only by the contract admins and placed on an Auction using the website owner address.

 Users can place bids on auctions or directly buy and sell Webshot that have been purchased from an auction.

 The contract applies a cut to Auction sales for the marketplace (% set as property on the NFT when it is minted)

 The contract applies a cut to direct sales for both the marketplace and the website owner (also set as property on the NFT)

 */

pub contract Drop {

    //A set of capability and storage paths used in this contract
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let CollectionPrivatePath: PrivatePath
    pub let WebshotAdminPublicPath: PublicPath
    pub let WebshotAdminStoragePath: StoragePath

    //counter for drops that is incremented every time there is a new auction
    pub var totalAuctions: UInt64

    //emitted when a drop is extended
    pub event AuctionExtended(auctionId: UInt64, name: String, owner: String, extendWith: Fix64, extendTo: Fix64)

    //emitted when a bid is made
    pub event AuctionBid(auctionId: UInt64, name: String, owner: String, bidder: Address, price: UFix64)

    //emitted when an Auction is created
    pub event AuctionCreated(auctionId: UInt64, name: String, owner: String, ownerAddress: Address)

    //emitted when an Auction is settled
    pub event AuctionSettled(auctionId: UInt64, price: UFix64)

    //emitted when an Auction is destroyed
    pub event AuctionCancelled(auctionId: UInt64)

    //emitted when an Auction is destroyed
    pub event AuctionDestroyed(auctionId: UInt64)

    // This struct aggregates status for the auction and is exposed in order to create websites using auction information
    pub struct AuctionStatus{
        pub let id: UInt64
        pub let webshotId: UInt64
        pub let startPrice : UFix64
        pub let currentPrice : UFix64
        pub let bidIncrement : UFix64
        pub let bids : UInt64
        pub let timeRemaining : Fix64
        pub let endTime : Fix64
        pub let startTime : Fix64
        pub let metadata: Webshot.Metadata
        pub let owner: Address
        pub let leader: Address?
        pub let minNextBid: UFix64
        pub let completed: Bool
        pub let expired: Bool
        pub let active: Bool
        pub let firstBidBlock: UInt64?
        pub let settledAt: UFix64?

        init(id: UInt64,
            webshotId: UInt64,
            startPrice: UFix64,
            currentPrice: UFix64,
            bids: UInt64,
            timeRemaining: Fix64,
            metadata: Webshot.Metadata,
            leader: Address?,
            bidIncrement: UFix64,
            owner: Address,
            startTime: Fix64,
            endTime: Fix64,
            minNextBid: UFix64,
            completed: Bool,
            expired: Bool,
            firstBidBlock: UInt64?,
            settledAt: UFix64?
        ) {
            self.id = id
            self.webshotId = webshotId
            self.startPrice = startPrice
            self.currentPrice = currentPrice
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
            self.active = !(expired || completed || startTime < getCurrentBlock().timestamp)
        }

    }

   //The Auction resource that manages all the bids done on a freshly minted Webshot
    pub resource Auction {

        //this is used to be able to query events for a drop from a given start point
        access(contract) var firstBidBlock: UInt64?
        access(contract) var settledAt: UFix64?

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

        //the time the auction should start at
        access(contract) var auctionStartTime: UFix64

        //The length in seconds for this auction
        access(contract) var duration: UFix64

        //Right now the webshot is not moved from the collection when it ends, it is just marked here that it has ended
        access(contract) var auctionSettled: Bool

        // Auction State
        access(contract) var startPrice: UFix64
        access(contract) var currentPrice: UFix64

        //the capability that points to the resource where you want the NFT transferred to if you win this bid.
        access(contract) var recipientCollectionCap: Capability<&{Webshot.CollectionPublic}>?

        //the capability to send the escrow bidVault to if you are outbid
        access(contract) var recipientVaultCap: Capability<&{FungibleToken.Receiver}>?

        //the capability for the owner of the NFT to return the item to if the auction is cancelled
        access(contract) let ownerCollectionCap: Capability<&{Webshot.CollectionPublic}>

        //the capability to pay the owner of the item when the auction is done
        access(contract) let ownerVaultCap: Capability<&{FungibleToken.Receiver}>

        access(contract) var extensionOnLateBid: UFix64

        //The id of the NFT
        pub let webshotId: UInt64

        //Store metadata here would allow us to show this after the drop has ended. The NFTS are gone then but the  metadata remains here
        pub let metadata: Webshot.Metadata

        init(
            NFT: @Webshot.NFT,
            minimumBidIncrement: UFix64,
            auctionStartTime: UFix64,
            startPrice: UFix64,
            duration: UFix64,
            extensionOnLateBid: UFix64,
            ownerCollectionCap: Capability<&{Webshot.CollectionPublic}>,
            ownerVaultCap: Capability<&{FungibleToken.Receiver}>) {

            Drop.totalAuctions = Drop.totalAuctions + (1 as UInt64)
            self.auctionId = Drop.totalAuctions
            self.firstBidBlock = nil
            self.settledAt = nil
            self.webshotId = NFT.id
            self.metadata = NFT.metadata
            self.NFT <- NFT
            self.bidVault <- FlowToken.createEmptyVault()
            self.minimumBidIncrement = minimumBidIncrement
            self.duration = duration
            self.startPrice = startPrice
            self.currentPrice = 0.0
            self.auctionStartTime = auctionStartTime
            self.auctionSettled = false
            self.recipientCollectionCap = nil
            self.recipientVaultCap = nil
            self.ownerCollectionCap = ownerCollectionCap
            self.ownerVaultCap = ownerVaultCap
            self.numberOfBids = 0
            self.extensionOnLateBid = extensionOnLateBid
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
            panic("Could not send tokens to non existent receiver")
        }

        pub fun releasePreviousBid() {
            if let vaultCap = self.recipientVaultCap {
                self.sendBidTokens(self.recipientVaultCap!)
                return
            }
        }

        //This method settles the Auction
        pub fun settle(cutPercentage: UFix64, cutVault: Capability<&{FungibleToken.Receiver}> )  {
            pre {
                !self.auctionSettled : "The auction is already settled"
                self.isAuctionExpired() : "The auction has not expired yet"
                self.NFT != nil: "NFT in auction does not exist"
            }

            // return if there are no bids to settle
            if self.currentPrice == 0.0{
                self.returnAuctionItemToOwner()
                return
            }

            //Withdraw cutPercentage to marketplace and put it in their vault
            let amountMarketplaceCut = self.currentPrice*cutPercentage
            let beneficiaryCut <- self.bidVault.withdraw(amount: amountMarketplaceCut)

            let cutVault = cutVault.borrow()!
            cutVault.deposit(from: <- beneficiaryCut)

            self.sendNFT(self.recipientCollectionCap!)
            self.sendBidTokens(self.ownerVaultCap)

            self.auctionSettled = true
            self.settledAt = getCurrentBlock().timestamp

            emit AuctionSettled(auctionId: self.auctionId, price: self.currentPrice)
        }

        pub fun returnAuctionItemToOwner() {
            // release the bidder's tokens
            self.releasePreviousBid()

            // deposit the NFT into the owner's collection
            self.sendNFT(self.ownerCollectionCap)

            self.auctionSettled = true
            self.settledAt = getCurrentBlock().timestamp
         }

         pub fun cancelAuction() {
            self.returnAuctionItemToOwner()
            emit AuctionCancelled(auctionId: self.auctionId)
        }

        //this can be negative if is expired
        pub fun timeRemaining(): Fix64 {
            let duration = self.duration

            let startTime = self.auctionStartTime
            let currentTime = getCurrentBlock().timestamp

            let remaining = Fix64(startTime) + Fix64(duration) - Fix64(currentTime)
            return remaining
        }

        pub fun isAuctionExpired(): Bool {
            let timeRemaining = self.timeRemaining()
            return timeRemaining < Fix64(0.0)
        }

        pub fun minNextBid(): UFix64{
            //If there are bids then the next min bid is the current price plus the increment
            if self.currentPrice != 0.0 {
                return self.currentPrice+self.minimumBidIncrement
            }
            //else start price
            return self.startPrice
        }

        //Extend an auction with a given set of blocks
        pub fun extendWith(_ amount: UFix64) {
            self.duration = self.duration + amount
        }

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

            let block = getCurrentBlock()
            let time = Fix64(block.timestamp)

            if auctionStatus.startTime > time {
                panic("The drop has not started")
            }

            if auctionStatus.endTime < time  {
                panic("This drop has ended")
            }

            //we save the time of the first bid so that it can be used to fetch events from that given block
            if self.firstBidBlock == nil {
                self.firstBidBlock = block.height
            }

            let bidEndTime = time + Fix64(self.extensionOnLateBid)

            //We need to extend the auction since there is too little time left. If we did not do this a late user could potentially win with a cheecky bid
            if auctionStatus.endTime < bidEndTime {
                let extendWith=bidEndTime - auctionStatus.endTime
                emit AuctionExtended(auctionId: self.auctionId, name: auctionStatus.metadata.name, owner: auctionStatus.metadata.owner, extendWith: extendWith, extendTo: bidEndTime)
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
            self.numberOfBids = self.numberOfBids + (1 as UInt64)

            let bidderAddress = vaultCap.borrow()!.owner!.address
            emit AuctionBid(auctionId: self.auctionId, name: auctionStatus.metadata.name, owner: auctionStatus.metadata.owner, bidder: bidderAddress, price: self.currentPrice)
        }

        pub fun getAuctionStatus(): AuctionStatus {

            var leader: Address? = nil
            if let recipient = self.recipientVaultCap {
                leader = recipient.borrow()!.owner!.address
            }

            return AuctionStatus(
                id: self.auctionId,
                webshotId: self.webshotId,
                startPrice: self.startPrice,
                currentPrice: self.currentPrice,
                bids: self.numberOfBids,
                timeRemaining: self.timeRemaining(),
                metadata: self.metadata,
                leader: leader,
                bidIncrement: self.minimumBidIncrement,
                owner: self.ownerVaultCap.borrow()!.owner!.address,
                startTime: Fix64(self.auctionStartTime),
                endTime: Fix64(self.auctionStartTime + self.duration),
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

            emit AuctionDestroyed(auctionId: self.auctionId)
        }

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
             duration: UFix64,
             extensionOnLateBid:UFix64)

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
            self.marketplaceNFTUnsold = marketplaceNFTUnsold
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
             duration: UFix64,
             extensionOnLateBid:UFix64) {

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
                duration: duration,
                extensionOnLateBid: extensionOnLateBid,
                ownerCollectionCap: self.marketplaceNFTUnsold,
                ownerVaultCap: vaultCap
            )

            emit AuctionCreated(auctionId: auction.auctionId, name: metadata.name, owner: metadata.owner, ownerAddress: vaultCap.borrow()!.owner!.address)

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

        access(contract) fun getAuction(_ auctionId: UInt64): &Auction {
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
        pub fun getWebshot(auctionId: UInt64): Webshot.Metadata {
            let auction = self.getAuction(auctionId)
            return auction.metadata
        }

        //settle an auction
        pub fun settle(_ auctionId: UInt64) {
            self.getAuction(auctionId).settle(cutPercentage: self.cutPercentage, cutVault: self.marketplaceVault)
       }

        //place a bid, will just delegate to the method in the drop collection
        pub fun placeBid(
            auctionId: UInt64,
            bidTokens: @FungibleToken.Vault,
            vaultCap: Capability<&{FungibleToken.Receiver}>,
            collectionCap: Capability<&{Webshot.CollectionPublic}>
        ) {
            self.getAuction(auctionId).placeBid(
                bidTokens: <- bidTokens,
                vaultCap: vaultCap,
                collectionCap: collectionCap
            )
        }

        destroy() {
            destroy self.auctions
        }
    }

    // Get the Webshot stored with a specific Auction
    pub fun getWebshotForAuction(_ auctionId: UInt64) : Webshot.Metadata? {
        let auctionCap = Drop.account.getCapability<&{Drop.AuctionPublic}>(self.CollectionPublicPath)
        if let auction = auctionCap.borrow()  {
            return auction.getWebshot(auctionId: auctionId)
        }
        return nil
    }

    pub fun getAuction(_ auctionId: UInt64) : Drop.AuctionStatus? {
      let account = Drop.account
      let auctionCap = account.getCapability<&{Drop.AuctionPublic}>(self.CollectionPublicPath)
      if let auction = auctionCap.borrow() {
          return auction.getStatus(auctionId: auctionId)
      }
      return nil
    }

    // Get all the Auctions
    pub fun getAuctions() : [Drop.AuctionStatus]{
        let account = Drop.account
        let auctionCap = account.getCapability<&{Drop.AuctionPublic}>(self.CollectionPublicPath)!
        return auctionCap.borrow()!.getAllStatuses().values
     }

     // Get the active Auctions
     pub fun getActiveAuctions() : [Drop.AuctionStatus]{
         let account = Drop.account
         let activeAuctions: [Drop.AuctionStatus] = [];
         let auctionCap = account.getCapability<&{Drop.AuctionPublic}>(self.CollectionPublicPath)!
         let auctionStatus = auctionCap.borrow()!.getAllStatuses()
         for s in auctionStatus.values {
             if s.active != false {
                 activeAuctions.append(s)
             }
         }
         return activeAuctions
      }

    //The interface used to add a Administrator capability to a client
    pub resource interface AdminPublic {
        pub fun addCapability(_ cap: Capability<&Drop.AuctionCollection>)
    }

    //The versus admin resource that a client will create and store, then link up a public VersusAdminClient
    pub resource Admin: AdminPublic {

        access(self) var server: Capability<&Drop.AuctionCollection>?

        init() {
            self.server = nil
        }

        pub fun addCapability(_ cap: Capability<&Drop.AuctionCollection>) {
            pre {
                cap.check() : "Invalid server capability"
                self.server == nil : "Server already set"
            }
            self.server = cap
        }

        // This will settle/end an auction
        pub fun settle(_ auctionId: UInt64) {
           pre {
             self.server != nil : "Your client has not been linked to the server"
           }
           self.server!.borrow()!.settle(auctionId)

        }

        pub fun setAuctionCut(_ num:UFix64) {
            pre {
                self.server != nil : "Your client has not been linked to the server"
            }

            let auctionC: &Drop.AuctionCollection = self.server!.borrow()!
            auctionC.cutPercentage = num
        }

        //This method can only be called from another contract in the same account. In Website case it is called from the AuctionAdmin that is used to administer the solution
        pub fun createWebsite(
            name: String,
            url: String,
            ownerName: String,
            ownerAddress: Address,
            description: String,
            webshotMinInterval: UInt64,
            isRecurring: Bool) : @Website.NFT {

            pre {
                self.server != nil : "Your client has not been linked to the server"
            }

            let website <- Website.createWebsite(
                name: name,
                url: url,
                ownerName: ownerName,
                ownerAddress: ownerAddress,
                description: description,
                webshotMinInterval: webshotMinInterval,
                isRecurring: isRecurring)
            return <- website

        }

        pub fun createAuction(
          nft: @NonFungibleToken.NFT,
          minimumBidIncrement: UFix64,
          startTime: UFix64,
          startPrice: UFix64,
          vaultCap: Capability<&{FungibleToken.Receiver}>
          duration: UFix64,
          extensionOnLateBid: UFix64)  {

          pre {
              self.server != nil : "Your client has not been linked to the server"
          }

          self.server!.borrow()!.createAuction(nft: <- nft,
            minimumBidIncrement: minimumBidIncrement,
            startTime: startTime,
            startPrice: startPrice,
            vaultCap: vaultCap,
            duration: duration,
            extensionOnLateBid: extensionOnLateBid
          )
        }

        // A stored Transaction to mintWebshot on Auction to a given artist
        pub fun mintWebshot(
            websiteAddress: Address,
            websiteId: UInt64,
            ipfs: {String: String},
            content: String,
            imgUrl: String) : @Webshot.NFT {

            pre {
                self.server != nil : "Your client has not been linked to the server"
            }

            let websiteData = Website.getWebsite(address: websiteAddress, id: websiteId)!

            let ownerAccount = getAccount(websiteData.ownerAddress)

            let ownerWallet = ownerAccount.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            let webshotWallet =  Drop.account.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)

            let royalty = {
                "owner" : Webshot.Royalty(wallet: ownerWallet, cut: 0.05),
                "marketplace" : Webshot.Royalty(wallet: webshotWallet, cut: 0.025)
            }

            return <- self.mintWebshotWithRoyalty(
                websiteAddress: websiteAddress,
                websiteId: websiteId,
                ipfs: ipfs,
                content: content,
                imgUrl: imgUrl,
                royalty: royalty)
        }

        // A stored Transaction to mintWebshot on Auction to a given artist
        pub fun mintWebshotWithRoyalty(
            websiteAddress: Address,
            websiteId: UInt64,
            ipfs: {String: String},
            content: String,
            imgUrl: String,
            royalty: {String: Webshot.Royalty}
            ) : @Webshot.NFT {

            pre {
                self.server != nil : "Your client has not been linked to the server"
                Website.lastWebshotMintedAt[websiteId] != nil : "Can't find Website in Collection"
                Website.totalMintedWebshots[websiteId] != nil : "Can't find Website in Collection"
            }

            let websiteData = Website.getWebsite(address: websiteAddress, id: websiteId)!

            let currentTime = getCurrentBlock().timestamp

            let lastMintedTime = UInt64(Website.lastWebshotMintedAt[websiteId]!)

            if(lastMintedTime + websiteData.webshotMinInterval > UInt64(currentTime) && lastMintedTime != UInt64(0)){
                panic("You are trying to mint a Webshot too soon!")
            }

            let webshot <- Webshot.createWebshot(
                websiteAddress: websiteAddress,
                websiteId: websiteId,
                name: websiteData.name,
                url: websiteData.url,
                owner: websiteData.ownerName,
                ownerAddress: websiteData.ownerAddress,
                description: websiteData.description,
                date: currentTime,
                ipfs: ipfs,
                content: content,
                imgUrl: imgUrl,
                royalty: royalty)

            return <- webshot
        }

        pub fun getFlowWallet():&FungibleToken.Vault {
          pre {
            self.server != nil : "Your client has not been linked to the server"
          }
          return Drop.account.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)!
        }

        pub fun getWebshotCollection() : &NonFungibleToken.Collection {
          pre {
            self.server != nil : "Your client has not been linked to the server"
          }
          return Drop.account.borrow<&NonFungibleToken.Collection>(from: Webshot.CollectionStoragePath)!
        }

    }

    //make it possible for a user that wants to be a versus admin to create the client
    pub fun createAdminClient(): @Admin {
        return <- create Admin()
    }

    //initialize all the paths and create and link up the admin proxy
    init() {

        self.CollectionPublicPath = /public/AuctionCollection
        self.CollectionStoragePath = /storage/AuctionCollection
        self.CollectionPrivatePath= /private/AuctionCollection
        self.WebshotAdminPublicPath = /public/WebshotAdmin
        self.WebshotAdminStoragePath = /storage/WebshotAdmin

        self.totalAuctions = (0 as UInt64)

        let account = self.account

        let marketplaceReceiver = account.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
        let marketplaceNFTUnsold: Capability<&{Webshot.CollectionPublic}> = account.getCapability<&{Webshot.CollectionPublic}>(Webshot.CollectionPublicPath)

        log("Setting up auction capability")
        let collection <- create AuctionCollection(
            marketplaceVault: marketplaceReceiver,
            marketplaceNFTUnsold: marketplaceNFTUnsold,
            cutPercentage: 0.2
        )
        account.save(<-collection, to: Drop.CollectionStoragePath)
        account.link<&{Drop.AuctionPublic}>(Drop.CollectionPublicPath, target: Drop.CollectionStoragePath)
        account.link<&Drop.AuctionCollection>(Drop.CollectionPrivatePath, target: Drop.CollectionStoragePath)

    }
}
