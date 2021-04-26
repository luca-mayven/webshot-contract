import FungibleToken from "../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Website from "../../contracts/Website.cdc"
import Webshot from "../../contracts/Webshot.cdc"
import WebshotMarket from "../../contracts/WebshotMarket.cdc"


//this transaction will setup a website collection
transaction() {

    prepare(account: AuthAccount) {
        if account.borrow<&Website.Collection>(from: Website.CollectionStoragePath) == nil {
            account.save<@NonFungibleToken.Collection>(<- Website.createEmptyCollection(), to: Website.CollectionStoragePath)
            account.link<&{Website.CollectionPublic}>(Website.CollectionPublicPath, target: Website.CollectionStoragePath)
        }
    }
}
