var VerifierLib = artifacts.require("VerifierLib");
var BlocksDBLib = artifacts.require("BlocksDBLib");
var ADC = artifacts.require("ADC");

module.exports = async function(deployer, network, accounts) {
  deployer.link(VerifierLib, ADC);
  deployer.link(BlocksDBLib, ADC);
  deployer.deploy(ADC);
};
