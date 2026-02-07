// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * =========================================================================
 * 🏛️ PAKISTAN DECENTRALIZED LAND REGISTRY
 * =========================================================================
 * @title LandRegistry
 * @author Muhammad Riyyan, Muhammad Haider Aziz
 * @notice A hybrid blockchain-based land administration system replacing traditional systems with NFTs (ERC721).
 * @dev ARCHITECTURAL HIGHLIGHTS:
 *      1. HYBRID STORAGE: Uses IPFS for heavy docs (Maps/Deeds) and Ethereum for ownership.
 *      2. ORACLE PATTERN: Uses a trusted Backend to verify Govt DB (NADRA) before minting.
 *      3. INHERITANCE: Implements a "Proposal & Consensus" model for Sharia-compliant succession.
 *      4. OPTIMIZATION: Uses standard ERC721 with manual URI handling to reduce contract size.
 */


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LandRegistry is ERC721, Ownable {

    enum LandType { RESIDENTIAL, AGRICULTURAL, COMMERCIAL }
    enum LandStatus { ACTIVE, PENDING_INHERITANCE, LOCKED_DISPUTE }


    /// @dev CHANGED: Stores hashes instead of raw strings for privacy
    struct LandRecord {
        address currentOwner;   
        bytes32 ownerCnicHash;  // Hashed CNIC
        bytes32 landIdHash;    // Hashed Govt ID
        string landId;          // Plain ID (for mapping key)
        string ipfsHash;        
        LandType landType;      
        LandStatus status;      
        uint256 verifiedAt;     
    }

    struct InheritanceRequest {
        address[] heirs;            
        string[] newLandIds;        
        string[] newIpfsHashes;     
        uint256 approvalCount;      
        bool isExecuted;            
        mapping(address => bool) hasApproved; 
    }

    struct OwnershipHistory {
        address owner;
        uint256 timestamp;
        uint256 price;          
    }

    /// @dev CHANGED: Name and CNIC are now hashed
    struct UserProfile {
        bytes32 nameHash;
        bytes32 cnicHash;
        bool isRegistered;
    }

    // --- Identity Module ---
    mapping(address => UserProfile) public users;
    // @dev CHANGED: Mapping key is now bytes32 (hashed CNIC)
    mapping(bytes32 => address) private cnicToAddress;

    // --- Land Data Module ---
    mapping(string => LandRecord) private landRecords;
    mapping(string => OwnershipHistory[]) private ownershipHistory;
    mapping(string => bool) private landExists;
    
    mapping(string => InheritanceRequest) public inheritanceRequests;
    mapping(uint256 => string) private _tokenIdToLandId;

    string[] private allLandIds;
    mapping(address => string[]) private ownerToLands;
    mapping(address => mapping(string => uint256)) private ownerLandIndex;

    mapping(address => bool) public isGovtAuthority; 
    address public immutable verificationBackend;    

    // --- EVENTS ---
    // @dev CHANGED: Params updated to bytes32
    event UserRegistered(address indexed user, bytes32 nameHash, bytes32 cnicHash);
    event LandMinted(address indexed owner, string landId, LandType lType, uint256 tokenId);
    event LandTransferred(string landId, address indexed from, address indexed to, uint256 price);
    event InheritanceInitiated(string oldLandId, uint256 totalHeirs);
    event HeirApproved(string oldLandId, address indexed heir);
    event InheritanceDisputed(string oldLandId, address indexed heir);
    event InheritanceFinalized(string oldLandId);
    event LandStatusChanged(string landId, LandStatus status);

    modifier onlyBackend() {
        require(msg.sender == verificationBackend, "Access Denied: Backend Only");
        _;
    }

    modifier landMustExist(string memory landId) {
        require(landExists[landId], "Error: Land does not exist");
        _;
    }

    modifier onlyActive(string memory landId) {
        require(landRecords[landId].status == LandStatus.ACTIVE, "Error: Land is Locked/Pending");
        _;
    }

    constructor(address _verificationBackend) ERC721("PakLandRegistry", "PLR") Ownable(msg.sender) {
        require(_verificationBackend != address(0), "Invalid Backend Address");
        verificationBackend = _verificationBackend;
    }

    function setGovtAuthority(address _wallet, bool _status) external onlyOwner {
        isGovtAuthority[_wallet] = _status;
    }

    /**
     * @notice Identity Registration (Hashed)
     * @dev CHANGED: Takes bytes32 hashes instead of raw strings
     */
    function registerUser(bytes32 _nameHash, bytes32 _cnicHash) external {
        require(!users[msg.sender].isRegistered, "Wallet already registered");
        require(cnicToAddress[_cnicHash] == address(0), "CNIC already linked to another wallet");
        
        users[msg.sender] = UserProfile(_nameHash, _cnicHash, true);
        cnicToAddress[_cnicHash] = msg.sender;
        
        emit UserRegistered(msg.sender, _nameHash, _cnicHash);
    }

    /**
     * @notice Land Registration (Minting)
     * @dev CHANGED: Added bytes32 hash parameters
     */
    function storeVerifiedLandRecord(
        address owner,
        string calldata landId,
        bytes32 landIdHash,     // New
        bytes32 ownerCnicHash,  // New
        string calldata ipfsHash,
        LandType lType
    ) external onlyBackend {
        require(users[owner].isRegistered || isGovtAuthority[owner], "Owner must be Registered User or Govt");
        require(!landExists[landId], "Land ID already exists");

        landRecords[landId] = LandRecord({
            currentOwner: owner,
            ownerCnicHash: ownerCnicHash,
            landIdHash: landIdHash,
            landId: landId,
            ipfsHash: ipfsHash,
            landType: lType,
            status: LandStatus.ACTIVE,
            verifiedAt: block.timestamp
        });

        landExists[landId] = true;
        allLandIds.push(landId);
        _addToOwnerList(owner, landId);
        ownershipHistory[landId].push(OwnershipHistory(owner, block.timestamp, 0));

        uint256 tokenId = getTokenIdFromLandId(landId);
        _safeMint(owner, tokenId);
        _tokenIdToLandId[tokenId] = landId; 

        emit LandMinted(owner, landId, lType, tokenId);
    }

    function transferLandOwnership(
        string calldata landId,
        address newOwner,
        uint256 salePrice
    ) external landMustExist(landId) onlyActive(landId) {
        uint256 tokenId = getTokenIdFromLandId(landId);
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        require(newOwner != msg.sender, "Cannot self-transfer");
        require(users[newOwner].isRegistered || isGovtAuthority[newOwner], "Receiver is not registered");

        _safeTransfer(msg.sender, newOwner, tokenId, "");

        landRecords[landId].currentOwner = newOwner;
        // Update the hashed CNIC reference
        landRecords[landId].ownerCnicHash = users[newOwner].isRegistered ? users[newOwner].cnicHash : bytes32(0);

        _removeFromOwnerList(msg.sender, landId);
        _addToOwnerList(newOwner, landId);
        ownershipHistory[landId].push(OwnershipHistory(newOwner, block.timestamp, salePrice));

        emit LandTransferred(landId, msg.sender, newOwner, salePrice);
    }

    function initiateInheritance(
        string calldata oldLandId,
        address[] memory heirs,          
        string[] memory newLandIds,      
        string[] memory newIpfsHashes    
    ) external onlyBackend landMustExist(oldLandId) onlyActive(oldLandId) {
        require(heirs.length == newLandIds.length && heirs.length == newIpfsHashes.length, "Input Mismatch");

        landRecords[oldLandId].status = LandStatus.PENDING_INHERITANCE;

        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        req.heirs = heirs;
        req.newLandIds = newLandIds;
        req.newIpfsHashes = newIpfsHashes;
        req.approvalCount = 0;
        req.isExecuted = false;

        emit InheritanceInitiated(oldLandId, heirs.length);
        emit LandStatusChanged(oldLandId, LandStatus.PENDING_INHERITANCE);
    }

    function approveSuccessionPlan(string calldata oldLandId) external {
        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        require(landRecords[oldLandId].status == LandStatus.PENDING_INHERITANCE, "No pending plan");
        require(!req.isExecuted, "Plan already executed");
        require(!req.hasApproved[msg.sender], "You already voted");

        bool isHeir = false;
        for (uint i = 0; i < req.heirs.length; i++) {
            if (req.heirs[i] == msg.sender) { isHeir = true; break; }
        }
        require(isHeir, "Caller is not an heir");

        req.hasApproved[msg.sender] = true;
        req.approvalCount++;
        emit HeirApproved(oldLandId, msg.sender);

        if (req.approvalCount == req.heirs.length) {
            _executeInheritance(oldLandId);
        }
    }

    function disputeSuccessionPlan(string calldata oldLandId) external {
        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        require(landRecords[oldLandId].status == LandStatus.PENDING_INHERITANCE, "No pending plan");
        
        bool isHeir = false;
        for (uint i = 0; i < req.heirs.length; i++) {
            if (req.heirs[i] == msg.sender) { isHeir = true; break; }
        }
        require(isHeir, "Caller is not an heir");

        landRecords[oldLandId].status = LandStatus.LOCKED_DISPUTE;
        emit InheritanceDisputed(oldLandId, msg.sender);
        emit LandStatusChanged(oldLandId, LandStatus.LOCKED_DISPUTE);
    }

    function _executeInheritance(string memory oldLandId) private {
        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        req.isExecuted = true;

        uint256 oldTokenId = getTokenIdFromLandId(oldLandId);
        _burn(oldTokenId);
        delete _tokenIdToLandId[oldTokenId]; 
        landRecords[oldLandId].currentOwner = address(0);
        
        for (uint i = 0; i < req.heirs.length; i++) {
            _mintInternal(req.heirs[i], req.newLandIds[i], req.newIpfsHashes[i], landRecords[oldLandId].landType);
        }

        emit InheritanceFinalized(oldLandId);
    }

    function resolveDispute(string calldata oldLandId, bool forceExecute) external onlyBackend {
        require(landRecords[oldLandId].status == LandStatus.LOCKED_DISPUTE, "Land not disputed");
        if (forceExecute) {
            _executeInheritance(oldLandId);
        } else {
            landRecords[oldLandId].status = LandStatus.ACTIVE;
            emit LandStatusChanged(oldLandId, LandStatus.ACTIVE);
        }
    }

    function _mintInternal(address owner, string memory landId, string memory ipfs, LandType lType) private {
        require(!landExists[landId], "Land ID collision");
        
        // Use keccak256 internally for ID and CNIC hashes if not provided
        landRecords[landId] = LandRecord({
            currentOwner: owner,
            ownerCnicHash: users[owner].cnicHash,
            landIdHash: keccak256(abi.encodePacked(landId)),
            landId: landId,
            ipfsHash: ipfs,
            landType: lType,
            status: LandStatus.ACTIVE,
            verifiedAt: block.timestamp
        });

        landExists[landId] = true;
        allLandIds.push(landId);
        _addToOwnerList(owner, landId);
        ownershipHistory[landId].push(OwnershipHistory(owner, block.timestamp, 0));

        uint256 tokenId = getTokenIdFromLandId(landId);
        _safeMint(owner, tokenId);
        _tokenIdToLandId[tokenId] = landId; 
    }

    function _addToOwnerList(address owner, string memory landId) private {
        ownerToLands[owner].push(landId);
        ownerLandIndex[owner][landId] = ownerToLands[owner].length - 1;
    }

    function _removeFromOwnerList(address owner, string memory landId) private {
        uint256 len = ownerToLands[owner].length;
        uint256 idx = ownerLandIndex[owner][landId];
        if (idx != len - 1) {
            string memory lastId = ownerToLands[owner][len - 1];
            ownerToLands[owner][idx] = lastId;
            ownerLandIndex[owner][lastId] = idx;
        }
        ownerToLands[owner].pop();
        delete ownerLandIndex[owner][landId];
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ERC721: invalid token ID");
        string memory landId = _tokenIdToLandId[tokenId];
        string memory ipfsHash = landRecords[landId].ipfsHash;
        return string(abi.encodePacked("ipfs://", ipfsHash));
    }

    function getTokenIdFromLandId(string memory landId) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(landId)));
    }

    function getLandRecord(string calldata landId) external view returns (LandRecord memory) {
        return landRecords[landId];
    }

    // @dev CHANGED: Search now uses bytes32 hash
    function getLandsByCnic(bytes32 cnicHash) external view returns (string[] memory) {
        return ownerToLands[cnicToAddress[cnicHash]];
    }

    function getAllLandRecordsPaginated(uint256 cursor, uint256 resultsPerPage) 
        external 
        view 
        returns (LandRecord[] memory results, uint256 nextCursor) 
    {
        uint256 length = allLandIds.length;
        if (cursor >= length) {
            return (new LandRecord[](0), length);
        }

        uint256 remaining = length - cursor;
        uint256 size = remaining < resultsPerPage ? remaining : resultsPerPage;

        results = new LandRecord[](size);

        for (uint256 i = 0; i < size; i++) {
            results[i] = landRecords[allLandIds[cursor + i]];
        }

        return (results, cursor + size);
    }
}