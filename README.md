# 🏛️ Pakistan Decentralized Land Registry

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?logo=solidity)](https://soliditylang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.0-4E5EE4?logo=openzeppelin)](https://openzeppelin.com/)

A production-grade, Sharia-compliant blockchain land administration system that replaces traditional paper-based land registries with NFT-based ownership certificates. Built for Pakistan's land governance infrastructure.

## 🎯 Overview

This smart contract implements a **hybrid on-chain/off-chain architecture** that combines:
- **ERC-721 NFTs** for immutable ownership certificates
- **IPFS** for decentralized document storage (deeds, maps, surveys)
- **Oracle pattern** for government database verification (NADRA integration)
- **Consensus-based inheritance** mechanism compliant with Islamic succession laws

### Key Innovation: Privacy-First Design

Unlike traditional blockchain implementations that store sensitive data on-chain, this contract uses **cryptographic hashing** to protect citizen privacy:
- CNICs (National ID numbers) are stored as `keccak256` hashes
- Land IDs are hashed for privacy while maintaining verifiability
- Only authorized parties can correlate on-chain records with real-world identities

---

## 🏗️ Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        OFF-CHAIN LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐         ┌─────────────────────────┐     │
│  │ Government       │────────▶│ Verification Oracle     │     │
│  │ Backend          │ Verifies│ (Trusted Address)       │     │
│  │ (NADRA DB)       │  NADRA  │                         │     │
│  └──────────────────┘         └──────────┬──────────────┘     │
│                                           │                     │
│  ┌──────────────────┐                     │                     │
│  │ IPFS Network     │                     │                     │
│  │ (Deeds/Maps)     │                     │                     │
│  └──────────────────┘                     │                     │
│                                           │                     │
└───────────────────────────────────────────┼─────────────────────┘
                                            │
                                            │ Calls storeVerifiedLandRecord()
                                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ON-CHAIN LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│              ┌────────────────────────────────┐                │
│              │   LandRegistry Contract        │                │
│              │   (Solidity Smart Contract)    │                │
│              └────────┬───────────────┬───────┘                │
│                       │               │                         │
│                       │ Mints         │ Stores                  │
│                       ▼               ▼                         │
│              ┌─────────────┐   ┌──────────────┐               │
│              │ ERC-721 NFT │   │ Privacy Layer│               │
│              │ (Ownership) │   │ (Hashed Data)│               │
│              └─────────────┘   └──────────────┘               │
│                                                                 │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ Interact
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                         USER LAYER                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐         ┌──────────────┐                    │
│  │  Citizens    │────────▶│   Register   │                    │
│  │              │         │   Transfer   │                    │
│  └──────────────┘         └──────────────┘                    │
│                                                                 │
│  ┌──────────────┐         ┌──────────────┐                    │
│  │  Heirs       │────────▶│   Approve    │                    │
│  │              │         │   Dispute    │                    │
│  └──────────────┘         └──────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Contract Inheritance

```
ERC721 (OpenZeppelin)
    ↓
Ownable (OpenZeppelin)
    ↓
LandRegistry (Custom Implementation)
```

---

## 🔑 Core Features

### 1. **Identity Management (Privacy-Preserving)**

```solidity
struct UserProfile {
    bytes32 nameHash;      // keccak256(name)
    bytes32 cnicHash;      // keccak256(CNIC)
    bool isRegistered;
}
```

**How it works:**
- Users register by submitting **hashed** credentials (computed off-chain)
- Contract prevents duplicate CNIC registrations via `cnicToAddress` mapping
- Government authorities can be whitelisted to bypass registration

**Privacy Guarantee:** Raw CNIC numbers never touch the blockchain.

---

### 2. **Land Registration (NFT Minting)**

```solidity
function storeVerifiedLandRecord(
    address owner,
    string calldata landId,
    bytes32 landIdHash,
    bytes32 ownerCnicHash,
    string calldata ipfsHash,
    LandType lType
) external onlyBackend
```

**Access Control:** Only the trusted `verificationBackend` can mint land NFTs.

**Process Flow:**
1. Government backend verifies land ownership in NADRA database
2. Backend calls `storeVerifiedLandRecord()` with verified data
3. Contract mints ERC-721 NFT with deterministic `tokenId = keccak256(landId)`
4. IPFS hash links to off-chain documents (deed, survey map, etc.)

**Land Types:**
- `RESIDENTIAL` - Housing plots
- `AGRICULTURAL` - Farmland
- `COMMERCIAL` - Business properties

---

### 3. **Ownership Transfer**

```solidity
function transferLandOwnership(
    string calldata landId,
    address newOwner,
    uint256 salePrice
) external
```

**Security Features:**
- ✅ Only current NFT owner can initiate transfer
- ✅ Receiver must be a registered user
- ✅ Land must be in `ACTIVE` status (not locked by inheritance/dispute)
- ✅ Transfer price recorded for taxation/audit purposes

**Automatic Updates:**
- NFT ownership transferred via ERC-721 `_safeTransfer`
- Ownership history appended with timestamp and price
- Seller's land list updated, buyer's list updated

---

### 4. **Sharia-Compliant Inheritance System**

#### 🔄 Inheritance Workflow

```
Backend          Contract              Heir1              Heir2
   │                 │                   │                  │
   │  initiateInheritance(oldLandId, [heir1, heir2], ...)  │
   ├────────────────▶│                   │                  │
   │                 │                   │                  │
   │                 │ Set status =      │                  │
   │                 │ PENDING_INHERITANCE                  │
   │                 │                   │                  │
   │                 │◀──────────────────┤                  │
   │                 │ approveSuccessionPlan(oldLandId)     │
   │                 │                   │                  │
   │                 │◀───────────────────────────────────┤
   │                 │          approveSuccessionPlan(oldLandId)
   │                 │                   │                  │
   │                 │ ✓ All heirs approved!               │
   │                 │ _executeInheritance()               │
   │                 │                   │                  │
   │                 │ 🔥 Burn old NFT   │                  │
   │                 │                   │                  │
   │                 ├──────────────────▶│                  │
   │                 │  Mint NFT (newLandId1)              │
   │                 │                   │                  │
   │                 ├───────────────────────────────────▶│
   │                 │         Mint NFT (newLandId2)       │
   │                 │                   │                  │
   │                 │ ✅ Inheritance Complete             │
```

#### Key Functions

**a) Initiate Inheritance (Backend Only)**
```solidity
function initiateInheritance(
    string calldata oldLandId,
    address[] memory heirs,
    string[] memory newLandIds,
    string[] memory newIpfsHashes
) external onlyBackend
```
- Locks the original land (`PENDING_INHERITANCE` status)
- Creates subdivision plan with new land IDs for each heir
- Requires unanimous approval from all heirs

