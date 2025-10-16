// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/MusicRegistry.sol";
import "../src/RoyaltyDistributor.sol";
import "../src/ReputationScore.sol";
import "../src/CrowdfundingPool.sol";

contract TuneCentIntegrationTest is Test {
    MusicRegistry public musicRegistry;
    RoyaltyDistributor public royaltyDistributor;
    ReputationScore public reputationScore;
    CrowdfundingPool public crowdfundingPool;

    address public creator = address(0x1);
    address public fan1 = address(0x2);
    address public fan2 = address(0x3);
    address public platform = address(0x4);
    address public platformFee = address(0x5);

    function setUp() public {
        // Deploy contracts
        musicRegistry = new MusicRegistry();
        reputationScore = new ReputationScore();
        royaltyDistributor = new RoyaltyDistributor(address(musicRegistry), address(reputationScore), platformFee);
        crowdfundingPool =
            new CrowdfundingPool(address(musicRegistry), payable(address(royaltyDistributor)), address(reputationScore));

        // Authorize contracts to update reputation
        reputationScore.authorizeUpdater(address(musicRegistry));
        reputationScore.authorizeUpdater(address(royaltyDistributor));
        reputationScore.authorizeUpdater(address(crowdfundingPool));

        // Fund test accounts
        vm.deal(creator, 100 ether);
        vm.deal(fan1, 10 ether);
        vm.deal(fan2, 10 ether);
        vm.deal(platform, 10 ether);
    }

    function testMusicRegistration() public {
        vm.startPrank(creator);

        string memory ipfsCID = "QmTest123";
        bytes32 fingerprint = keccak256("test_music_fingerprint");
        string memory title = "Test Song";
        string memory artist = "Test Artist";

        uint256 tokenId = musicRegistry.registerMusic(ipfsCID, fingerprint, title, artist);

        assertEq(tokenId, 1);
        assertEq(musicRegistry.ownerOf(tokenId), creator);

        MusicRegistry.MusicMetadata memory metadata = musicRegistry.getMusicMetadata(tokenId);
        assertEq(metadata.title, title);
        assertEq(metadata.artist, artist);
        assertTrue(metadata.isActive);

        vm.stopPrank();
    }

    function testRoyaltyPaymentAndDistribution() public {
        // First register music
        vm.startPrank(creator);
        bytes32 fingerprint = keccak256("test_music_2");
        uint256 tokenId = musicRegistry.registerMusic("QmTest456", fingerprint, "Song 2", "Artist 2");
        vm.stopPrank();

        // Platform pays royalty
        vm.startPrank(platform);
        royaltyDistributor.simulateDetectionPayment{value: 1 ether}(tokenId, "TikTok");
        vm.stopPrank();

        // Check pending royalties
        uint256 pending = royaltyDistributor.getPendingRoyalties(tokenId);
        assertEq(pending, 1 ether);

        // Distribute royalties
        uint256 creatorBalanceBefore = creator.balance;
        vm.startPrank(creator);
        royaltyDistributor.distributeRoyalties(tokenId);
        vm.stopPrank();

        // Creator should receive 90% (default split)
        uint256 creatorBalanceAfter = creator.balance;
        assertEq(creatorBalanceAfter - creatorBalanceBefore, 0.9 ether);

        // Check pending is now 0
        assertEq(royaltyDistributor.getPendingRoyalties(tokenId), 0);
    }

    function testCrowdfundingCampaign() public {
        // Register music first
        vm.startPrank(creator);
        bytes32 fingerprint = keccak256("test_music_3");
        uint256 tokenId = musicRegistry.registerMusic("QmTest789", fingerprint, "Song 3", "Artist 3");

        // Create campaign: 1 ETH goal, 20% royalty share, 7 days duration
        uint256 campaignId = crowdfundingPool.createCampaign(
            tokenId,
            1 ether, // goal
            2000, // 20% royalty
            7, // 7 days duration
            30 // 30 days lock-up
        );
        vm.stopPrank();

        assertEq(campaignId, 1);

        // Fans contribute
        vm.startPrank(fan1);
        crowdfundingPool.contribute{value: 0.6 ether}(campaignId);
        vm.stopPrank();

        vm.startPrank(fan2);
        crowdfundingPool.contribute{value: 0.4 ether}(campaignId);
        vm.stopPrank();

        CrowdfundingPool.Campaign memory campaign = crowdfundingPool.getCampaign(campaignId);
        assertEq(campaign.raisedAmount, 1 ether);
        assertEq(uint256(campaign.status), 0); // Active

        // Fast forward past deadline
        vm.warp(block.timestamp + 8 days);

        // Finalize campaign
        crowdfundingPool.finalizeCampaign(campaignId);

        campaign = crowdfundingPool.getCampaign(campaignId);
        assertEq(uint256(campaign.status), 1); // Successful

        // Creator withdraws funds
        uint256 creatorBalanceBefore = creator.balance;
        vm.startPrank(creator);
        crowdfundingPool.withdrawFunds(campaignId);
        vm.stopPrank();

        // Creator receives 95% (5% platform fee)
        uint256 creatorBalanceAfter = creator.balance;
        assertEq(creatorBalanceAfter - creatorBalanceBefore, 0.95 ether);
    }

    function testReputationScoreUpdate() public {
        vm.startPrank(creator);

        // Register multiple works
        for (uint256 i = 0; i < 3; i++) {
            bytes32 fingerprint = keccak256(abi.encodePacked("music_", i));
            musicRegistry.registerMusic(
                string(abi.encodePacked("QmTest", i)), fingerprint, string(abi.encodePacked("Song ", i)), "Artist"
            );
        }

        vm.stopPrank();

        // Check reputation updated
        ReputationScore.CreatorStats memory stats = reputationScore.getCreatorStats(creator);
        assertEq(stats.totalWorks, 0); // Not automatically updated in this PoC

        // Manually update for testing (in real scenario, MusicRegistry would call this)
        reputationScore.incrementWorks(creator);
        reputationScore.incrementWorks(creator);
        reputationScore.incrementWorks(creator);

        stats = reputationScore.getCreatorStats(creator);
        assertEq(stats.totalWorks, 3);
        assertTrue(stats.reputationScore > 0);
    }

    function test_RevertWhen_DoubleRegistration() public {
        vm.startPrank(creator);

        bytes32 fingerprint = keccak256("duplicate_test");

        musicRegistry.registerMusic("QmTest1", fingerprint, "Song 1", "Artist");

        // This should revert
        vm.expectRevert("Fingerprint already registered");
        musicRegistry.registerMusic("QmTest2", fingerprint, "Song 2", "Artist");

        vm.stopPrank();
    }
}
