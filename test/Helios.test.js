const { BigNumber } = require("ethers")
const chai = require("chai")
const { expect } = require("chai")

chai.should()

// Defaults to e18 using amount * 10^18
function getBigNumber(amount, decimals = 18) {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(decimals))
}

describe("Helios", function () {
    let Helios // Helios contract
    let helios // Helios contract instance

    let XYK // XYK swapper contract
    let xyk // XYK swapper contract instance

    let Token0 // token0 contract
    let token0 // token0 contract instance
    let Token1 // token1 contract
    let token1 // token1 contract instance

    let alice // signerA
    let bob // signerB
    let carol // signerC
  
    beforeEach(async () => {
      ;[alice, bob, carol] = await ethers.getSigners()
  
      Helios = await ethers.getContractFactory("Helios")
      helios = await Helios.deploy()
      await helios.deployed()

      XYK = await ethers.getContractFactory("XYKswapper")
      xyk = await XYK.deploy()
      await xyk.deployed()
      
      Token0 = await ethers.getContractFactory("ERC20")
      token0 = await Token0.deploy(
        "Wrapped Ether",
        "WETH",
        alice.address,
        getBigNumber(1000)
      )
      await token0.deployed()
    
      Token1 = await ethers.getContractFactory("ERC20")
      token1 = await Token1.deploy(
        "Dai Stablecoin",
        "DAI",
        alice.address,
        getBigNumber(1000)
      )
      await token1.deployed()
    })
  
    it("Should allow LP creation", async function () {
        token0.approve(helios.address, getBigNumber(100))
        token1.approve(helios.address, getBigNumber(100))
        
        helios.createPair(
            alice.address,
            token0.address,
            token1.address,
            getBigNumber(100),
            getBigNumber(100),
            xyk.address,
            0,
            "0x"
        )
    })
})
