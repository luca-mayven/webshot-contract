import FungibleToken from "./FungibleToken.cdc"
import FlowToken from "./FlowToken.cdc"
import NonFungibleToken from "./NonFungibleToken.cdc"
import Webshot from "./Webshot.cdc"
//import FungibleToken from 0x9a0766d93b6608b7
//import FUSD from 0xe223d8a629e49c68



/*
// A standard marketplace contract only hardcoded against Webshots that pay out Royalty as stored int he Webshot NFT

 This contract based on the following git repo

 - The Versus Auction contract created by Bjartek and Alchemist
 https://github.com/versus-flow/auction-flow-contract
*/

pub contract Marketplace {

    pub let CollectionPublicPath: PublicPath
    pub let CollectionStoragePath: StoragePath

    // Event that is emitted when a new NFT is put up for sale
    pub event ForSale(id: UInt64, price: UFix64, address: Address)

    // Event that is emitted when the price of an NFT changes
    pub event PriceChanged(id: UInt64, newPrice: UFix64, address: Address)

    // Event that is emitted when a token is purchased
    pub event WebshotPurchased(id: UInt64, price: UFix64, from: Address, to: Address)

    pub event RoyaltyPaid(id: UInt64, amount: UFix64, to: Address, name: String)

    // Event that is emitted when a seller withdraws their NFT from the sale
    pub event SaleWithdrawn(tokenId: UInt64, address: Address)

    // Interface that users will publish for their Sale collection
    // that only exposes the methods that are supposed to be public
    //
    pub resource interface SalePublic {
        pub fun purchase(tokenId: UInt64, recipientCap: Capability<&{Webshot.CollectionPublic}>, buyTokens: @FungibleToken.Vault)
        pub fun getPrice(tokenId: UInt64): UFix64?
        pub fun getIDs(): [UInt64]
        pub fun getWebshot(tokenId: UInt64): &{Webshot.Public}?
    }

    // SaleCollection
    //
    // NFT Collection object that allows a user to put their NFT up for sale
    // where others can send fungible tokens to purchase it
    //
    pub resource SaleCollection: SalePublic {

        // Dictionary of the NFTs that the user is putting up for sale
        pub var forSale: @{UInt64: Webshot.NFT}

        // Dictionary of the prices for each NFT by ID
        pub var prices: {UInt64: UFix64}

        // The fungible token vault of the owner of this sale.
        // When someone buys a token, this resource can deposit
        // tokens into their account.
        access(account) let ownerVault: Capability<&AnyResource{FungibleToken.Receiver}>

        init (vault: Capability<&AnyResource{FungibleToken.Receiver}>) {
            self.forSale <- {}
            self.ownerVault = vault
            self.prices = {}
        }

        // withdraw gives the owner the opportunity to remove a sale from the collection
        pub fun withdraw(tokenId: UInt64): @Webshot.NFT {
            // remove the price
            self.prices.remove(key: tokenId)
            // remove and return the token
            let token <- self.forSale.remove(key: tokenId) ?? panic("missing NFT")


            let vaultRef = self.ownerVault.borrow()
                ?? panic("Could not borrow reference to owner token vault")
            emit SaleWithdrawn(tokenId: tokenId, address: vaultRef.owner!.address)
            return <-token
        }

        // listForSale lists an NFT for sale in this collection
        pub fun listForSale(token: @Webshot.NFT, price: UFix64) {
            let id = token.id

            // store the price in the price array
            self.prices[id] = price

            // put the NFT into the the forSale dictionary
            let oldToken <- self.forSale[id] <- token
            destroy oldToken

            let vaultRef = self.ownerVault.borrow()
                ?? panic("Could not borrow reference to owner token vault")
            emit ForSale(id: id, price: price, address: vaultRef.owner!.address)
        }

        // changePrice changes the price of a token that is currently for sale
        pub fun changePrice(tokenId: UInt64, newPrice: UFix64) {
            self.prices[tokenId] = newPrice

            let vaultRef = self.ownerVault.borrow()
                ?? panic("Could not borrow reference to owner token vault")
            emit PriceChanged(id: tokenId, newPrice: newPrice, address: vaultRef.owner!.address)
        }

        // purchase lets a user send tokens to purchase an NFT that is for sale
        pub fun purchase(tokenId: UInt64, recipientCap: Capability<&{Webshot.CollectionPublic}>, buyTokens: @FungibleToken.Vault) {
            pre {
                self.forSale[tokenId] != nil && self.prices[tokenId] != nil:
                    "No token matching this ID for sale!"
                buyTokens.balance >= (self.prices[tokenId] ?? 0.0):
                    "Not enough tokens to buy the NFT!"
            }

            let recipient=recipientCap.borrow()!

            // get the value out of the optional
            let price = self.prices[tokenId]!

            self.prices[tokenId] = nil

            let vaultRef = self.ownerVault.borrow()
                ?? panic("Could not borrow reference to owner token vault")

            let token <-self.withdraw(tokenId: tokenId)

            for royalty in token.royalty.keys {
                let royaltyData = token.royalty[royalty]!
                let amount = price * royaltyData.cut
                let wallet = royaltyData.wallet.borrow()!

                let royaltyWallet <- buyTokens.withdraw(amount: amount)

                wallet.deposit(from: <- royaltyWallet)

                emit RoyaltyPaid(id: tokenId, amount:amount, to: wallet.owner!.address, name:royalty)
            }
            // deposit the purchasing tokens into the owners vault
            vaultRef.deposit(from: <-buyTokens)

            // deposit the NFT into the buyers collection
            recipient.deposit(token: <- token)

            emit WebshotPurchased(id: tokenId, price: price, from: vaultRef.owner!.address, to:  recipient.owner!.address)
        }

        // idPrice returns the price of a specific token in the sale
        pub fun getPrice(tokenId: UInt64): UFix64? {
            return self.prices[tokenId]
        }

        // getIDs returns an array of token IDs that are for sale
        pub fun getIDs(): [UInt64] {
            return self.forSale.keys
        }
        // borrowSale returns a borrowed reference to a Sale
        // so that the caller can read data and call methods from it.
        //
        // Parameters: id: The ID of the Sale NFT to get the reference for
        //
        // Returns: A reference to the NFT
        pub fun getWebshot(tokenId: UInt64): &{Webshot.Public}? {
            if self.forSale[tokenId] != nil {
                let ref = &self.forSale[tokenId] as auth &NonFungibleToken.NFT
                return ref as! &Webshot.NFT
            } else {
                return nil
            }
        }

        destroy() {
            destroy self.forSale
        }
    }


    pub struct SaleData {
        pub let id: UInt64
        pub let price: UFix64
        pub let metadata: Webshot.Metadata

        init(
            id: UInt64,
            price: UFix64,
            metadata: Webshot.Metadata){

            self.id = id
            self.price = price
            self.metadata = metadata
        }
    }


    pub fun getSales(address: Address) : [SaleData] {
        var saleData: [SaleData] = []
        let account = getAccount(address)

        if let saleCollection = account.getCapability(self.CollectionPublicPath).borrow<&{Marketplace.SalePublic}>()  {
            for id in saleCollection.getIDs() {
                let price = saleCollection.getPrice(tokenId: id)
                let webshot = saleCollection.getWebshot(tokenId: id)
                saleData.append(SaleData(
                    id: id,
                    price: price!,
                    metadata: webshot!.metadata
                    ))
            }
        }
        return saleData
    }

    pub fun getSale(address: Address, id: UInt64) : SaleData? {

        let account = getAccount(address)

        if let saleCollection = account.getCapability(self.CollectionPublicPath).borrow<&{Marketplace.SalePublic}>()  {
            if let webshot = saleCollection.getWebshot(tokenId: id) {
                let price = saleCollection.getPrice(tokenId: id)
                return SaleData(
                           id: id,
                            price: price!,
                            metadata: webshot.metadata
                           )
            }
        }
        return nil
    }





    // createCollection returns a new collection resource to the caller
    pub fun createSaleCollection(ownerVault: Capability<&{FungibleToken.Receiver}>): @SaleCollection {
        return <- create SaleCollection(vault: ownerVault)
    }



    pub init() {
        //TODO: REMOVE SUFFIX BEFORE RELEASE
        self.CollectionPublicPath= /public/WebshotMarketplace002
        self.CollectionStoragePath= /storage/WebshotMarketplace002
    }
}
