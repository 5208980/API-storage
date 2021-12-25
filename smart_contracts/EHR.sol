//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/*
    There will be a factory contract that legimatises these patient contract by storing contract addr on that contract
    Any contract deployed not using the factory contract will have a high chance of fraud.
    To provide for the patient centric, a patient will be in charge of the creation of there medical record.
    Once created can't be destory (Maybe refine)


    STEPS: 
    - Visit GP, Admin to a hospital, setup Health insurance 
    - If first time ever, create a EHR contract.
    - Owners can add these providers to there EHR contract, for viewing and writing.
    - They do there real Processed
        - If they need to view medical history, provider can use viewData
        - New record needs to be add can be done through, ensuring that the provider in reality check they are valid and correct.
    - DONE
    
    - If they move providers, or they don't trust the provider anymore.
    - They can remove that provider. 
    
    
    WEB3 (frontend)
    - connected to IPFS, or Filecoin
    - Users can log in using MetaMask FOR NOW.
    - Patients can view there information once logged in.
    - If not they can create a EHR contract for themselves.
    - Import (Too far for prototype but might want to consider)
*/

contract EHR {
    address owner;  // Might wanna turn into struct

    struct medicalRecord {
        string cid;        // cid of IPFS that contains information to record     
        address medicalProfession;  // Adminstrated health provider that made this record 
        uint256 time;   // timestamp at which this record was created
    }

    enum Permissions{ NONE, VIEW, WRITE, BOTH }
    struct medicalProfessionInfo {
        bool exist;
        Permissions permission;
        uint index;
    }

    uint256 nMedicalProfessions;
    address[] public medicalProfessionsLUT;
    mapping (address => medicalProfessionInfo) public medicalProfessions; 
    uint256 public nRecords; // Decide not to go with address => medicalRecord for query purposes
    mapping (uint256 => medicalRecord) private medicalRecords;   

    event auditLog(uint256 timestamp);  // Logs off all accesses on EHR   

    constructor() {
        nRecords = 0;
        owner = msg.sender;
    }

    function grantAccess(address addr, uint p) isOwner validPermission(p) public returns (bool) {
        bool ret = true;
        if (medicalProfessions[addr].exist) {  // Update permission
            medicalProfessions[addr].permission = Permissions(p);  
        } else { // Add new entry 
            medicalProfessionsLUT.push(addr);
            nMedicalProfessions++;
            medicalProfessionInfo memory info;
            info.exist = true;
            info.permission = Permissions(p);
            info.index = medicalProfessionsLUT.length-1;

            medicalProfessions[addr] = info;
        }
        
        emit auditLog(block.timestamp);    
        return ret;
    }
    
    function removeAccess(address addr) isOwner public {
        if (medicalProfessions[addr].exist) {
            medicalProfessionInfo memory revoker = medicalProfessions[addr];
            if (revoker.index != medicalProfessionsLUT.length-1) {
                // swap last user with deleted user
                address lastAddr = medicalProfessionsLUT[medicalProfessionsLUT.length-1];
                medicalProfessions[lastAddr].index = revoker.index;     // Change index
                medicalProfessionsLUT[revoker.index] = lastAddr;        // Change LUT
            }

            medicalProfessionsLUT.pop();
            delete medicalProfessions[addr];   
        }
        emit auditLog(block.timestamp);    
    }

    function getMedicalProfession(address addr) public view returns (uint256) {
        return uint256(medicalProfessions[addr].permission);
    }

    function getMedicalProfessions() public view returns (address[] memory) {
        return medicalProfessionsLUT;
    }
    
    function viewData(uint256 id) Accessible public returns(string memory, address, uint256) {
        require(id <= nRecords, "Invalid Record");
        emit auditLog(block.timestamp);        
        return (medicalRecords[id].cid, medicalRecords[id].medicalProfession, medicalRecords[id].time);
    }
    
    function writeData(
        string memory documentation,
        uint256 timestamp
    ) isOwner Accessible public returns(uint256) {
        emit auditLog(block.timestamp);
        nRecords++;
        medicalRecord memory medRec;
        medRec.cid = documentation; 
        medRec.medicalProfession = msg.sender;
        medRec.time = timestamp;
        medicalRecords[nRecords] = medRec;

        return nRecords;
    }

    function isAccessible() public view returns (bool) {
        return msg.sender == owner || medicalProfessions[msg.sender].permission != Permissions.NONE;
    }
    
    modifier isOwner() {
        require(owner == msg.sender, "Requires Owner of contract");
        _;
    }
    
    modifier Accessible() {
        require(owner == msg.sender, "Not permitted");
        _;
    }
    
    modifier validPermission(uint256 p) {
        require(p >= uint256(Permissions.NONE) && p <= uint256(Permissions.BOTH), "Invalid Permission");
        _;
    }
}
