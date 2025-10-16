// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ReputationScore
 * @dev On-chain reputation and social credit system for creators
 * @notice Tracks creator performance metrics and builds long-term reputation moat
 */
contract ReputationScore is Ownable {
    struct CreatorStats {
        uint256 totalWorks;           // Number of registered works
        uint256 totalEarnings;         // Lifetime earnings in wei
        uint256 totalContributions;    // Amount received from crowdfunding
        uint256 successfulCampaigns;   // Number of successful crowdfunding campaigns
        uint256 reputationScore;       // Calculated reputation score (0-10000)
        uint256 lastUpdated;           // Last update timestamp
        bool isVerified;               // Verification status
    }

    // Mapping from creator address to stats
    mapping(address => CreatorStats) private _creatorStats;

    // Authorized contracts that can update reputation
    mapping(address => bool) public authorizedUpdaters;

    // Reputation calculation weights
    uint256 public constant WORKS_WEIGHT = 1000;        // 10%
    uint256 public constant EARNINGS_WEIGHT = 4000;      // 40%
    uint256 public constant CONTRIBUTIONS_WEIGHT = 3000; // 30%
    uint256 public constant CAMPAIGNS_WEIGHT = 2000;     // 20%

    // Scaling factors for calculations
    uint256 public constant EARNINGS_SCALE = 1 ether;
    uint256 public constant MAX_SCORE = 10000;

    // Events
    event ReputationUpdated(
        address indexed creator,
        uint256 newScore,
        uint256 totalWorks,
        uint256 totalEarnings
    );

    event CreatorVerified(address indexed creator);
    event CreatorUnverified(address indexed creator);
    event UpdaterAuthorized(address indexed updater);
    event UpdaterRevoked(address indexed updater);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Authorize a contract to update reputation
     * @param updater Address of the updater contract
     */
    function authorizeUpdater(address updater) external onlyOwner {
        require(updater != address(0), "Invalid updater address");
        authorizedUpdaters[updater] = true;
        emit UpdaterAuthorized(updater);
    }

    /**
     * @dev Revoke updater authorization
     * @param updater Address of the updater contract
     */
    function revokeUpdater(address updater) external onlyOwner {
        authorizedUpdaters[updater] = false;
        emit UpdaterRevoked(updater);
    }

    modifier onlyAuthorized() {
        require(
            authorizedUpdaters[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    /**
     * @dev Increment works count for a creator
     * @param creator Creator address
     */
    function incrementWorks(address creator) external onlyAuthorized {
        require(creator != address(0), "Invalid creator");

        _creatorStats[creator].totalWorks += 1;
        _creatorStats[creator].lastUpdated = block.timestamp;

        _recalculateScore(creator);
    }

    /**
     * @dev Add earnings to creator stats
     * @param creator Creator address
     * @param amount Earnings amount in wei
     */
    function addEarnings(address creator, uint256 amount) external onlyAuthorized {
        require(creator != address(0), "Invalid creator");
        require(amount > 0, "Amount must be > 0");

        _creatorStats[creator].totalEarnings += amount;
        _creatorStats[creator].lastUpdated = block.timestamp;

        _recalculateScore(creator);
    }

    /**
     * @dev Add crowdfunding contributions to creator stats
     * @param creator Creator address
     * @param amount Contribution amount
     */
    function addContributions(address creator, uint256 amount) external onlyAuthorized {
        require(creator != address(0), "Invalid creator");
        require(amount > 0, "Amount must be > 0");

        _creatorStats[creator].totalContributions += amount;
        _creatorStats[creator].lastUpdated = block.timestamp;

        _recalculateScore(creator);
    }

    /**
     * @dev Increment successful campaigns count
     * @param creator Creator address
     */
    function incrementSuccessfulCampaigns(address creator) external onlyAuthorized {
        require(creator != address(0), "Invalid creator");

        _creatorStats[creator].successfulCampaigns += 1;
        _creatorStats[creator].lastUpdated = block.timestamp;

        _recalculateScore(creator);
    }

    /**
     * @dev Verify a creator (manual verification by platform)
     * @param creator Creator address
     */
    function verifyCreator(address creator) external onlyOwner {
        require(creator != address(0), "Invalid creator");
        _creatorStats[creator].isVerified = true;
        emit CreatorVerified(creator);
    }

    /**
     * @dev Unverify a creator
     * @param creator Creator address
     */
    function unverifyCreator(address creator) external onlyOwner {
        require(creator != address(0), "Invalid creator");
        _creatorStats[creator].isVerified = false;
        emit CreatorUnverified(creator);
    }

    /**
     * @dev Get creator stats
     * @param creator Creator address
     * @return stats Creator statistics
     */
    function getCreatorStats(address creator)
        external
        view
        returns (CreatorStats memory)
    {
        return _creatorStats[creator];
    }

    /**
     * @dev Get reputation score for a creator
     * @param creator Creator address
     * @return score Reputation score (0-10000)
     */
    function getReputationScore(address creator) external view returns (uint256) {
        return _creatorStats[creator].reputationScore;
    }

    /**
     * @dev Check if creator is verified
     * @param creator Creator address
     * @return verified Verification status
     */
    function isCreatorVerified(address creator) external view returns (bool) {
        return _creatorStats[creator].isVerified;
    }

    /**
     * @dev Internal function to recalculate reputation score
     * @param creator Creator address
     */
    function _recalculateScore(address creator) private {
        CreatorStats storage stats = _creatorStats[creator];

        // Calculate component scores (each 0-10000)
        uint256 worksScore = _calculateWorksScore(stats.totalWorks);
        uint256 earningsScore = _calculateEarningsScore(stats.totalEarnings);
        uint256 contributionsScore = _calculateContributionsScore(stats.totalContributions);
        uint256 campaignsScore = _calculateCampaignsScore(stats.successfulCampaigns);

        // Weighted average
        uint256 newScore = (
            (worksScore * WORKS_WEIGHT) +
            (earningsScore * EARNINGS_WEIGHT) +
            (contributionsScore * CONTRIBUTIONS_WEIGHT) +
            (campaignsScore * CAMPAIGNS_WEIGHT)
        ) / MAX_SCORE;

        // Cap at MAX_SCORE
        if (newScore > MAX_SCORE) {
            newScore = MAX_SCORE;
        }

        stats.reputationScore = newScore;

        emit ReputationUpdated(
            creator,
            newScore,
            stats.totalWorks,
            stats.totalEarnings
        );
    }

    /**
     * @dev Calculate score based on number of works
     * @param works Number of registered works
     * @return score Score (0-10000)
     */
    function _calculateWorksScore(uint256 works) private pure returns (uint256) {
        if (works == 0) return 0;
        if (works >= 50) return MAX_SCORE;

        // Linear scale: 1 work = 200 points, 50 works = 10000 points
        return works * 200;
    }

    /**
     * @dev Calculate score based on earnings
     * @param earnings Total earnings in wei
     * @return score Score (0-10000)
     */
    function _calculateEarningsScore(uint256 earnings) private pure returns (uint256) {
        if (earnings == 0) return 0;

        // Scale: 10 ETH = max score
        uint256 scaledEarnings = (earnings * MAX_SCORE) / (10 * EARNINGS_SCALE);

        return scaledEarnings > MAX_SCORE ? MAX_SCORE : scaledEarnings;
    }

    /**
     * @dev Calculate score based on crowdfunding contributions
     * @param contributions Total contributions received
     * @return score Score (0-10000)
     */
    function _calculateContributionsScore(uint256 contributions) private pure returns (uint256) {
        if (contributions == 0) return 0;

        // Scale: 5 ETH = max score
        uint256 scaledContributions = (contributions * MAX_SCORE) / (5 * EARNINGS_SCALE);

        return scaledContributions > MAX_SCORE ? MAX_SCORE : scaledContributions;
    }

    /**
     * @dev Calculate score based on successful campaigns
     * @param campaigns Number of successful campaigns
     * @return score Score (0-10000)
     */
    function _calculateCampaignsScore(uint256 campaigns) private pure returns (uint256) {
        if (campaigns == 0) return 0;
        if (campaigns >= 20) return MAX_SCORE;

        // Linear scale: 1 campaign = 500 points, 20 campaigns = 10000 points
        return campaigns * 500;
    }

    /**
     * @dev Get detailed score breakdown
     * @param creator Creator address
     * @return works Works score
     * @return earnings Earnings score
     * @return contributions Contributions score
     * @return campaigns Campaigns score
     */
    function getScoreBreakdown(address creator)
        external
        view
        returns (
            uint256 works,
            uint256 earnings,
            uint256 contributions,
            uint256 campaigns
        )
    {
        CreatorStats memory stats = _creatorStats[creator];

        return (
            _calculateWorksScore(stats.totalWorks),
            _calculateEarningsScore(stats.totalEarnings),
            _calculateContributionsScore(stats.totalContributions),
            _calculateCampaignsScore(stats.successfulCampaigns)
        );
    }
}