**b) Heir Approval**
```solidity
function approveSuccessionPlan(string calldata oldLandId) external
```
- Each heir must explicitly approve the division
- Auto-executes when all heirs approve
- Prevents unilateral land grabs

**c) Dispute Resolution**
```solidity
function disputeSuccessionPlan(string calldata oldLandId) external
```
- Any heir can dispute the plan
- Locks land in `LOCKED_DISPUTE` status
- Requires backend intervention to resolve

**d) Backend Resolution**
```solidity
function resolveDispute(string calldata oldLandId, bool forceExecute) external onlyBackend
```
- Government authority can force execution or revert to `ACTIVE`
- Handles court-ordered resolutions

---

### 5. **Ownership History & Provenance**

```solidity
struct OwnershipHistory {
    address owner;
    uint256 timestamp;
    uint256 price;
}
```

Every land transfer is permanently recorded with:
- Previous owner's address
- Transfer timestamp
- Sale price (for tax compliance)

**Use Cases:**
- Audit trails for tax authorities
- Fraud detection (rapid flip patterns)
- Property valuation analytics

---

## 📊 Data Structures

### Land Record
```solidity
struct LandRecord {
    address currentOwner;
    bytes32 ownerCnicHash;    // Privacy-preserving
    bytes32 landIdHash;       // Privacy-preserving
    string landId;            // Mapping key (plain)
    string ipfsHash;          // Link to documents
    LandType landType;
    LandStatus status;
    uint256 verifiedAt;
}
```

