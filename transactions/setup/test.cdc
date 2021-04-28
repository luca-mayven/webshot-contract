
//import FungibleToken from 0xee82856bf20e2aa6
import FungibleToken from "../../contracts/FungibleToken.cdc"
import FlowToken from "../../contracts/FlowToken.cdc"

//This transactions transfers flow on testnet from one account to another
transaction(
    from: Address,
    to: Address) {


      prepare(signer: AuthAccount) {

      }

      execute {
        let sender = getAccount(from)
        let recipient = getAccount(to)
      }
}