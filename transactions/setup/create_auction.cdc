import FungibleToken from "../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Website from "../../contracts/Website.cdc"
import Webshot from "../../contracts/Webshot.cdc"
import WebshotMarket from "../../contracts/WebshotMarket.cdc"


//this transaction will setup a webshot auction
transaction(
    websiteAddress: Address,
    name: String,
    url: String,
    owner:String,
    ownerAddress:Address,
    description: String,
    date: String,
    ipfs: String,
    content: String,
    imgUrl: String,
    royalty: {String: Royalty}
    minimumBidIncrement: UFix64,
    startTime: UFix64,
    startPrice: UFix64,
    vaultCap: Capability<&{FungibleToken.Receiver}>,
    webshotAdmin: &Webshot.Administrator,
    auctionLength: UFix64,
    extentionOnLateBid:UFix64) {

    let client: &Versus.Admin
    let artistWallet: Capability<&{FungibleToken.Receiver}>

    prepare(account: AuthAccount) {

        self.client = account.borrow<&Versus.Admin>(from: Versus.VersusAdminStoragePath) ?? panic("could not load versus admin")
        self.artistWallet=  getAccount(artist).getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
    }

    execute {

        let webshot <-  self.client.mintArt(artist: artist, artistName: artistName, artName: artName, content:content, description: description)

        self.client.createDrop(
            nft: <- webshot,
            minimumBidIncrement: UFix64,
            startTime: UFix64,
            startPrice: UFix64,
            vaultCap: Capability<&{FungibleToken.Receiver}>,
            webshotAdmin: &Webshot.Administrator,
            auctionLength: UFix64,
            extentionOnLateBid:UFix64
       )

       let content=self.client.getContent()
       log(content.contents.keys)

       let wallet=self.client.getFlowWallet()
       log(wallet.balance)


    }
}