### Land Status States
```solidity
enum LandStatus {
    ACTIVE,                  // Normal operations allowed
    PENDING_INHERITANCE,     // Awaiting heir consensus
    LOCKED_DISPUTE           // Frozen by dispute
}
```

---

## 🔐 Access Control

### Role-Based Permissions

| Role | Address | Capabilities |
|------|---------|-------------|
| **Owner** | Contract deployer | Set government authorities, upgrade backend |
| **Verification Backend** | Immutable oracle address | Mint land NFTs, initiate inheritance, resolve disputes |
| **Government Authority** | Whitelisted addresses | Receive land transfers without registration |
| **Registered Users** | Public | Register identity, transfer land, approve inheritance |

### Critical Modifiers

```solidity
modifier onlyBackend()           // Restricts to verification oracle
modifier landMustExist()         // Validates land ID exists
modifier onlyActive()            // Ensures land not locked
```

---

## 🛠️ Technical Implementation

### Gas Optimization Techniques

1. **Deterministic Token IDs**
   ```solidity
   function getTokenIdFromLandId(string memory landId) public pure returns (uint256) {
       return uint256(keccak256(abi.encodePacked(landId)));
   }
   ```
   - Eliminates need for counter storage
   - Enables off-chain token ID calculation

2. **Efficient Owner Tracking**
   ```solidity
   mapping(address => string[]) private ownerToLands;
   mapping(address => mapping(string => uint256)) private ownerLandIndex;
   ```
   - O(1) land removal via swap-and-pop pattern
   - Prevents array iteration gas costs

3. **Pagination for Large Datasets**
   ```solidity
   function getAllLandRecordsPaginated(uint256 cursor, uint256 resultsPerPage)
   ```
   - Prevents out-of-gas errors on large registries
   - Supports frontend pagination

### IPFS Integration

**Metadata Structure (Off-Chain):**
```json
{
  "name": "Land Parcel #12345",
  "description": "Residential plot in Islamabad",
  "image": "ipfs://Qm.../survey_map.png",
  "attributes": [
    {"trait_type": "Area", "value": "500 sq yards"},
    {"trait_type": "Location", "value": "Sector F-10"},
    {"trait_type": "Deed Number", "value": "ISB-2024-00123"}
  ]
}
```

**tokenURI Implementation:**
```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory) {
    string memory ipfsHash = landRecords[_tokenIdToLandId[tokenId]].ipfsHash;
    return string(abi.encodePacked("ipfs://", ipfsHash));
}
```

---

## 🚀 Deployment Guide

### Prerequisites

```bash
npm install @openzeppelin/contracts@5.0.0
```

### Constructor Parameters

```solidity
constructor(address _verificationBackend)
```

**Example Deployment:**
```javascript
const LandRegistry = await ethers.getContractFactory("LandRegistry");
const registry = await LandRegistry.deploy(
    "0x1234...5678"  // Backend oracle address
);
```

### Post-Deployment Setup

```javascript
// 1. Whitelist government authorities
await registry.setGovtAuthority("0xGovtWallet1", true);

// 2. Transfer ownership to DAO/Multisig (optional)
await registry.transferOwnership("0xMultisigAddress");
```

---

## 📖 Usage Examples

### 1. User Registration (Frontend)

```javascript
// Off-chain: Hash sensitive data
const nameHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Muhammad Ali"));
const cnicHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("12345-6789012-3"));

// On-chain: Register with hashes
await landRegistry.registerUser(nameHash, cnicHash);
```

### 2. Land Minting (Backend)

```javascript
// Backend verifies NADRA database, then:
const landIdHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ISB-F10-00123"));
const ownerCnicHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("12345-6789012-3"));

await landRegistry.storeVerifiedLandRecord(
    "0xOwnerAddress",
    "ISB-F10-00123",           // Plain land ID
    landIdHash,
    ownerCnicHash,
    "QmYwAPJzv5CZsnA...",      // IPFS hash
    0                          // RESIDENTIAL
);
```

