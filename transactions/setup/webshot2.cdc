
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
transaction(ownerAddress: Address) {

    prepare(account: AuthAccount) {

        let owner = getAccount(ownerAddress)

        let client = owner.getCapability<&{WebshotMarket.WebshotMarketAdminClient}>(WebshotMarket.WebshotMarketAdminClientPublicPath)
                .borrow() ?? panic("Could not borrow admin client")
        let webshotMarketAdminCap = account.getCapability<&WebshotMarket.Administrator>(WebshotMarket.WebshotMarketAdministratorPrivatePath)
        client.addCapability(webshotMarketAdminCap)


        let websiteClient = owner.getCapability<&{Website.AdministratorClient}>(Website.AdministratorPublicPath)
            .borrow() ?? panic("Could not borrow website admin client")
        let minterWebsite = account.getCapability<&Website.Minter>(Website.MinterPrivatePath)
        websiteClient.addCapability(minterWebsite)

        let webshotClient = owner.getCapability<&{Webshot.AdministratorClient}>(Webshot.AdministratorPublicPath)
            .borrow() ?? panic("Could not borrow webshot admin client")
        let minterWebshot = account.getCapability<&Webshot.Minter>(Webshot.MinterPrivatePath)
        webshotClient.addCapability(minterWebshot)

    }
}
