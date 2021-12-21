// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Celoscrow {
    enum State { AWAITING_DELIVERABLE, AWAITING_APPROVAL, DISPUTE, COMPLETE, CANCEL }
    enum Asset { CELO, CUSD }

    struct Escrow {
        address payable contractor;

        // Cid of documentations
        string requirements;    // Ensure immutability to agreement, so contractors aren't cheated on  
        string deliverables;

        // status for approval of stakeholders
        bool clientApproval;
        bool contractorApproval;

        // Locked up funds
        Asset currency;     // Asset type: CELO, cUSD
        uint256 funds;      // in wei
        uint256 fees;       // Fees for Celoscrow

        State escrowState;      // Status for escrow transaction
        uint256 settlementTime; // epoch time
    }

    address public client;
    address payable celoscrowAddr; // Fees goes here
    IERC20 cUSDToken = IERC20(0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1);  // CUSD stablecoin

    uint256 public nEscrow; 
    mapping (uint256 => Escrow) public escrows; // List of escrows that client has

    constructor() {
        client = msg.sender;
        nEscrow = 0;    // Starts with 0;
        celoscrowAddr = payable(0x7dbC9C5d22ea26DcA7D9F5fA1c321Bc6A6ccd2FE);
    }

    function create(       
        address payable contractor,
        string memory requirementsCid,
        uint256 value,
        uint256 settlementTime
    ) onlyClient public payable {
        require(contractor != client, "Can't make escrow arrangement with yourself");
        
        nEscrow = nEscrow + 1;  // Create new escrow;

        Escrow memory newEscrow;
        newEscrow.contractor = contractor;
        newEscrow.requirements = requirementsCid;
        newEscrow.clientApproval = false;
        newEscrow.contractorApproval = false;

        // Handling Funds and Fees
        if(msg.value > 0) { // Using CELO Asset
            newEscrow.currency = Asset.CELO;
            newEscrow.fees = msg.value / 400;               // service fee of 0.25%
            newEscrow.funds = msg.value - newEscrow.fees;   // Lock up funds, Not sure how to implement
        } else { // Using cUSD Stablecoin
            newEscrow.currency = Asset.CUSD;
            newEscrow.fees = value / 400;               // service fee of 0.25%
            newEscrow.funds = value - newEscrow.fees;   // Lock up funds, Not sure how to implement

            // Front end should have allowance and approve _value via Web3  
            uint256 cUSDbalance = cUSDToken.balanceOf(msg.sender);
            require(value <= cUSDbalance, "Insufficient funds");
            cUSDToken.transferFrom(msg.sender, address(this), value);  // Lock up cUSD to this SC addr
        }

        newEscrow.settlementTime = settlementTime;
        newEscrow.escrowState = State.AWAITING_DELIVERABLE;
        escrows[nEscrow] = newEscrow;
    }

    function setRequirements(uint256 id, string memory cid) onlyClient public returns (bool) {
        require(escrows[id].contractor != address(0), "Escrow: Invalid Escrow");
        escrows[id].requirements = cid;
        return true;
    }

    function setDeliverables(uint256 id, string memory cid) 
    onlyContractor(id) 
    escrowStateCheck(id, State.AWAITING_DELIVERABLE) 
    public returns (bool) {
        escrows[id].deliverables = cid;
        escrows[id].contractorApproval = true; // Siging that contract approves
        // Emit event (oracle to web3 that signals contractor) Not sure how to implement
        escrows[id].escrowState = State.AWAITING_APPROVAL;

        return true;
    }

    function approve(uint256 id) 
    onlyStakeholder(id) 
    escrowStateCheck(id, State.AWAITING_APPROVAL) 
    public returns(bool) { 
        if (msg.sender == escrows[id].contractor){
            escrows[id].contractorApproval = true;
        } else if (msg.sender == client){
            escrows[id].clientApproval = true;
        }
        return true;
    }

    function disapproval(uint256 id)
    onlyStakeholder(id) 
    escrowStateCheck(id, State.AWAITING_APPROVAL) 
    public returns(bool) { 
        if (msg.sender == escrows[id].contractor){
            escrows[id].contractorApproval = false;
        } else if (msg.sender == client){
            escrows[id].clientApproval = false;
        }
        return true;
    }

    function cancel(uint id) onlyClient public {
        if(escrows[id].currency == Asset.CELO) {
            payable(client).transfer(escrows[id].funds);    // Refund locked funds
            celoscrowAddr.transfer(escrows[id].fees);       // Transfer fees to Celoscrow Wallet
        } else if(escrows[id].currency == Asset.CUSD) {
            cUSDToken.allowance(address(this), payable(client));
            cUSDToken.allowance(address(this), celoscrowAddr);
            cUSDToken.transfer(payable(client), escrows[id].funds);
            cUSDToken.transfer(celoscrowAddr, escrows[id].fees);
        }

        // Reset funds
        escrows[id].funds = 0;     
        escrows[id].funds = 0;   
        escrows[id].escrowState = State.CANCEL;   
    }

    function releaseFunds(uint256 id) onlyClient escrowStateCheck(id, State.AWAITING_APPROVAL) public {
        if(escrows[id].clientApproval && escrows[id].contractorApproval) { // 100% Approval
            if(escrows[id].currency == Asset.CELO) {
                escrows[id].contractor.transfer(escrows[id].funds); // Release funds to contractor
                celoscrowAddr.transfer(escrows[id].fees); // Transfer fees to Celoscrow Wallet
            } else if(escrows[id].currency == Asset.CUSD) {
                cUSDToken.allowance(address(this), escrows[id].contractor);
                cUSDToken.allowance(address(this), celoscrowAddr);
                cUSDToken.transfer(escrows[id].contractor, escrows[id].funds);
                cUSDToken.transfer(celoscrowAddr, escrows[id].fees);
            }

            escrows[id].funds = 0;
            escrows[id].fees = 0;
            escrows[id].escrowState = State.COMPLETE;
        }
    }

    modifier onlyClient() {
        require(msg.sender == client, "Only client can call this method");
        _;
    }
  
    modifier onlyContractor(uint256 id) {
        require(escrows[id].contractor == msg.sender, "Only contractor can call this method");
        _;
    }

    modifier onlyStakeholder(uint256 id) {
        require(
            escrows[id].contractor == msg.sender || client == msg.sender,
            "Only contractor can call this method"
        );
        _;
    }

    modifier escrowStateCheck(uint id, State _state) {
        require(escrows[id].escrowState == _state, "Wrong state.");
        _;
    }


    // Stablecoin checking
    function cUSDBalanceOf(address addr) public view returns (uint256) {
        return cUSDToken.balanceOf(addr);
    }
}