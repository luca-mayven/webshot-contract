import Webshot from "../../contracts/Webshot.cdc"

// This scripts returns the number of Webshots currently in existence.

pub fun main(): UInt64 {    
    return Webshot.totalSupply
}
