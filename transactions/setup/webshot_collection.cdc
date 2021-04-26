import FungibleToken from "../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Website from "../../contracts/Website.cdc"
import Webshot from "../../contracts/Webshot.cdc"
import WebshotMarket from "../../contracts/WebshotMarket.cdc"


//this transaction will setup a webshot collection
transaction() {

    prepare(account: AuthAccount) {
        if account.borrow<&Webshot.Collection>(from: Webshot.CollectionStoragePath) == nil {
            account.save<@NonFungibleToken.Collection>(<- Webshot.createEmptyCollection(), to: Webshot.CollectionStoragePath)
            account.link<&{Webshot.CollectionPublic}>(Webshot.CollectionPublicPath, target: Webshot.CollectionStoragePath)
        }
    }
}
