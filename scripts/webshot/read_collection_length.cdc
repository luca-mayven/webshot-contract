import NonFungibleToken from "../../contracts/NonFungibleToken.cdc"
import Webshot from "../../contracts/Webshot.cdc"

// This script returns the size of an account's Webshot collection.

pub fun main(address: Address): Int {
    let account = getAccount(address)

    let collectionRef = account.getCapability(Webshot.CollectionPublicPath)!
        .borrow<&{NonFungibleToken.CollectionPublic}>()
        ?? panic("Could not borrow capability from public collection")
    
    return collectionRef.getIDs().length
}
