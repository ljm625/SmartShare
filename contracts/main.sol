pragma solidity ^0.4.13;

/*

SmartShare

The First version of token distribution

Still under development
========================

Current feature list:

1. Fund Raising
2. Token Distribution
3. Fee Raising
4. Fee paid by tokens
5. Whitelist

TODO:

The implementation of the multiple times token distribution

For example:

1. 100 Tokens
50 User1 50 User2
then 100 more tokens
it should be 50 User1 and 50 User2

Need further testing before proceeding.

Individual Cap


Special thanks to cintix

*/

// ERC20 Interface: https://github.com/ethereum/EIPs/issues/20
contract ERC20 {
  function transfer(address _to, uint256 _value) returns (bool success);
  function balanceOf(address _owner) constant returns (uint256 balance);
}



/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    if (a == 0) {
      return 0;
    }
    c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return a / b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = a + b;
    assert(c >= a);
    return c;
  }
}



contract SmartShare {
  // Store the amount of ETH deposited by each account.
  mapping (address => uint256) public balances;

  mapping (address => uint256) public withdrawn_tokens;
  using SafeMath for uint256;
  // Store the withdrawn token balance
  uint256 withdrawn_token_balances;


  // Track whether the contract has sent funds yet.
  bool public sent_funds;
  // Record ETH value of tokens currently held by contract.
  uint256 public contract_eth_value;
  // Emergency kill switch in case a critical bug is found.
  bool public kill_switch;

  // Enable normal deposit, highly suggest disable!
  bool public allow_payable = false;
    // Maximum amount of user ETH contract will accept.
  uint256 public eth_cap = 0 ether;
  // The developer address.
  address public developer = 0x627306090abaB3A6e1400e9345bC60c78a8BEf57;
  // The deployer address.
  address public deployer = 0x627306090abaB3A6e1400e9345bC60c78a8BEf57;
  // The crowdsale address.
  address public sale;
  // The token address.
  ERC20 public token;
  // The fee for developers, 3 means 0.3%
  uint64 public dev_fee = 3;
  // The fee for deployers
  uint64 public fee;
  // Define whether fees are charged in tokens or in ethereum
  bool public fee_in_tokens = false;

  // Define whether whitelist is enabled
  bool public whitelist_enabled = false;
  // Define the max and min cap for each user.
  uint256 public ind_max_cap;
  uint256 public ind_min_cap;
  // Define the whitelist address that are allowed to participate
  mapping (address => bool) public whitelist;

  // The hidden sha3 for contract protection.
  bytes32 public contract_checksum;

  // Events for web3.js & Debugging
  event DepositEther(address _from, uint256 _value);
  event WithdrawEther(address _from, uint256 _value);
  event SetDestAddress(address _from, address _dest_addr);
  event SetTokenAddress(address _from, address _token_addr);
  event FundsSent(address _dest, uint256 _amount);
  
  
  // Allows the developer to set the crowdsale addresses.
  function set_addresses(address _sale) public {
    // Only allow the developer to set the sale and token addresses.
    require(msg.sender == deployer);
    // Only allow setting the addresses once.
    require(sale == 0x0);
    // Set the crowdsale and token addresses.
    sale = _sale;
    SetDestAddress(msg.sender, _sale);
  }

  function set_token_address(address _token) public {
      // Only allow the deployer to set the token address.
      require(msg.sender == deployer);
      token = ERC20(_token);
      SetTokenAddress(msg.sender, _token);
  }

  function set_fee(uint64 _fee) public {
      // Only allow the deployer to set the fee, and only once
      require(msg.sender == deployer);
      require(fee == 0);
      fee = _fee;
  }

  function set_min_max_cap(uint64 _min_cap, uint64 _max_cap) public {
    // Only allow the deployer to change the min and max cap
    require(msg.sender == deployer);
    ind_min_cap = _min_cap;
    ind_max_cap = _max_cap;
  }
  
  // Allows the deployer or anyone with the password to shut down everything except withdrawals in emergencies.
  function activate_kill_switch(string password) public {
    // Only activate the kill switch if the sender is the developer or the password is correct.
    require(msg.sender == deployer);
    // Irreversibly activate the kill switch.
    kill_switch = true;
  }

  // Set the cap for the token sale
  function set_token_cap(uint256 _cap) public {
    // Only allow developers to set fees
    require(msg.sender == deployer);
    eth_cap = _cap;

  }
  
  // The token withdraw mechanizm



  // Withdraws all ETH deposited or tokens purchased by the given user.
  function withdraw_all(address user) public {
    // Onlu allow deployer to activate
    require(msg.sender == deployer);
    // Only allow after the ERC20 Token is set.
    // Short circuit to save gas if the user doesn't have a balance.
    if (balances[user] == 0) 
    return;
    // If the contract failed to buy into the sale, withdraw the user's ETH.
    if (!sent_funds) {
      // Store the user's balance prior to withdrawal in a temporary variable.
      uint256 eth_to_withdraw = balances[user];
      // Update the user's balance prior to sending ETH to prevent recursive call. (a function() with strange parameters )
      balances[user] = 0;
      // Return the user's funds.  Throws on failure to prevent loss of funds.
      user.transfer(eth_to_withdraw);
      contract_eth_value = contract_eth_value.sub(eth_to_withdraw);
    } else {      // Withdraw the user's tokens if the contract has purchased them.
      // Retrieve current token balance of contract.
      uint256 contract_token_balance = token.balanceOf(address(this));
      // Disallow token withdrawals if there are no tokens to withdraw.
      require(contract_token_balance != 0);
      // Store the user's token balance in a temporary variable.
      uint256 tokens_per_contribution = contract_token_balance.add(withdrawn_token_balances).mul(balances[user]).div(contract_eth_value);
      uint256 tokens_to_withdraw = tokens_per_contribution.sub(withdrawn_tokens[user]);
      // Update the value of tokens currently held by the contract.
      // contract_eth_value -= balances[user];
      // Update the user's balance prior to sending to prevent recursive call.
      balances[user] = 0;
      uint256 fee_token = 0;
      if(fee_in_tokens) {
        // fee if contract successfully bought tokens.
        fee_token = tokens_to_withdraw.mul(fee).div(1000);
        // Send the fee to the deployer.
        require(token.transfer(deployer, fee_token));
      }
      // Send the funds.  Throws on failure to prevent loss of funds.
      require(token.transfer(user, tokens_to_withdraw.sub(fee_token)));
      // TOKENS ARE NOT DEDUCTED YET

    }
  }


    
  // Send funds
  function send_funds() public {
    // Short circuit to save gas if the contract has already bought tokens.
    require(!sent_funds);
    // Short circuit to save gas if kill switch is active.
    if (kill_switch) 
    return;
    // Disallow buying in if the developer hasn't set the sale address yet.
    require(sale != 0x0);
    // Record that the contract has bought the tokens.
    sent_funds = true;
    // Update bounty prior to sending to prevent recursive call.
    uint256 dev_fee_eth = this.balance.mul(dev_fee).div(1000);
    uint256 fee_eth = 0;
    if (!fee_in_tokens) {
      fee_eth = this.balance.mul(dev_fee).div(1000);
    }
    // Record the amount of ETH sent as the contract's current value.
    contract_eth_value = this.balance - fee_eth - dev_fee_eth;
    // Transfer all the funds (less the bounties) to the crowdsale address
    // to buy tokens.  Throws if the crowdsale hasn't started yet or has
    // already completed, preventing loss of funds.
    require(sale.call.value(contract_eth_value)());
    if ( fee_eth != 0 ) {
      deployer.transfer(fee_eth);
    }
    developer.transfer(dev_fee_eth);
    FundsSent(sale,contract_eth_value);
  }

  function withdraw_eth (uint256 value) public {
    // Withdraw on user's request
    // Withdraw will only work before funds are sent
    require(!sent_funds);
    // Require user withdraw less than request
    require(balances[msg.sender]>=value);
    // Update balance before sending to prevent recursive call
    balances[msg.sender] = balances[msg.sender] - value;
    contract_eth_value = contract_eth_value.sub(value);
    // Send value back to user
    msg.sender.transfer(value);
    WithdrawEther(msg.sender, value);
  }
  
 // Whitelist related features

   function trigger_whitelist(bool _whitelist) public {
    require(msg.sender == deployer);
    whitelist_enabled = _whitelist;
  }

  // Add address to Whitelist

  function add_whitelist(address[] _address) public {
    require(msg.sender == deployer);
    for (uint64 i = 0 ; i < _address.length ; i++) {
      whitelist[_address[i]] = true;
    }
  }

  // Deposit related functions
  // Default function.  Called when a user sends ETH to the contract.
  function () payable public {
    // Disallow if funds are sent
    require(!sent_funds);
    // Disallow deposits without hex by default.
    require(allow_payable);
    // Update balance
    if(ind_max_cap != 0) {
     require(balances[msg.sender]+msg.value <= ind_max_cap); 
    }
    require(balances[msg.sender]+msg.value >= ind_min_cap);
    require(eth_cap>=(contract_eth_value+msg.value));
    balances[msg.sender] += msg.value;
    contract_eth_value = contract_eth_value.add(msg.value);
    DepositEther(msg.sender, msg.value);
  }

  // deposit function.  Called when a user sends ETH to the contract.
  function deposit() public payable {
    // Disallow if funds are sent
    require(!sent_funds);
    // Update balance
    if(ind_max_cap != 0) {
     require(balances[msg.sender]+msg.value <= ind_max_cap); 
    }
    require(balances[msg.sender]+msg.value >= ind_min_cap);
    require(eth_cap>=(contract_eth_value+msg.value));
    balances[msg.sender] += msg.value;
    contract_eth_value = contract_eth_value.add(msg.value);
    DepositEther(msg.sender, msg.value);
  }

}