
//import FungibleToken from 0xee82856bf20e2aa6
import FungibleToken from "../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Website from "../../contracts/Website.cdc"
import Webshot from "../../contracts/Webshot.cdc"
import Marketplace from "../../contracts/Marketplace.cdc"
import Drop from "../../contracts/Drop.cdc"


//this transaction is run as the account that will host and own the marketplace to set up the
//webshotAdmin client and create the empty content and webshot collection
transaction(id: UInt64) {

    let auctionCollection: &Drop.AuctionCollection

    prepare(account: AuthAccount) {

        self.auctionCollection = account.borrow<&Drop.AuctionCollection>(from: Drop.CollectionStoragePath)!
    }

    execute {

        let auction <- self.auctionCollection.auctions[id] <- nil
        destroy auction

    }
}