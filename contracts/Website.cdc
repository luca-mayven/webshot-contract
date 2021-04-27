
import NonFungibleToken from "./NonFungibleToken.cdc"
import FungibleToken from "./FungibleToken.cdc"
//import FungibleToken from 0x9a0766d93b6608b7
//import FUSD from 0xe223d8a629e49c68

/*

 The contract that defines the Website NFT and a Collection to manage them

 This contract based on the following git repo

 - The Versus Auction contract created by Bjartek and Alchemist
 https://github.com/versus-flow/auction-flow-contract


 Each Website defines the name, URL, drop frequency, minting number for all the webshots created from it

 */


pub contract Website: NonFungibleToken {

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
    pub event Minted(id: UInt64, name: String, url: String)

    pub resource interface Public {
        pub let id: UInt64
        pub let name: String
        pub let url: String
        pub let ownerName: String
        pub let ownerAddress: Address
        pub let description: String
        pub let webshotMinInterval: UInt64
        pub let isRecurring: Bool
        access(contract) var totalMinted: UInt64
    }

    pub resource NFT: NonFungibleToken.INFT, Public {
        pub let id: UInt64
        pub let name: String
        pub let url: String
        pub let ownerName: String
        pub let ownerAddress: Address
        pub let description: String
        pub let webshotMinInterval: UInt64
        pub let isRecurring: Bool
        access(contract) var totalMinted: UInt64

        init(
            id: UInt64,
            name: String,
            url: String,
            ownerName: String,
            ownerAddress: Address,
            description: String,
            webshotMinInterval: UInt64,
            isRecurring: Bool
                    ) {

            self.id = id
            self.totalMinted = 0
            self.name = name
            self.url = url
            self.ownerName = ownerName
            self.ownerAddress = ownerAddress
            self.description = description
            self.webshotMinInterval = webshotMinInterval
            self.isRecurring = isRecurring
        }
    }








    //Standard NFT CollectionPublic interface that can also borrowWebsite as the correct type
    pub resource interface CollectionPublic {
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowWebsite(id: UInt64): &{Website.Public}?
    }

    pub resource Collection: CollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
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
            let token <- token as! @Website.NFT

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

        // borrowWebsite returns a borrowed reference to a Website
        // so that the caller can read data and call methods from it.
        //
        // Parameters: id: The ID of the NFT to get the reference for
        //
        // Returns: A reference to the NFT
        pub fun borrowWebsite(id: UInt64): &{Website.Public}? {
            if self.ownedNFTs[id] != nil {
                let ref = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT
                return ref as! &Website.NFT
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
    pub fun getWebsiteIDs(address:Address) : [UInt64] {

        let account=getAccount(address)

        let websiteCollection = account.getCapability(self.CollectionPublicPath)!.borrow<&Website.Collection{Website.CollectionPublic}>() ?? panic("Couldn't get collection")

        return websiteCollection.getIDs();
    }

    pub resource Minter {


        pub fun mintNFT(
            name: String,
            url: String,
            ownerName: String,
            ownerAddress: Address,
            description: String,
            webshotMinInterval: UInt64,
            isRecurring: Bool) : @Website.NFT {

            var newNFT <- create NFT(
                id: Website.totalSupply,
                name: name,
                url: url,
                ownerName: ownerName,
                ownerAddress: ownerAddress,
                description: description,
                webshotMinInterval: webshotMinInterval,
                isRecurring: isRecurring
            )

            emit Minted(id: Website.totalSupply, name: newNFT.name, url: newNFT.url)

            Website.totalSupply = Website.totalSupply + UInt64(1)
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
                cap.check() : "Invalid server capability"
                self.server == nil : "Server already set"
            }
            self.server = cap
        }

        pub fun mintNFT(
            name: String,
            url: String,
            ownerName: String,
            ownerAddress: Address,
            description: String,
            webshotMinInterval: UInt64,
            isRecurring: Bool) : @Website.NFT {

            pre {
                self.server != nil:
                    "Cannot create art if server is not set"
            }
            return <- self.server!.borrow()!.mintNFT(
                name: name,
                url: url,
                ownerName: ownerName,
                ownerAddress: ownerAddress,
                description: description,
                webshotMinInterval: webshotMinInterval,
                isRecurring: isRecurring
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
        self.CollectionPublicPath=/public/WebsiteCollection001
        self.CollectionStoragePath=/storage/WebsiteCollection001
        self.AdministratorPublicPath= /public/WebsiteAdminClient001
        self.AdministratorStoragePath=/storage/WebsiteAdminClient001
        self.MinterStoragePath=/storage/WebsiteAdmin001
        self.MinterPrivatePath=/private/WebsiteAdmin001

        self.account.save(<- create Minter(), to: self.MinterStoragePath)
        self.account.link<&Minter>(self.MinterPrivatePath, target: self.MinterStoragePath)

        emit ContractInitialized()
	}
}

