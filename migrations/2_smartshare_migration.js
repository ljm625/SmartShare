var SmartShare = artifacts.require("SmartShare");
var Tokens = artifacts.require("FucksToken")
module.exports = function(deployer) {
    deployer.deploy(SmartShare);
    deployer.deploy(Tokens);
  };
  