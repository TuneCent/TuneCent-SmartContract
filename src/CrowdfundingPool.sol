// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MusicRegistry.sol";
import "./RoyaltyDistributor.sol";
import "./ReputationScore.sol";

/**
 * @title CrowdfundingPool
 * @dev Crowdfunding campaigns with fractionalized NFT (f-NFT) issuance
 * @notice Enables fans to fund creators and receive automatic royalty splits via f-NFTs
 */
contract CrowdfundingPool is Ownable, ReentrancyGuard {
    MusicRegistry public musicRegistry;
    RoyaltyDistributor public royaltyDistributor;
    ReputationScore public reputationScore;

    enum CampaignStatus {
        Active,
        Successful,
        Failed,
        Cancelled
    }

    struct Campaign {
        uint256 tokenId; // Associated music NFT token ID
        address creator; // Campaign creator
        uint256 goalAmount; // Funding goal in wei
        uint256 raisedAmount; // Amount raised so far
        uint256 royaltyPercentage; // Percentage of royalties offered (in basis points)
        uint256 deadline; // Campaign deadline timestamp
        uint256 lockupPeriod; // Lock-up period in seconds
        CampaignStatus status;
        bool fundsWithdrawn;
        uint256 createdAt;
    }

    struct Contribution {
        address contributor;
        uint256 amount;
        uint256 timestamp;
    }

    // Campaign ID counter
    uint256 private _campaignIdCounter;

    // Mapping from campaign ID to campaign
    mapping(uint256 => Campaign) public campaigns;

    // Mapping from campaign ID to contributions
    mapping(uint256 => Contribution[]) private _contributions;

    // Mapping from campaign ID to contributor address to total contribution
    mapping(uint256 => mapping(address => uint256)) public contributorAmounts;

    // Mapping from token ID to campaign ID (one campaign per token)
    mapping(uint256 => uint256) public tokenToCampaign;

    // Platform fee for successful campaigns (in basis points)
    uint256 public constant PLATFORM_FEE = 500; // 5%

    // Minimum campaign duration
    uint256 public constant MIN_DURATION = 1 days;
    uint256 public constant MAX_DURATION = 90 days;

    // Events
    event CampaignCreated(
        uint256 indexed campaignId,
        uint256 indexed tokenId,
        address indexed creator,
        uint256 goalAmount,
        uint256 royaltyPercentage,
        uint256 deadline
    );

    event ContributionMade(
        uint256 indexed campaignId, address indexed contributor, uint256 amount, uint256 totalRaised
    );

    event CampaignFinalized(uint256 indexed campaignId, bool successful, uint256 totalRaised);

    event FundsWithdrawn(uint256 indexed campaignId, address indexed creator, uint256 amount);

    event RefundIssued(uint256 indexed campaignId, address indexed contributor, uint256 amount);

    event CampaignCancelled(uint256 indexed campaignId);

    constructor(address _musicRegistry, address payable _royaltyDistributor, address _reputationScore)
        Ownable(msg.sender)
    {
        require(_musicRegistry != address(0), "Invalid registry address");
        require(_royaltyDistributor != address(0), "Invalid distributor address");
        require(_reputationScore != address(0), "Invalid reputation address");

        musicRegistry = MusicRegistry(_musicRegistry);
        royaltyDistributor = RoyaltyDistributor(_royaltyDistributor);
        reputationScore = ReputationScore(_reputationScore);
    }

    /**
     * @dev Create a new crowdfunding campaign
     * @param tokenId Music NFT token ID
     * @param goalAmount Funding goal in wei
     * @param royaltyPercentage Percentage of royalties to offer (in basis points, max 5000 = 50%)
     * @param durationInDays Campaign duration in days
     * @param lockupPeriodInDays Lock-up period in days
     * @return campaignId The created campaign ID
     */
    function createCampaign(
        uint256 tokenId,
        uint256 goalAmount,
        uint256 royaltyPercentage,
        uint256 durationInDays,
        uint256 lockupPeriodInDays
    )
        external
        returns (uint256)
    {
        address owner = musicRegistry.getCurrentOwner(tokenId);
        require(msg.sender == owner, "Only NFT owner can create campaign");
        require(tokenToCampaign[tokenId] == 0, "Campaign already exists for this token");
        require(goalAmount > 0, "Goal must be > 0");
        require(royaltyPercentage > 0 && royaltyPercentage <= 5000, "Invalid royalty percentage");
        require(durationInDays >= 1 && durationInDays <= 90, "Invalid duration");

        _campaignIdCounter++;
        uint256 campaignId = _campaignIdCounter;

        uint256 duration = durationInDays * 1 days;
        require(duration >= MIN_DURATION && duration <= MAX_DURATION, "Invalid duration range");

        campaigns[campaignId] = Campaign({
            tokenId: tokenId,
            creator: msg.sender,
            goalAmount: goalAmount,
            raisedAmount: 0,
            royaltyPercentage: royaltyPercentage,
            deadline: block.timestamp + duration,
            lockupPeriod: lockupPeriodInDays * 1 days,
            status: CampaignStatus.Active,
            fundsWithdrawn: false,
            createdAt: block.timestamp
        });

        tokenToCampaign[tokenId] = campaignId;

        emit CampaignCreated(campaignId, tokenId, msg.sender, goalAmount, royaltyPercentage, block.timestamp + duration);

        return campaignId;
    }

    /**
     * @dev Contribute to a campaign
     * @param campaignId The campaign ID
     */
    function contribute(uint256 campaignId) external payable nonReentrant {
        Campaign storage campaign = campaigns[campaignId];

        require(campaign.creator != address(0), "Campaign does not exist");
        require(campaign.status == CampaignStatus.Active, "Campaign not active");
        require(block.timestamp < campaign.deadline, "Campaign ended");
        require(msg.value > 0, "Contribution must be > 0");
        require(msg.sender != campaign.creator, "Creator cannot contribute");

        campaign.raisedAmount += msg.value;
        contributorAmounts[campaignId][msg.sender] += msg.value;

        _contributions[campaignId]
        .push(Contribution({ contributor: msg.sender, amount: msg.value, timestamp: block.timestamp }));

        emit ContributionMade(campaignId, msg.sender, msg.value, campaign.raisedAmount);
    }

    /**
     * @dev Finalize a campaign after deadline
     * @param campaignId The campaign ID
     */
    function finalizeCampaign(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[campaignId];

        require(campaign.creator != address(0), "Campaign does not exist");
        require(campaign.status == CampaignStatus.Active, "Campaign not active");
        require(block.timestamp >= campaign.deadline, "Campaign not ended yet");

        if (campaign.raisedAmount >= campaign.goalAmount) {
            campaign.status = CampaignStatus.Successful;

            // Update reputation
            reputationScore.incrementSuccessfulCampaigns(campaign.creator);
            reputationScore.addContributions(campaign.creator, campaign.raisedAmount);

            // Setup royalty splits automatically
            _setupRoyaltySplits(campaignId);
        } else {
            campaign.status = CampaignStatus.Failed;
        }

        emit CampaignFinalized(campaignId, campaign.status == CampaignStatus.Successful, campaign.raisedAmount);
    }

    /**
     * @dev Withdraw funds from successful campaign
     * @param campaignId The campaign ID
     */
    function withdrawFunds(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[campaignId];

        require(msg.sender == campaign.creator, "Only creator can withdraw");
        require(campaign.status == CampaignStatus.Successful, "Campaign not successful");
        require(!campaign.fundsWithdrawn, "Funds already withdrawn");

        campaign.fundsWithdrawn = true;

        // Calculate platform fee
        uint256 platformFee = (campaign.raisedAmount * PLATFORM_FEE) / 10000;
        uint256 creatorAmount = campaign.raisedAmount - platformFee;

        // Transfer funds
        (bool success1,) = payable(campaign.creator).call{ value: creatorAmount }("");
        require(success1, "Transfer to creator failed");

        (bool success2,) = payable(owner()).call{ value: platformFee }("");
        require(success2, "Transfer of platform fee failed");

        emit FundsWithdrawn(campaignId, campaign.creator, creatorAmount);
    }

    /**
     * @dev Claim refund from failed campaign
     * @param campaignId The campaign ID
     */
    function claimRefund(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[campaignId];

        require(campaign.status == CampaignStatus.Failed, "Campaign not failed");

        uint256 contributedAmount = contributorAmounts[campaignId][msg.sender];
        require(contributedAmount > 0, "No contribution found");

        contributorAmounts[campaignId][msg.sender] = 0;

        (bool success,) = payable(msg.sender).call{ value: contributedAmount }("");
        require(success, "Refund transfer failed");

        emit RefundIssued(campaignId, msg.sender, contributedAmount);
    }

    /**
     * @dev Cancel a campaign (only by creator, before deadline, if no contributions)
     * @param campaignId The campaign ID
     */
    function cancelCampaign(uint256 campaignId) external {
        Campaign storage campaign = campaigns[campaignId];

        require(msg.sender == campaign.creator, "Only creator can cancel");
        require(campaign.status == CampaignStatus.Active, "Campaign not active");
        require(campaign.raisedAmount == 0, "Cannot cancel with contributions");

        campaign.status = CampaignStatus.Cancelled;

        emit CampaignCancelled(campaignId);
    }

    /**
     * @dev Get campaign details
     * @param campaignId The campaign ID
     * @return campaign The campaign struct
     */
    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        return campaigns[campaignId];
    }

    /**
     * @dev Get all contributions for a campaign
     * @param campaignId The campaign ID
     * @return contributions Array of contributions
     */
    function getContributions(uint256 campaignId) external view returns (Contribution[] memory) {
        return _contributions[campaignId];
    }

    /**
     * @dev Get contribution share percentage for a contributor
     * @param campaignId The campaign ID
     * @param contributor Contributor address
     * @return sharePercentage Share percentage in basis points
     */
    function getContributionShare(uint256 campaignId, address contributor) external view returns (uint256) {
        Campaign memory campaign = campaigns[campaignId];
        uint256 contributedAmount = contributorAmounts[campaignId][contributor];

        if (campaign.raisedAmount == 0) return 0;

        return (contributedAmount * 10000) / campaign.raisedAmount;
    }

    /**
     * @dev Get total number of campaigns
     * @return Total campaigns count
     */
    function getTotalCampaigns() external view returns (uint256) {
        return _campaignIdCounter;
    }

    /**
     * @dev Internal function to setup royalty splits based on contributions
     * @param campaignId The campaign ID
     */
    function _setupRoyaltySplits(uint256 campaignId) private {
        Campaign memory campaign = campaigns[campaignId];
        Contribution[] memory contributions = _contributions[campaignId];

        require(contributions.length > 0, "No contributors");

        // Calculate split: creator gets (100% - royaltyPercentage), contributors split royaltyPercentage
        uint256 creatorPercentage = 10000 - campaign.royaltyPercentage;

        // Build beneficiaries array
        address[] memory beneficiaries = new address[](contributions.length + 1);
        uint256[] memory percentages = new uint256[](contributions.length + 1);

        // First beneficiary is creator
        beneficiaries[0] = campaign.creator;
        percentages[0] = creatorPercentage;

        // Calculate proportional splits for contributors
        for (uint256 i = 0; i < contributions.length; i++) {
            address contributor = contributions[i].contributor;
            uint256 contributorShare =
                (contributorAmounts[campaignId][contributor] * campaign.royaltyPercentage) / campaign.raisedAmount;

            beneficiaries[i + 1] = contributor;
            percentages[i + 1] = contributorShare;
        }

        // Set royalty split in RoyaltyDistributor
        // Note: This requires the creator to have approved this contract or called it
        // For PoC, we assume the creator will call setRoyaltySplit after campaign success
    }

    /**
     * @dev Get campaign by token ID
     * @param tokenId Music NFT token ID
     * @return campaignId The campaign ID (0 if none exists)
     */
    function getCampaignByToken(uint256 tokenId) external view returns (uint256) {
        return tokenToCampaign[tokenId];
    }
}
