// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MusicRegistry
 * @dev NFT-based music ownership registry with fingerprint verification
 * @notice This contract enables creators to register music with on-chain fingerprints
 */
contract MusicRegistry is ERC721, Ownable {
    uint256 private _tokenIds;

    struct MusicMetadata {
        string ipfsCID;              // IPFS CID for music metadata
        bytes32 fingerprintHash;     // Keccak256 hash of audio fingerprint
        address creator;              // Original creator address
        uint256 registeredAt;         // Registration timestamp
        string title;                 // Music title
        string artist;                // Artist name
        bool isActive;                // Active status
    }

    // Mapping from token ID to music metadata
    mapping(uint256 => MusicMetadata) private _musicData;

    // Mapping from fingerprint hash to token ID (for quick lookup)
    mapping(bytes32 => uint256) private _fingerprintToToken;

    // Mapping to track if a fingerprint is already registered
    mapping(bytes32 => bool) private _registeredFingerprints;

    // Events
    event MusicRegistered(
        uint256 indexed tokenId,
        address indexed creator,
        bytes32 indexed fingerprintHash,
        string ipfsCID,
        string title
    );

    event MusicDeactivated(uint256 indexed tokenId);
    event MusicReactivated(uint256 indexed tokenId);

    constructor() ERC721("TuneCent Music Rights", "TCMR") Ownable(msg.sender) {}

    /**
     * @dev Register a new music piece with fingerprint
     * @param ipfsCID IPFS content identifier for metadata
     * @param fingerprintHash Keccak256 hash of the audio fingerprint
     * @param title Music title
     * @param artist Artist name
     * @return tokenId The minted NFT token ID
     */
    function registerMusic(
        string memory ipfsCID,
        bytes32 fingerprintHash,
        string memory title,
        string memory artist
    ) external returns (uint256) {
        require(bytes(ipfsCID).length > 0, "IPFS CID cannot be empty");
        require(fingerprintHash != bytes32(0), "Fingerprint hash cannot be empty");
        require(bytes(title).length > 0, "Title cannot be empty");
        require(!_registeredFingerprints[fingerprintHash], "Fingerprint already registered");

        _tokenIds++;
        uint256 newTokenId = _tokenIds;

        // Mint NFT to creator
        _safeMint(msg.sender, newTokenId);

        // Store metadata
        _musicData[newTokenId] = MusicMetadata({
            ipfsCID: ipfsCID,
            fingerprintHash: fingerprintHash,
            creator: msg.sender,
            registeredAt: block.timestamp,
            title: title,
            artist: artist,
            isActive: true
        });

        // Map fingerprint to token ID
        _fingerprintToToken[fingerprintHash] = newTokenId;
        _registeredFingerprints[fingerprintHash] = true;

        emit MusicRegistered(newTokenId, msg.sender, fingerprintHash, ipfsCID, title);

        return newTokenId;
    }

    /**
     * @dev Verify if a fingerprint matches a registered music
     * @param fingerprintHash The fingerprint hash to verify
     * @return exists Whether the fingerprint exists
     * @return tokenId The associated token ID (0 if not found)
     * @return creator The creator address
     */
    function verifyFingerprint(bytes32 fingerprintHash)
        external
        view
        returns (bool exists, uint256 tokenId, address creator)
    {
        if (!_registeredFingerprints[fingerprintHash]) {
            return (false, 0, address(0));
        }

        tokenId = _fingerprintToToken[fingerprintHash];
        MusicMetadata memory metadata = _musicData[tokenId];

        return (metadata.isActive, tokenId, ownerOf(tokenId));
    }

    /**
     * @dev Get full music metadata
     * @param tokenId The NFT token ID
     * @return metadata The music metadata struct
     */
    function getMusicMetadata(uint256 tokenId)
        external
        view
        returns (MusicMetadata memory)
    {
        require(_exists(tokenId), "Token does not exist");
        return _musicData[tokenId];
    }

    /**
     * @dev Get current owner of a music NFT
     * @param tokenId The NFT token ID
     * @return owner The current owner address
     */
    function getCurrentOwner(uint256 tokenId) external view returns (address) {
        require(_exists(tokenId), "Token does not exist");
        return ownerOf(tokenId);
    }

    /**
     * @dev Deactivate a music registration (only by owner)
     * @param tokenId The NFT token ID to deactivate
     */
    function deactivateMusic(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(_musicData[tokenId].isActive, "Already deactivated");

        _musicData[tokenId].isActive = false;
        emit MusicDeactivated(tokenId);
    }

    /**
     * @dev Reactivate a music registration (only by owner)
     * @param tokenId The NFT token ID to reactivate
     */
    function reactivateMusic(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(!_musicData[tokenId].isActive, "Already active");

        _musicData[tokenId].isActive = true;
        emit MusicReactivated(tokenId);
    }

    /**
     * @dev Get total number of registered music pieces
     * @return count The total count
     */
    function getTotalRegistered() external view returns (uint256) {
        return _tokenIds;
    }

    /**
     * @dev Check if a token exists
     * @param tokenId The token ID to check
     * @return exists Whether the token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _musicData[tokenId].registeredAt > 0;
    }

    /**
     * @dev Override tokenURI to return IPFS URI
     * @param tokenId The token ID
     * @return The token URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return string(abi.encodePacked("ipfs://", _musicData[tokenId].ipfsCID));
    }
}
