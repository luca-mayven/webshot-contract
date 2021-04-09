import WebshotMarket from "../../contracts/WebshotMarket.cdc"

// This script returns an array of all the NFT IDs for sale 
// in an account's SaleOffer collection.

pub fun main(address: Address): Int {
    let saleOfferCollectionRef = getAccount(address)
        .getCapability<&WebshotMarket.SaleOfferCollection{WebshotMarket.SaleOfferPublic}>(
            WebshotMarket.SaleOfferCollectionPublicPath
        )
        .borrow()
        ?? panic("Could not borrow market collection from market address")
    
    return saleOfferCollectionRef.getSaleOfferIDs().length
}
