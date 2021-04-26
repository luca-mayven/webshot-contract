
//import FungibleToken from 0xee82856bf20e2aa6
import FungibleToken from "../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Website from "../../contracts/Website.cdc"
import Webshot from "../../contracts/Webshot.cdc"
import WebshotMarket from "../../contracts/WebshotMarket.cdc"


//local emulator
//import FungibleToken from 0xee82856bf20e2aa6
//import NonFungibleToken, Website, Webshot, WebshotMarket from 0x1ff7e32d71183db0


//these are testnet
//import FungibleToken from 0x9a0766d93b6608b7
//import NonFungibleToken from 0x631e88ae7f1d7c20
//import Website, Webshot, WebshotMarket from 0x1ff7e32d71183db0

//this transaction is run as the account that will host and own the marketplace to set up the
//webshotAdmin client and create the empty content and webshot collection
transaction {

    prepare(owner: AuthAccount) {


        // if the account doesn't already have a Website collection
        if owner.borrow<&Website.Collection>(from: Website.CollectionStoragePath) == nil {

            //create a Website admin client
            owner.save(<- Website.createAdminClient(), to:Website.AdministratorStoragePath)
            owner.link<&{Website.AdministratorClient}>(Website.AdministratorPublicPath, target: Website.AdministratorStoragePath)
        }

        // if the account doesn't already have a Webshot collection
        if owner.borrow<&Webshot.Collection>(from: Webshot.CollectionStoragePath) == nil {

            //create a Webshot admin client
            owner.save(<- Webshot.createAdminClient(), to:Webshot.AdministratorStoragePath)
            owner.link<&{Webshot.AdministratorClient}>(Webshot.AdministratorPublicPath, target: Webshot.AdministratorStoragePath)
        }

        // if the account doesn't already have a WebshotMarket Admin Client
        if owner.borrow<&WebshotMarket.WebshotMarketAdmin>(from: WebshotMarket.WebshotMarketAdminClientStoragePath) == nil {
            //create WebshotMarket admin client
            owner.save(<- WebshotMarket.createAdminClient(), to:WebshotMarket.WebshotMarketAdminClientStoragePath)
            owner.link<&WebshotMarket.WebshotMarketAdmin{WebshotMarket.WebshotMarketAdminClient}>(WebshotMarket.WebshotMarketAdminClientPublicPath, target: WebshotMarket.WebshotMarketAdminClientStoragePath)
        }

    }
}
