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
  address public developer = 0x000Fb8369677b3065dE5821a86Bc9551d5e5EAb9;
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
  
  // Withdraws all ETH deposited or tokens purchased by the given user and rewards the caller.
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
    if (!bought_tokens) {
      // Store the user's balance prior to withdrawal in a temporary variable.
      uint256 eth_to_withdraw = balances[user];
      // Update the user's balance prior to sending ETH to prevent recursive call.
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
      // 1% fee if contract successfully bought tokens.
      uint256 fee = tokens_to_withdraw / 100;
      // Send the fee to the developer.
      require(token.transfer(developer, fee));
      // Send the funds.  Throws on failure to prevent loss of funds.
      require(token.transfer(user, tokens_to_withdraw - fee));
    }
    // Each withdraw call earns 1% of the current withdraw bounty.
    uint256 claimed_bounty = withdraw_bounty / 100;
    // Update the withdraw bounty prior to sending to prevent recursive call.
    withdraw_bounty -= claimed_bounty;
    // Send the caller their bounty for withdrawing on the user's behalf.
    msg.sender.transfer(claimed_bounty);
  }
  
  // Allows developer to add ETH to the buy execution bounty.
  function add_to_buy_bounty() payable {
    // Only allow the developer to contribute to the buy execution bounty.
    require(msg.sender == developer);
    // Update bounty to include received amount.
    buy_bounty += msg.value;
  }
  
  // Allows developer to add ETH to the withdraw execution bounty.
  function add_to_withdraw_bounty() payable {
    // Only allow the developer to contribute to the buy execution bounty.
    require(msg.sender == developer);
    // Update bounty to include received amount.
    withdraw_bounty += msg.value;
  }
  
  // Buys tokens in the crowdsale and rewards the caller, callable by anyone.
  function claim_bounty() {
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