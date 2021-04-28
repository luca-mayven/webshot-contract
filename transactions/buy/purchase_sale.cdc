
//import FungibleToken from 0xee82856bf20e2aa6
import FungibleToken from "../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Website from "../../contracts/Website.cdc"
import Webshot from "../../contracts/Webshot.cdc"
import Marketplace from "../../contracts/Marketplace.cdc"
import Drop from "../../contracts/Drop.cdc"


//this transaction buy a Webshot from a direct sale listing from another user
transaction(saleAddress: Address, tokenID: UInt64, amount: UFix64) {

    // reference to the buyer's NFT collection where they
    // will store the bought NFT

    let vaultCap: Capability<&{FungibleToken.Receiver}>
    let collectionCap: Capability<&{Webshot.CollectionPublic}>
    // Vault that will hold the tokens that will be used
    // to buy the NFT
    let temporaryVault: @FungibleToken.Vault

    prepare(account: AuthAccount) {

        // get the references to the buyer's Vault and NFT Collection receiver
        var collectionCap = account.getCapability<&{Webshot.CollectionPublic}>(Webshot.CollectionPublicPath)

        // if collection is not created yet we make it.
        if !collectionCap.check() {
            // store an empty NFT Collection in account storage
            account.save<@NonFungibleToken.Collection>(<- Webshot.createEmptyCollection(), to: Webshot.CollectionStoragePath)

            // publish a capability to the Collection in storage
            account.link<&{Webshot.CollectionPublic}>(Webshot.CollectionPublicPath, target: Webshot.CollectionStoragePath)
        }

        self.collectionCap = collectionCap

        self.vaultCap = account.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)

        let vaultRef = account.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault) ?? panic("Could not borrow owner's Vault reference")

        // withdraw tokens from the buyer's Vault
        self.temporaryVault <- vaultRef.withdraw(amount: amount)
    }

    execute {
        // get the read-only account storage of the seller
        let seller = getAccount(saleAddress)

        let marketplace= seller.getCapability(Marketplace.CollectionPublicPath).borrow<&{Marketplace.SalePublic}>()
                         ?? panic("Could not borrow seller's sale reference")

        marketplace.purchase(tokenID: tokenID, recipientCap:self.collectionCap, buyTokens: <- self.temporaryVault)
    }

}