### 3. Transfer Land

```javascript
await landRegistry.transferLandOwnership(
    "ISB-F10-00123",
    "0xBuyerAddress",
    ethers.utils.parseEther("50")  // Sale price in ETH
);
```

### 4. Inheritance Process

```javascript
// Backend initiates after owner's death certificate verification
await landRegistry.initiateInheritance(
    "ISB-F10-00123",
    ["0xHeir1", "0xHeir2"],
    ["ISB-F10-00123-A", "ISB-F10-00123-B"],
    ["QmHash1...", "QmHash2..."]
);

// Heirs approve
await landRegistry.connect(heir1).approveSuccessionPlan("ISB-F10-00123");
await landRegistry.connect(heir2).approveSuccessionPlan("ISB-F10-00123");
// Auto-executes after last approval
```

---

## 🔍 Query Functions

### Get Land Details
```solidity
function getLandRecord(string calldata landId) external view returns (LandRecord memory)
```

### Get User's Lands
```solidity
function getLandsByCnic(bytes32 cnicHash) external view returns (string[] memory)
```

### Paginated Registry View
```solidity
function getAllLandRecordsPaginated(uint256 cursor, uint256 resultsPerPage)
    external view returns (LandRecord[] memory results, uint256 nextCursor)
```

---

## 🎭 Events

```solidity
event UserRegistered(address indexed user, bytes32 nameHash, bytes32 cnicHash);
event LandMinted(address indexed owner, string landId, LandType lType, uint256 tokenId);
event LandTransferred(string landId, address indexed from, address indexed to, uint256 price);
event InheritanceInitiated(string oldLandId, uint256 totalHeirs);
event HeirApproved(string oldLandId, address indexed heir);
event InheritanceDisputed(string oldLandId, address indexed heir);
event InheritanceFinalized(string oldLandId);
event LandStatusChanged(string landId, LandStatus status);
```

**Use Cases:**
- Real-time frontend updates
- Audit log generation
- Analytics dashboards

---

## 🛡️ Security Considerations

### Implemented Protections

✅ **Reentrancy Safe:** Uses OpenZeppelin's `_safeMint` and `_safeTransfer`  
✅ **Access Control:** Multi-tier permission system  
✅ **Input Validation:** Comprehensive `require` statements  
✅ **Privacy:** Hashed sensitive data  
✅ **Immutable Oracle:** Backend address set at deployment  

### Recommended Audits

- [ ] Formal verification of inheritance logic
- [ ] Gas optimization review
- [ ] Frontend integration security (hash computation)
- [ ] Backend oracle security (NADRA API protection)

---

## 🧪 Testing Checklist

```bash
# Unit Tests
- User registration (duplicate prevention)
- Land minting (backend-only access)
- Transfer validation (status checks)
- Inheritance consensus (unanimous approval)
- Dispute locking mechanism

# Integration Tests
- IPFS metadata retrieval
- Backend oracle authentication
- Multi-heir scenarios
- Pagination edge cases

# Stress Tests
- 10,000+ land records
- 100+ heirs (edge case)
- Rapid transfer sequences
```

---

## 📜 License

MIT License - See [LICENSE](LICENSE) file

---

## 👥 Authors

**Muhammad Riyyan** - Core Architecture  
**Muhammad Haider Aziz** - Smart Contract Implementation

---

## 🤝 Contributing

This is a government infrastructure project. For feature requests or bug reports, please contact the development team through official channels.

---

## 📞 Support

For technical documentation and integration guides, refer to:
- [IPFS Documentation](https://docs.ipfs.io/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [ERC-721 Standard](https://eips.ethereum.org/EIPS/eip-721)

---

## 🔮 Roadmap

- [ ] Layer 2 deployment (Polygon/Arbitrum) for lower gas costs
- [ ] Multi-signature backend oracle (decentralization)
- [ ] Automated tax calculation integration
- [ ] Mobile app with biometric authentication
- [ ] Cross-province land transfer protocol

---

**Built with ❤️ for Pakistan's Digital Transformation**
