var VerifierLib = artifacts.require("VerifierLib");

module.exports = async function(deployer, network, accounts) {
  deployer.deploy(VerifierLib);
};
