// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MusicRegistry.sol";
import "./ReputationScore.sol";

/**
 * @title RoyaltyDistributor
 * @dev Manages royalty payments and programmable splits with micro-payment streaming
 * @notice Handles automated royalty distribution based on configurable splits
 */
contract RoyaltyDistributor is Ownable, ReentrancyGuard {
    MusicRegistry public musicRegistry;
    ReputationScore public reputationScore;

    struct RoyaltySplit {
        address[] beneficiaries;
        uint256[] percentages; // In basis points (10000 = 100%)
        bool isConfigured;
    }

    struct PaymentContext {
        string platform; // e.g., "TikTok", "Spotify"
        string usageType; // e.g., "video", "stream"
        uint256 timestamp;
    }

    // Mapping from token ID to royalty split configuration
    mapping(uint256 => RoyaltySplit) private _royaltySplits;

    // Mapping from token ID to pending royalties
    mapping(uint256 => uint256) public pendingRoyalties;

    // Mapping to track total earnings per token
    mapping(uint256 => uint256) public totalEarnings;

    // Mapping to track total distributed per beneficiary per token
    mapping(uint256 => mapping(address => uint256)) public distributedTo;

    // Default split if not configured (90% creator, 10% platform fee)
    uint256 public constant DEFAULT_CREATOR_PERCENTAGE = 9000; // 90%
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 1000; // 10%
    address public platformFeeRecipient;

    // Minimum royalty amount for distribution
    uint256 public constant MIN_DISTRIBUTION_AMOUNT = 0.0001 ether;

    // Events
    event RoyaltyReceived(
        uint256 indexed tokenId, address indexed from, uint256 amount, string platform, string usageType
    );

    event RoyaltyDistributed(uint256 indexed tokenId, address indexed beneficiary, uint256 amount);

    event RoyaltySplitConfigured(uint256 indexed tokenId, address[] beneficiaries, uint256[] percentages);

    event PlatformFeeCollected(address indexed recipient, uint256 amount);

    constructor(address _musicRegistry, address _reputationScore, address _platformFeeRecipient) Ownable(msg.sender) {
        require(_musicRegistry != address(0), "Invalid registry address");
        require(_reputationScore != address(0), "Invalid reputation address");
        require(_platformFeeRecipient != address(0), "Invalid fee recipient");

        musicRegistry = MusicRegistry(_musicRegistry);
        reputationScore = ReputationScore(_reputationScore);
        platformFeeRecipient = _platformFeeRecipient;
    }

    /**
     * @dev Configure royalty split for a music token
     * @param tokenId The music NFT token ID
     * @param beneficiaries Array of beneficiary addresses
     * @param percentages Array of percentages in basis points (must sum to 10000)
     */
    function setRoyaltySplit(uint256 tokenId, address[] memory beneficiaries, uint256[] memory percentages) external {
        address owner = musicRegistry.getCurrentOwner(tokenId);
        require(msg.sender == owner, "Only owner can set splits");
        require(beneficiaries.length == percentages.length, "Length mismatch");
        require(beneficiaries.length > 0, "Empty beneficiaries");

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            require(beneficiaries[i] != address(0), "Invalid beneficiary");
            require(percentages[i] > 0, "Percentage must be > 0");
            totalPercentage += percentages[i];
        }
        require(totalPercentage == 10000, "Total must be 100%");

        _royaltySplits[tokenId] =
            RoyaltySplit({beneficiaries: beneficiaries, percentages: percentages, isConfigured: true});

        emit RoyaltySplitConfigured(tokenId, beneficiaries, percentages);
    }

    /**
     * @dev Pay royalty for music usage (called by platform/detection service)
     * @param tokenId The music NFT token ID
     * @param platform Platform name (e.g., "TikTok")
     * @param usageType Usage type (e.g., "video", "stream")
     */
    function payRoyalty(uint256 tokenId, string memory platform, string memory usageType) external payable {
        require(msg.value > 0, "Payment must be > 0");

        // Verify music exists and is active
        (bool exists,, address creator) = musicRegistry.verifyFingerprint(_getTokenFingerprint(tokenId));
        require(exists, "Music not found or inactive");

        // Add to pending royalties
        pendingRoyalties[tokenId] += msg.value;
        totalEarnings[tokenId] += msg.value;

        emit RoyaltyReceived(tokenId, msg.sender, msg.value, platform, usageType);
    }

    /**
     * @dev Distribute pending royalties for a token
     * @param tokenId The music NFT token ID
     */
    function distributeRoyalties(uint256 tokenId) external nonReentrant {
        uint256 pending = pendingRoyalties[tokenId];
        require(pending >= MIN_DISTRIBUTION_AMOUNT, "Insufficient pending royalties");

        address owner = musicRegistry.getCurrentOwner(tokenId);
        RoyaltySplit memory split = _royaltySplits[tokenId];

        // Reset pending before distribution (reentrancy protection)
        pendingRoyalties[tokenId] = 0;

        if (!split.isConfigured) {
            // Default split: 90% to owner, 10% platform fee
            uint256 ownerAmount = (pending * DEFAULT_CREATOR_PERCENTAGE) / 10000;
            uint256 feeAmount = (pending * PLATFORM_FEE_PERCENTAGE) / 10000;

            _transfer(owner, ownerAmount);
            _transfer(platformFeeRecipient, feeAmount);

            distributedTo[tokenId][owner] += ownerAmount;
            emit RoyaltyDistributed(tokenId, owner, ownerAmount);
            emit PlatformFeeCollected(platformFeeRecipient, feeAmount);

            // Update reputation
            reputationScore.addEarnings(owner, ownerAmount);
        } else {
            // Custom split
            for (uint256 i = 0; i < split.beneficiaries.length; i++) {
                address beneficiary = split.beneficiaries[i];
                uint256 amount = (pending * split.percentages[i]) / 10000;

                _transfer(beneficiary, amount);
                distributedTo[tokenId][beneficiary] += amount;

                emit RoyaltyDistributed(tokenId, beneficiary, amount);

                // Update reputation for all beneficiaries
                reputationScore.addEarnings(beneficiary, amount);
            }
        }
    }

    /**
     * @dev Simulate detection and payment (for PoC demo)
     * @param tokenId The music NFT token ID
     * @param platform Platform name
     */
    function simulateDetectionPayment(uint256 tokenId, string memory platform) external payable {
        require(msg.value > 0, "Payment must be > 0");

        // Verify music exists
        (bool exists,,) = musicRegistry.verifyFingerprint(_getTokenFingerprint(tokenId));
        require(exists, "Music not found or inactive");

        // Add to pending royalties
        pendingRoyalties[tokenId] += msg.value;
        totalEarnings[tokenId] += msg.value;

        emit RoyaltyReceived(tokenId, msg.sender, msg.value, platform, "simulated_usage");
    }

    /**
     * @dev Get royalty split configuration for a token
     * @param tokenId The music NFT token ID
     * @return beneficiaries Array of beneficiary addresses
     * @return percentages Array of percentages
     * @return isConfigured Whether split is configured
     */
    function getRoyaltySplit(uint256 tokenId)
        external
        view
        returns (address[] memory beneficiaries, uint256[] memory percentages, bool isConfigured)
    {
        RoyaltySplit memory split = _royaltySplits[tokenId];
        return (split.beneficiaries, split.percentages, split.isConfigured);
    }

    /**
     * @dev Get pending royalties for a token
     * @param tokenId The music NFT token ID
     * @return amount Pending royalty amount
     */
    function getPendingRoyalties(uint256 tokenId) external view returns (uint256) {
        return pendingRoyalties[tokenId];
    }

    /**
     * @dev Internal transfer function
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _transfer(address to, uint256 amount) private {
        require(to != address(0), "Invalid recipient");
        (bool success,) = payable(to).call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Helper to get fingerprint for a token (mock for PoC)
     * @param tokenId The token ID
     * @return Fingerprint hash
     */
    function _getTokenFingerprint(uint256 tokenId) private view returns (bytes32) {
        MusicRegistry.MusicMetadata memory metadata = musicRegistry.getMusicMetadata(tokenId);
        return metadata.fingerprintHash;
    }

    /**
     * @dev Update platform fee recipient (only owner)
     * @param newRecipient New recipient address
     */
    function updatePlatformFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid address");
        platformFeeRecipient = newRecipient;
    }

    /**
     * @dev Get total earnings for a token
     * @param tokenId The music NFT token ID
     * @return Total earnings
     */
    function getTotalEarnings(uint256 tokenId) external view returns (uint256) {
        return totalEarnings[tokenId];
    }

    /**
     * @dev Get amount distributed to a beneficiary for a token
     * @param tokenId The music NFT token ID
     * @param beneficiary The beneficiary address
     * @return Distributed amount
     */
    function getDistributedAmount(uint256 tokenId, address beneficiary) external view returns (uint256) {
        return distributedTo[tokenId][beneficiary];
    }

    receive() external payable {}
}
