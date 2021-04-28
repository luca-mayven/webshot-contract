
//import FungibleToken from 0xee82856bf20e2aa6
import FungibleToken from "../contracts/FungibleToken.cdc"
import NonFungibleToken from "../contracts/NonFungibleToken.cdc"
import Website from "../contracts/Website.cdc"
import Webshot from "../contracts/Webshot.cdc"
import Marketplace from "../contracts/Marketplace.cdc"
import Drop from "../contracts/Drop.cdc"

pub struct AddressStatus {

  pub(set) var address:Address
  pub(set) var balance: UFix64
  pub(set) var webshotData: [Webshot.WebshotData]
  pub(set) var websiteData: [Website.WebsiteData]
  pub(set) var saleData: [Marketplace.SaleData]
  init (_ address:Address) {
    self.address=address
    self.balance= 0.0
    self.webshotData= []
    self.websiteData= []
    self.saleData = []
  }
}

// This script checks that the accounts are set up correctly for the marketplace tutorial.

pub fun main(address:Address) : AddressStatus {
    // get the accounts' public address objects
    let account = getAccount(address)
    let status = AddressStatus(address)
    
    if let vault = account.getCapability(/public/flowTokenBalance).borrow<&{FungibleToken.Balance}>() {
       status.balance = vault.balance
    }

    status.webshotData = Webshot.getWebshot(address: address)
    status.websiteData = Website.getWebsite(address: address)
    status.saleData = Marketplace.getSale(address: address)
    
    return status

}
