
import NonFungibleToken from "./NonFungibleToken.cdc"
import FungibleToken from "./FungibleToken.cdc"
//import FungibleToken from 0x9a0766d93b6608b7
//import FUSD from 0xe223d8a629e49c68

/*

 The contract that defines the Webshot NFT and a Collection to manage them

 This contract is based on a mix of 2 other contracts:

 - The Versus Auction contract created by Bjartek and Alchemist
 https://github.com/versus-flow/auction-flow-contract

 - The Kitty items demo from the Flow team
 https://github.com/onflow/kitty-items


 Each Webshot has a Metadata struct containing both the IPFS URL with the high-res copy of the screenshot, and also a small thumbnail saved on-chain in the "content" field

 royalty defines the percentage cut for the Owner and the Market to be applied in direct sales

 */


pub contract Webshot: NonFungibleToken {

    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let MinterStoragePath: StoragePath
    pub let MinterPrivatePath: PrivatePath
    pub let AdministratorPublicPath: PublicPath
    pub let AdministratorStoragePath:StoragePath

    pub var totalSupply: UInt64

    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)
    pub event Minted(id: UInt64, metadata: Metadata)

    //The public interface can show metadata and the content for the Webshot
    pub resource interface Public {
        pub let id: UInt64
        pub let metadata: Metadata
    }

    //content is embedded in the NFT both as content and as URL pointing to an IPFS
    pub struct Metadata {
        pub let name: String
        pub let url: String
        pub let owner: String
        pub let ownerAddress:Address
        pub let description: String
        pub let date: String
        pub let ipfs: String
        pub let content: String
        pub let imgUrl: String

        init(
            name: String,
            url: String,
            owner: String,
            ownerAddress:Address,
            description: String,
            date: String,
            ipfs: String,
            content: String,
            imgUrl: String) {
                self.name = name
                self.url = url
                self.owner = owner
                self.ownerAddress = ownerAddress
                self.description = description
                self.date = date
                self.ipfs = ipfs
                self.content=content
                self.imgUrl=imgUrl
        }
    }

    pub struct Royalty{
        pub let wallet: Capability<&{FungibleToken.Receiver}>
        pub let cut: UFix64

        init(wallet: Capability<&{FungibleToken.Receiver}>, cut: UFix64 ){
           self.wallet = wallet
           self.cut = cut
        }
    }

    pub resource NFT: NonFungibleToken.INFT, Public {
        pub let id: UInt64
        pub let metadata: Metadata
        pub let royalty: {String: Royalty}

        init(
            initID: UInt64,
            metadata: Metadata,
            royalty: {String: Royalty}) {

            self.id = initID
            self.metadata = metadata
            self.royalty = royalty
        }

        pub fun getID(): UInt64 {
            return self.id
        }


        pub fun getMetadata(): Metadata {
            return self.metadata
        }

        pub fun getRoyalty(): {String: Royalty} {
            return self.royalty
        }


    }


    //Standard NFT collectionPublic interface that can also borrowWebshot as the correct type
    pub resource interface WebshotCollectionPublic {

        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowWebshot(id: UInt64): &{Webshot.Public}?
    }


    pub resource Collection: WebshotCollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // dictionary of NFT conforming tokens
        // NFT is a resource type with an `UInt64` ID field
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        init () {
            self.ownedNFTs <- {}
        }

        // withdraw removes an NFT from the collection and moves it to the caller
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("missing NFT")

            emit Withdraw(id: token.id, from: self.owner?.address)

            return <-token
        }

        // deposit takes a NFT and adds it to the collections dictionary
        // and adds the ID to the id array
        pub fun deposit(token: @NonFungibleToken.NFT) {
            let token <- token as! @Webshot.NFT

            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        // getIDs returns an array of the IDs that are in the collection
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        // borrowNFT gets a reference to an NFT in the collection
        // so that the caller can read its metadata and call its methods
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT
        }

        // borrowWebshot returns a borrowed reference to a Webshot
        // so that the caller can read data and call methods from it.
        //
        // Parameters: id: The ID of the NFT to get the reference for
        //
        // Returns: A reference to the NFT
        pub fun borrowWebshot(id: UInt64): &{Webshot.Public}? {
            if self.ownedNFTs[id] != nil {
                let ref = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT
                return ref as! &Webshot.NFT
            } else {
                return nil
            }
        }


        destroy() {
            destroy self.ownedNFTs
        }
    }

    // public function that anyone can call to create a new empty collection
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        return <- create Collection()
    }


    // We cannot return the content here since it will be too big to run in a script
    pub fun getWebshotIDs(address:Address) : [UInt64] {

        let account=getAccount(address)

        let webshotCollection = account.getCapability(self.CollectionPublicPath)!.borrow<&Webshot.Collection{Webshot.WebshotCollectionPublic}>() ?? panic("Couldn't get collection")

        return webshotCollection.getIDs();
    }



    pub resource Minter {

        pub fun mintNFT(
            name: String,
            url: String,
            owner:String,
            ownerAddress:Address,
            description: String,
            date: String,
            ipfs: String,
            content: String,
            imgUrl: String,
            royalty: {String: Royalty}) : @Webshot.NFT {
            var newNFT <- create NFT(
                initID: Webshot.totalSupply,
                metadata: Metadata(
                    name: name,
                    url: url,
                    owner: owner,
                    ownerAddress: ownerAddress,
                    description: description,
                    date: date,
                    ipfs: ipfs,
                    content: content,
                    imgUrl: imgUrl
                ),
                royalty: royalty
            )
            emit Minted(id: Webshot.totalSupply, metadata: newNFT.metadata)

            Webshot.totalSupply = Webshot.totalSupply + UInt64(1)
            return <- newNFT

        }

    }


     //The interface used to add a Administrator capability to a client
    pub resource interface AdministratorClient {
        pub fun addCapability(_ cap: Capability<&Minter>)
    }


    //The admin resource that a client will create and store, then link up a public AdminClient
    pub resource Administrator: AdministratorClient {

        access(self) var server: Capability<&Minter>?

        init() {
            self.server = nil
        }

         pub fun addCapability(_ cap: Capability<&Minter>) {
            pre {
                cap.check() : "Invalid server capablity"
                self.server == nil : "Server already set"
            }
            self.server = cap
        }

        pub fun mintNFT(
            name: String,
            url: String,
            owner:String,
            ownerAddress:Address,
            description: String,
            date: String,
            ipfs: String,
            content: String,
            imgUrl: String,
            royalty: {String: Royalty}) : @Webshot.NFT {

            pre {
                self.server != nil:
                    "Cannot create art if server is not set"
            }
            return <- self.server!.borrow()!.mintNFT(
                name: name,
                url: url,
                owner: owner,
                ownerAddress: ownerAddress,
                description: description,
                date: date,
                ipfs: ipfs,
                content: content,
                imgUrl: imgUrl,
                royalty: royalty
            )
        }

    }

    //make it possible for a user that wants to be an admin to create the client
    pub fun createAdminClient(): @Administrator {
        return <- create Administrator()
    }


	init() {
        // Initialize the total supply
        self.totalSupply = 0
        //TODO: REMOVE SUFFIX BEFORE RELEASE
        self.CollectionPublicPath=/public/WebshotCollection001
        self.CollectionStoragePath=/storage/WebshotCollection001
        self.AdministratorPublicPath= /public/WebshotAdminClient001
        self.AdministratorStoragePath=/storage/WebshotAdminClient001
        self.MinterStoragePath=/storage/WebshotAdmin001
        self.MinterPrivatePath=/private/WebshotAdmin001

        self.account.save(<- create Minter(), to: self.MinterStoragePath)
        self.account.link<&Minter>(self.MinterPrivatePath, target: self.MinterStoragePath)

        emit ContractInitialized()
	}
}

