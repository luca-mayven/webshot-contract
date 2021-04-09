import WebshotMarket from "../../contracts/WebshotMarket.cdc"

// This script returns an array of all the NFT IDs for sale 
// in an account's Auction collection.

pub fun main(address: Address): [UInt64] {
    let marketCollectionRef = getAccount(address)
        .getCapability<&WebshotMarket.AuctionCollection{WebshotMarket.AuctionPublic}>(
            WebshotMarket.CollectionPublicPath
        )
        .borrow()
        ?? panic("Could not borrow market collection from market address")
    
    return marketCollectionRef.getAllStatuses()
}
