var BlocksDBLib = artifacts.require("BlocksDBLib");

module.exports = async function(deployer, network, accounts) {
  deployer.deploy(BlocksDBLib);
};
