// This script checks that the accounts are set up correctly for the marketplace tutorial.
//

//testnet
//import FungibleToken from 0x9a0766d93b6608b7
//import NonFungibleToken from 0x631e88ae7f1d7c20
//import Webshot from 0x0000

//emulator
import FungibleToken from 0xee82856bf20e2aa6
import NonFungibleToken, Content, Webshot, WebshotMarket from 0x0000

pub struct AddressStatus {

  pub(set) var address:Address
  pub(set) var balance: UFix64
  pub(set) var webshotIDs: [UInt64]
  init (_ address:Address) {
    self.address=address
    self.balance= 0.0
    self.webshotIDs= []
  }
}

/*
  This script will check an address and print out its FT, NFT and Versus resources
 */
pub fun main(address:Address) : AddressStatus {
    // get the accounts' public address objects
    let account = getAccount(address)
    let status= AddressStatus(address)
    
    if let vault= account.getCapability(/public/flowTokenBalance).borrow<&{FungibleToken.Balance}>() {
       status.balance=vault.balance
    }

    status.webshotIDs= Webshot.getWebshotIDs(address: address)
    
    return status

}
