import FungibleToken from "../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Website from "../../contracts/Website.cdc"
import Webshot from "../../contracts/Webshot.cdc"
import WebshotMarket from "../../contracts/WebshotMarket.cdc"


//this transaction will setup a webshot collection
transaction(id: UInt64) {

    prepare(account: AuthAccount) {
        self.webshotMarket= account.borrow<&WebshotMarket.AuctionCollection>(from: WebshotMarket.CollectionStoragePath)!
    }

    execute {

        let auction <- self.webshotMarket.auctions[id] <- nil
        destroy auction

    }
}
