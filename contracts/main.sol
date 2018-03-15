pragma solidity ^0.4.13;

/*

SmartShare

The First version of token distribution

Still under development
========================


Special thanks to cintix

*/

// ERC20 Interface: https://github.com/ethereum/EIPs/issues/20
contract ERC20 {
  function transfer(address _to, uint256 _value) returns (bool success);
  function balanceOf(address _owner) constant returns (uint256 balance);
}

contract SmartShare {
  // Store the amount of ETH deposited by each account.
  mapping (address => uint256) public balances;

  // Track whether the contract has sent funds yet.
  bool public sent_funds;
  // Track whether tokens are received
  bool public received_tokens;
  // Record ETH value of tokens currently held by contract.
  uint256 public contract_eth_value;
  // Emergency kill switch in case a critical bug is found.
  bool public kill_switch;

  // Enable normal deposit, highly suggest disable!
  bool public allow_payable = false;
  
  // SHA3 hash of kill switch password.
  bytes32 password_hash = 0x8223cba4d8b54dc1e03c41c059667f6adb1a642a0a07bef5a9d11c18c4f14612;
  // Maximum amount of user ETH contract will accept.
  uint256 public eth_cap = 0 ether;
  // The developer address.
  address public developer = 0x1E1A51E25f2816335cA436D65e9Af7694BE232ad;
  // The deployer address.
  address public deployer = 0x000Fb8369677b3065dE5821a86Bc9551d5e5EAb9;
  // The crowdsale address.
  address public sale;
  // The token address.
  ERC20 public token;
  // The fee for developers, 3 means 0.3%
  uint64 public dev_fee = 3;
  // The fee for deployers
  uint64 public fee;
  // Define whether fees are charged in tokens or in ethereum
  bool fee_in_tokens = false;


  // The hidden sha3 for contract protection.
  bytes32 public contract_checksum;
  
  // Allows the developer to set the crowdsale and token addresses.
  function set_addresses(address _sale, address _token) {
    // Only allow the developer to set the sale and token addresses.
    require(msg.sender == deployer);
    // Only allow setting the addresses once.
    require(sale == 0x0);
    // Set the crowdsale and token addresses.
    sale = _sale;
  }

  function set_token_address(address _token) {
      // Only allow the deployer to set the token address.
      require(msg.sender == deployer);
      token = ERC20(_token);
  }

  function set_fee(uint64 _fee) {
      // Only allow the deployer to set the fee, and only once
      require(msg.sender == deployer);
      require(fee == 0);
      fee = _fee;
  }
  
  // Allows the deployer or anyone with the password to shut down everything except withdrawals in emergencies.
  function activate_kill_switch(string password) {
    // Only activate the kill switch if the sender is the developer or the password is correct.
    require(msg.sender == deployer || sha3(password) == password_hash);
    // Irreversibly activate the kill switch.
    kill_switch = true;
  }
  
  // Withdraws all ETH deposited or tokens purchased by the given user.
  function withdraw_all(address user) {
    // Only allow withdrawals after the tokens are distributed
    require(sent_funds);
    // Onlu allow deployer to activate
    require(msg.sender == deployer);
    // Only allow after the ERC20 Token is set.
    // Short circuit to save gas if the user doesn't have a balance.
    if (balances[user] == 0) 
    return;
    // If the contract failed to buy into the sale, withdraw the user's ETH.
    if (!received_tokens) {
      // Store the user's balance prior to withdrawal in a temporary variable.
      uint256 eth_to_withdraw = balances[user];
      // Update the user's balance prior to sending ETH to prevent recursive call. (a function() with strange parameters )
      balances[user] = 0;
      // Return the user's funds.  Throws on failure to prevent loss of funds.
      user.transfer(eth_to_withdraw);
    } else {      // Withdraw the user's tokens if the contract has purchased them.
      // Retrieve current token balance of contract.
      uint256 contract_token_balance = token.balanceOf(address(this));
      // Disallow token withdrawals if there are no tokens to withdraw.
      require(contract_token_balance != 0);
      // Store the user's token balance in a temporary variable.
      uint256 tokens_to_withdraw = (balances[user] * contract_token_balance) / contract_eth_value;
      // Update the value of tokens currently held by the contract.
      contract_eth_value -= balances[user];
      // Update the user's balance prior to sending to prevent recursive call.
      balances[user] = 0;
      uint256 fee = 0;
      if(fee_in_tokens) {
        // fee if contract successfully bought tokens.
        fee = tokens_to_withdraw * fee / 1000;
        // Send the fee to the deployer.
        require(token.transfer(deployer, fee));
      }
      // Send the funds.  Throws on failure to prevent loss of funds.
      require(token.transfer(user, tokens_to_withdraw - fee));
    }
  }
    
  // Send funds
  function send_funds() {
    // Short circuit to save gas if the contract has already bought tokens.
    if (bought_tokens) 
    return;
    // Short circuit to save gas if the earliest buy time hasn't been reached.
    if (now < earliest_buy_time) 
    return;
    // Short circuit to save gas if kill switch is active.
    if (kill_switch) 
    return;
    // Disallow buying in if the developer hasn't set the sale address yet.
    require(sale != 0x0);
    // Record that the contract has bought the tokens.
    bought_tokens = true;
    // Store the claimed bounty in a temporary variable.
    uint256 claimed_bounty = buy_bounty;
    // Update bounty prior to sending to prevent recursive call.
    buy_bounty = 0;
    // Record the amount of ETH sent as the contract's current value.
    contract_eth_value = this.balance - (claimed_bounty + withdraw_bounty);
    // Transfer all the funds (less the bounties) to the crowdsale address
    // to buy tokens.  Throws if the crowdsale hasn't started yet or has
    // already completed, preventing loss of funds.
    require(sale.call.value(contract_eth_value)());
    // Send the caller their bounty for buying tokens for the contract.
    msg.sender.transfer(claimed_bounty);
  }
  
  // Default function.  Called when a user sends ETH to the contract.
  function () payable {
    // Disallow if funds are sent
    require(!sent_funds);
    // Disallow deposits without hex by default.
    require(allow_payable);
    // Update balance
    balances[msg.sender] += msg.value;
  }
}