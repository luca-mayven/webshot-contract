import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Webshot from "../../contracts/Webshot.cdc"

// This script returns the metadata for an NFT in an account's collection.

pub fun main(address: Address, itemID: UInt64): UInt64 {

    // get the public account object for the token owner
    let owner = getAccount(address)

    let collectionBorrow = owner.getCapability(Webshot.CollectionPublicPath)!
        .borrow<&{Webshot.CollectionPublic}>()
        ?? panic("Could not borrow Webshot CollectionPublic")

    // borrow a reference to a specific NFT in the collection
    let webshot = collectionBorrow.borrowWebshot(id: itemID)
        ?? panic("No such itemID in that collection")

    return webshot.metadata
}
