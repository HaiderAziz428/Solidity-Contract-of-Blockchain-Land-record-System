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

    // ========================================================================
    // 1. DATA STRUCTURES & TYPES
    // ========================================================================

    /// @notice Categorization to determine physical divisibility (e.g., Agri is split, House is joint)
    enum LandType { RESIDENTIAL, AGRICULTURAL, COMMERCIAL }

    /// @notice The Lifecycle State of the Asset
    /// ACTIVE: Normal state, tradeable.
    /// PENDING_INHERITANCE: Locked because Govt initiated a succession plan.
    /// LOCKED_DISPUTE: Frozen because an heir rejected the succession plan.
    enum LandStatus { ACTIVE, PENDING_INHERITANCE, LOCKED_DISPUTE }

    /// @notice The Master Record for every property on-chain
    struct LandRecord {
        address currentOwner;   // Wallet Address (User or Govt)
        string cnic;            // Identity Link (e.g., "42101-...")
        string landId;          // The Legal Govt ID (e.g., "ISL-F10-22")
        string ipfsHash;        // CID of the Deed/Map stored on IPFS
        LandType landType;      // Type classification
        LandStatus status;      // Security status
        uint256 verifiedAt;     // Timestamp of minting
    }

    /// @notice Represents a Court-Ordered Succession Proposal
    struct InheritanceRequest {
        address[] heirs;            // List of legitimate heirs from Court Order
        string[] newLandIds;        // New Govt IDs assigned to split portions
        string[] newIpfsHashes;     // Specific maps (Fertile/Infertile) for each heir
        uint256 approvalCount;      // Vote counter
        bool isExecuted;            // Prevention against double-execution
        mapping(address => bool) hasApproved; // Tracks who has voted
    }

    /// @notice Permanent Log of Transaction History
    struct OwnershipHistory {
        address owner;
        uint256 timestamp;
        uint256 price;          // Sale price in Wei/PKR (For Tax Transparency)
    }

    /// @notice Digital Identity Profile
    struct UserProfile {
        string name;
        string cnic;
        bool isRegistered;
    }

    // ========================================================================
    // 2. STATE STORAGE (DATABASE)
    // ========================================================================

    // --- Identity Module ---
    mapping(address => UserProfile) public users;
    // Reverse Lookup: Allows Officials to find Wallets using CNIC
    mapping(string => address) private cnicToAddress;

    // --- Land Data Module ---
    mapping(string => LandRecord) private landRecords;
    mapping(string => OwnershipHistory[]) private ownershipHistory;
    mapping(string => bool) private landExists;
    
    // --- Inheritance Module ---
    // Maps Old Land ID -> The Proposed Succession Plan
    mapping(string => InheritanceRequest) public inheritanceRequests;

    // --- NFT Optimization Module ---
    // Maps TokenID -> LandID string (Saves space by avoiding ERC721URIStorage)
    mapping(uint256 => string) private _tokenIdToLandId;

    // --- Indexing Module (For Dashboard) ---
    string[] private allLandIds;
    mapping(address => string[]) private ownerToLands;
    mapping(address => mapping(string => uint256)) private ownerLandIndex;

    // --- Access Control Module ---
    mapping(address => bool) public isGovtAuthority; // Whitelist for Govt Wallets (CDA/LDA)
    address public immutable verificationBackend;    // The Trusted Server (Oracle)

    // ========================================================================
    // 3. EVENTS (LOGGING)
    // ========================================================================

    event UserRegistered(address indexed user, string name, string cnic);
    event LandMinted(address indexed owner, string landId, LandType lType, uint256 tokenId);
    event LandTransferred(string landId, address indexed from, address indexed to, uint256 price);
    event InheritanceInitiated(string oldLandId, uint256 totalHeirs);
    event HeirApproved(string oldLandId, address indexed heir);
    event InheritanceDisputed(string oldLandId, address indexed heir);
    event InheritanceFinalized(string oldLandId);
    event LandStatusChanged(string landId, LandStatus status);

    // ========================================================================
    // 4. MODIFIERS (SECURITY RULES)
    // ========================================================================

    /// @dev Only allows the trusted backend server to call (Oracle Pattern)
    modifier onlyBackend() {
        require(msg.sender == verificationBackend, "Access Denied: Backend Only");
        _;
    }

    /// @dev Ensures the Land ID is valid and exists in the system
    modifier landMustExist(string memory landId) {
        require(landExists[landId], "Error: Land does not exist");
        _;
    }

    /// @dev Prevents transfers if Land is Locked (Disputed or Pending Inheritance)
    modifier onlyActive(string memory landId) {
        require(landRecords[landId].status == LandStatus.ACTIVE, "Error: Land is Locked/Pending");
        _;
    }

    constructor(address _verificationBackend) ERC721("PakLandRegistry", "PLR") Ownable(msg.sender) {
        require(_verificationBackend != address(0), "Invalid Backend Address");
        verificationBackend = _verificationBackend;
    }

    /**
     * @notice Admin function to whitelist Govt Dept wallets (CDA, DHA, etc.)
     *         so they can hold land without a personal CNIC.
     */
    function setGovtAuthority(address _wallet, bool _status) external onlyOwner {
        isGovtAuthority[_wallet] = _status;
    }

    // ========================================================================
    // 5. MODULE: IDENTITY REGISTRATION
    // ========================================================================

    /**
     * @notice Links a blockchain wallet to a Real World Identity (CNIC).
     * @param _name Full Name as per CNIC.
     * @param _cnic National ID Number (Unique Key).
     */
    function registerUser(string calldata _name, string calldata _cnic) external {
        require(!users[msg.sender].isRegistered, "Wallet already registered");
        require(cnicToAddress[_cnic] == address(0), "CNIC already linked to another wallet");
        
        users[msg.sender] = UserProfile(_name, _cnic, true);
        cnicToAddress[_cnic] = msg.sender;
        
        emit UserRegistered(msg.sender, _name, _cnic);
    }

    // ========================================================================
    // 6. MODULE: LAND REGISTRATION (MINTING)
    // ========================================================================

    /**
     * @notice The Entry Point for new lands. Called by Backend after verifying
     *         legacy records in the Govt Database.
     * @param owner The wallet address of the citizen or Govt authority.
     * @param landId The official ID (e.g., "ISL-101").
     * @param ipfsHash The CID of the digital file stored on IPFS.
     * @param lType The classification (Res/Agri/Comm).
     */
    function storeVerifiedLandRecord(
        address owner,
        string calldata landId,
        string calldata ipfsHash,
        LandType lType
    ) external onlyBackend {
        require(users[owner].isRegistered || isGovtAuthority[owner], "Owner must be Registered User or Govt");
        require(!landExists[landId], "Land ID already exists");

        // 1. Create the On-Chain Record
        landRecords[landId] = LandRecord({
            currentOwner: owner,
            cnic: users[owner].isRegistered ? users[owner].cnic : "GOVT",
            landId: landId,
            ipfsHash: ipfsHash,
            landType: lType,
            status: LandStatus.ACTIVE,
            verifiedAt: block.timestamp
        });

        // 2. Update Indexing
        landExists[landId] = true;
        allLandIds.push(landId);
        _addToOwnerList(owner, landId);

        // 3. Initialize History
        ownershipHistory[landId].push(OwnershipHistory(owner, block.timestamp, 0));

        // 4. Mint the NFT
        uint256 tokenId = getTokenIdFromLandId(landId);
        _safeMint(owner, tokenId);
        
        // *Optimization*: Link ID manually instead of using heavy storage
        _tokenIdToLandId[tokenId] = landId; 

        emit LandMinted(owner, landId, lType, tokenId);
    }

    // ========================================================================
    // 7. MODULE: TRANSFER (MARKETPLACE SETTLEMENT)
    // ========================================================================

    /**
     * @notice Executes a sale/transfer between two parties.
     * @dev Includes 'salePrice' to maintain a transparent price history.
     */
    function transferLandOwnership(
        string calldata landId,
        address newOwner,
        uint256 salePrice
    ) external landMustExist(landId) onlyActive(landId) {
        uint256 tokenId = getTokenIdFromLandId(landId);
        
        // Security Checks
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        require(newOwner != msg.sender, "Cannot self-transfer");
        require(users[newOwner].isRegistered || isGovtAuthority[newOwner], "Receiver is not registered");

        // 1. Execute NFT Transfer
        _safeTransfer(msg.sender, newOwner, tokenId, "");

        // 2. Update Internal Record
        landRecords[landId].currentOwner = newOwner;
        landRecords[landId].cnic = users[newOwner].isRegistered ? users[newOwner].cnic : "GOVT";

        // 3. Update Manual Lists (Swap & Pop)
        _removeFromOwnerList(msg.sender, landId);
        _addToOwnerList(newOwner, landId);

        // 4. Log History
        ownershipHistory[landId].push(OwnershipHistory(newOwner, block.timestamp, salePrice));

        emit LandTransferred(landId, msg.sender, newOwner, salePrice);
    }

    // ========================================================================
    // 8. MODULE: INHERITANCE (CONSENSUS ENGINE)
    // ========================================================================

    /**
     * @notice STEP 1: Govt initiates succession based on Court Order.
     * @dev Uses 'memory' for arrays to avoid "Copying nested calldata" error.
     * @param newIpfsHashes Contains specific maps (e.g. Fertile vs Infertile) for each heir.
     */
    function initiateInheritance(
        string calldata oldLandId,
        address[] memory heirs,          
        string[] memory newLandIds,      
        string[] memory newIpfsHashes    
    ) external onlyBackend landMustExist(oldLandId) onlyActive(oldLandId) {
        require(heirs.length == newLandIds.length && heirs.length == newIpfsHashes.length, "Input Mismatch");

        // Lock the Asset so it cannot be sold during verification
        landRecords[oldLandId].status = LandStatus.PENDING_INHERITANCE;

        // Create the Proposal
        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        req.heirs = heirs;
        req.newLandIds = newLandIds;
        req.newIpfsHashes = newIpfsHashes;
        req.approvalCount = 0;
        req.isExecuted = false;

        emit InheritanceInitiated(oldLandId, heirs.length);
        emit LandStatusChanged(oldLandId, LandStatus.PENDING_INHERITANCE);
    }

    /**
     * @notice STEP 2: Heirs verify the map/order on frontend and Vote "Approve".
     */
    function approveSuccessionPlan(string calldata oldLandId) external {
        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        require(landRecords[oldLandId].status == LandStatus.PENDING_INHERITANCE, "No pending plan");
        require(!req.isExecuted, "Plan already executed");
        require(!req.hasApproved[msg.sender], "You already voted");

        // Security: Check if caller is truly an heir
        bool isHeir = false;
        for (uint i = 0; i < req.heirs.length; i++) {
            if (req.heirs[i] == msg.sender) {
                isHeir = true;
                break;
            }
        }
        require(isHeir, "Caller is not an heir");

        // Record Vote
        req.hasApproved[msg.sender] = true;
        req.approvalCount++;
        emit HeirApproved(oldLandId, msg.sender);

        // Trigger Execution if Consensus Reached (100% Agreement)
        if (req.approvalCount == req.heirs.length) {
            _executeInheritance(oldLandId);
        }
    }

    /**
     * @notice STEP 2B: Heir detects fabrication and Disputes the plan.
     */
    function disputeSuccessionPlan(string calldata oldLandId) external {
        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        require(landRecords[oldLandId].status == LandStatus.PENDING_INHERITANCE, "No pending plan");
        
        bool isHeir = false;
        for (uint i = 0; i < req.heirs.length; i++) {
            if (req.heirs[i] == msg.sender) { isHeir = true; break; }
        }
        require(isHeir, "Caller is not an heir");

        // Hard Lock the Land
        landRecords[oldLandId].status = LandStatus.LOCKED_DISPUTE;
        emit InheritanceDisputed(oldLandId, msg.sender);
        emit LandStatusChanged(oldLandId, LandStatus.LOCKED_DISPUTE);
    }

    /**
     * @notice STEP 3: Internal Execution. Burns old NFT, Mints new ones.
     */
    function _executeInheritance(string memory oldLandId) private {
        InheritanceRequest storage req = inheritanceRequests[oldLandId];
        req.isExecuted = true;

        // 1. Burn the Deceased's NFT
        uint256 oldTokenId = getTokenIdFromLandId(oldLandId);
        _burn(oldTokenId);
        delete _tokenIdToLandId[oldTokenId]; // Cleanup
        landRecords[oldLandId].currentOwner = address(0);
        
        // 2. Mint New NFTs for Heirs
        for (uint i = 0; i < req.heirs.length; i++) {
            _mintInternal(req.heirs[i], req.newLandIds[i], req.newIpfsHashes[i], landRecords[oldLandId].landType);
        }

        emit InheritanceFinalized(oldLandId);
    }

    /**
     * @notice STEP 4: Government Resolution for Disputed Lands.
     */
    function resolveDispute(string calldata oldLandId, bool forceExecute) external onlyBackend {
        require(landRecords[oldLandId].status == LandStatus.LOCKED_DISPUTE, "Land not disputed");
        if (forceExecute) {
            _executeInheritance(oldLandId);
        } else {
            // Reset to Active (Allows creating a new, corrected proposal)
            landRecords[oldLandId].status = LandStatus.ACTIVE;
            emit LandStatusChanged(oldLandId, LandStatus.ACTIVE);
        }
    }

    // ========================================================================
    // 9. INTERNAL HELPER FUNCTIONS
    // ========================================================================

    function _mintInternal(address owner, string memory landId, string memory ipfs, LandType lType) private {
        require(!landExists[landId], "Land ID collision");
        
        landRecords[landId] = LandRecord(owner, users[owner].cnic, landId, ipfs, lType, LandStatus.ACTIVE, block.timestamp);
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

    // ========================================================================
    // 10. VIEW FUNCTIONS (DASHBOARD)
    // ========================================================================

    /**
     * @notice Returns the metadata URI (IPFS Link) for a Token ID.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ERC721: invalid token ID");
        string memory landId = _tokenIdToLandId[tokenId];
        string memory ipfsHash = landRecords[landId].ipfsHash;
        return string(abi.encodePacked("ipfs://", ipfsHash));
    }

    /**
     * @notice Generates a deterministic Token ID from a Land ID string.
     */
    function getTokenIdFromLandId(string memory landId) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(landId)));
    }

    function getLandRecord(string calldata landId) external view returns (LandRecord memory) {
        return landRecords[landId];
    }

    function getLandsByCnic(string calldata cnic) external view returns (string[] memory) {
        return ownerToLands[cnicToAddress[cnic]];
    }

    /**
     * @notice Pagination for Govt Officials to browse registry without crashing.
     */
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