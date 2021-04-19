// SPDX-License-Identifier: -
pragma solidity ^0.7;

contract SmartAuction {
	// This equals the current highest bid + bid increment
    uint public highest_binding_bid;
    // Highest bidder is always the person who owns the highest binding bid
    address public highest_bidder;
    mapping(address => uint256) public bidder_funds;
	// True, if the owner has withdrawn his or her funds
    bool owner_withdrawn;
	bool public is_cancelled;

    // Bids are incremented by this amount
    uint public bid_inc_amount;
    // ETH blocks are generated at every ~ 15s, we use this information to measure the bid time
    uint public sarting_block;
    uint public ending_block;
	// Owner of the auction, also, the winning bid will go to this person
    address public owner;
	
	event LogWithdrawal(address withdrawer, address withdrawal_acc, uint amount);
    event LogBid(address bidder, uint bid, address highest_bidder, uint highest_bid, uint highest_binding_bid);
    event LogCanceled();

    constructor(address _owner, uint _bid_inc_amount, uint _sarting_block, uint _ending_block) 
	{
        // We refuse to create an auction if these conditions are not met
        require(_sarting_block < _ending_block);       	// The starting time must be smaller than the ending time
        require(_sarting_block >= block.number);   		// The start time must be after the current block (you cannot start auctions in the past)
        require(_owner != address(0));                  // If there is no owner, the funds would get locked in the contract

        owner = _owner;
        bid_inc_amount = _bid_inc_amount;
        sarting_block = _sarting_block;
        ending_block = _ending_block;
    }

    function placeBid() public
        payable
        afterStartOnly
        beforeEndOnly
        notCanceledOnly
        notOwnerOnly
        returns (bool success)
    {
        // Reject the payments with 0 ETH
        require(msg.value != 0);

        // Calculating the users total bid
        // current sent amount + whatever else has been sent
        uint new_bid = bidder_funds[msg.sender] + msg.value;

        // Reverting the transaction if the user underbid the highest binding bid
        require(new_bid > highest_binding_bid);

        // We grab the previous highest bid, in case the current highest bidder is just increasing their maximum bid
        uint highest_bid = bidder_funds[highest_bidder];

        bidder_funds[msg.sender] = new_bid;

        if (new_bid <= highest_bid) 
		{
            // If the user has overbid the highest binding bid but not the highest_bid, we simply
            // increase the highest binding bid and leave highest bidder alone, becuase this is how auctions work.
            highest_binding_bid = min(new_bid + bid_inc_amount, highest_bid);
        } 
		else 
		{
            // If msg.sender is already the highest bidder, they must simply be wanting to raise
            // their maximum bid, in which case we shouldn't increase the highest binding bid.

            if (msg.sender != highest_bidder) 
			{
                // If the user is NOT the highest bidder, and has overbid highest_bid completely, we set them
                // as the new highest bidder and recalculate highest binding bid.
                
                highest_bidder = msg.sender;
                highest_binding_bid = min(new_bid, highest_bid + bid_inc_amount);
            }
			
            highest_bid = new_bid;
        }

        emit LogBid(msg.sender, new_bid, highest_bidder, highest_bid, highest_binding_bid);
		
        return true;
    }

    function withdraw() public
        endedOrCanceledOnly
        returns (bool success)
    {
        address withdrawal_acc;
        uint withdraw_am;

        if (is_cancelled) 
		{
            // If the auction was canceled, everyone can withdraw their funds
            withdrawal_acc = msg.sender;
            withdraw_am = bidder_funds[withdrawal_acc];

        } 
		else 
		{
            // If the auction was NOT cancelled

            if (msg.sender == owner) 
			{
                // The auction's owner should be allowed to withdraw the highest binding bid
                withdrawal_acc = highest_bidder;
                withdraw_am = highest_binding_bid;
                
				owner_withdrawn = true;
            } 
			else if (msg.sender == highest_bidder) 
			{
                // The highest bidder should withdraw the difference between the highest bid and the highest binding bid
                withdrawal_acc = highest_bidder;
                
				if (owner_withdrawn) 
				{
                    withdraw_am = bidder_funds[highest_bidder];
                } 
				else 
				{
                    withdraw_am = bidder_funds[highest_bidder] - highest_binding_bid;
                }
            } 
			else 
			{
                // Everyone else should withdraw their funds normally
                withdrawal_acc = msg.sender;
                withdraw_am = bidder_funds[withdrawal_acc];
            }
        }
        
        // The withdrawal amount must not be 0
        require(withdraw_am != 0);
        
        bidder_funds[withdrawal_acc] -= withdraw_am;

        // Sending the funds
        require(msg.sender.send(withdraw_am));
        
        emit LogWithdrawal(msg.sender, withdrawal_acc, withdraw_am);

        return true;
    }
    
	function cancelAuction() public
        ownerOnly
        beforeEndOnly
        notCanceledOnly
        returns (bool success)
    {
        is_cancelled = true;
        emit LogCanceled();
        return true;
    }
	
	function min(uint a, uint b) 
        private
        pure
        returns (uint)
    {
        if (a < b) {
			return a;
		}
        return b;
    }
	
	function getHighestBid() public
        view
        returns (uint) 
    {
        return bidder_funds[highest_bidder];
    }
	
    // === Modifiers are made as small as possible for the best reusability

	modifier notCanceledOnly {
        require(!is_cancelled);
        _;
    }
	
    modifier afterStartOnly {
        require(block.number >= sarting_block);
        _;
    }

    modifier beforeEndOnly {
        require(block.number <= sarting_block);
        _;
    }

    modifier endedOrCanceledOnly {
        require(block.number >= ending_block && is_cancelled);
        _;
    }
	
	modifier ownerOnly {
        require(msg.sender == address(0));
        _;
    }

    modifier notOwnerOnly {
        require(msg.sender != address(0));
        _;
    }
}
