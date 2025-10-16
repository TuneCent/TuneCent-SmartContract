// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/MusicRegistry.sol";
import "../src/RoyaltyDistributor.sol";
import "../src/ReputationScore.sol";
import "../src/CrowdfundingPool.sol";

/**
 * @title Deploy Script for TuneCent
 * @notice Deploys all TuneCent contracts to Base Sepolia
 *
 * Usage:
 * forge script script/Deploy.s.sol:DeployScript --rpc-url base_sepolia --broadcast --verify
 */
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy MusicRegistry
        console.log("\n1. Deploying MusicRegistry...");
        MusicRegistry musicRegistry = new MusicRegistry();
        console.log("MusicRegistry deployed at:", address(musicRegistry));

        // 2. Deploy ReputationScore
        console.log("\n2. Deploying ReputationScore...");
        ReputationScore reputationScore = new ReputationScore();
        console.log("ReputationScore deployed at:", address(reputationScore));

        // 3. Deploy RoyaltyDistributor
        console.log("\n3. Deploying RoyaltyDistributor...");
        RoyaltyDistributor royaltyDistributor = new RoyaltyDistributor(
            address(musicRegistry),
            address(reputationScore),
            deployer // Platform fee recipient (can be changed later)
        );
        console.log("RoyaltyDistributor deployed at:", address(royaltyDistributor));

        // 4. Deploy CrowdfundingPool
        console.log("\n4. Deploying CrowdfundingPool...");
        CrowdfundingPool crowdfundingPool =
            new CrowdfundingPool(address(musicRegistry), payable(address(royaltyDistributor)), address(reputationScore));
        console.log("CrowdfundingPool deployed at:", address(crowdfundingPool));

        // 5. Configure contract permissions
        console.log("\n5. Configuring permissions...");

        // Authorize contracts to update reputation
        reputationScore.authorizeUpdater(address(musicRegistry));
        console.log("- Authorized MusicRegistry to update reputation");

        reputationScore.authorizeUpdater(address(royaltyDistributor));
        console.log("- Authorized RoyaltyDistributor to update reputation");

        reputationScore.authorizeUpdater(address(crowdfundingPool));
        console.log("- Authorized CrowdfundingPool to update reputation");

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n============================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("============================================");
        console.log("Network: Base Sepolia");
        console.log("Deployer:", deployer);
        console.log("");
        console.log("Contract Addresses:");
        console.log("-------------------------------------------");
        console.log("MusicRegistry:      ", address(musicRegistry));
        console.log("ReputationScore:    ", address(reputationScore));
        console.log("RoyaltyDistributor: ", address(royaltyDistributor));
        console.log("CrowdfundingPool:   ", address(crowdfundingPool));
        console.log("============================================\n");

        // Save deployment info to file
        string memory deploymentInfo = string(
            abi.encodePacked(
                "# TuneCent Deployment - Base Sepolia\n\n",
                "Deployed at: ",
                vm.toString(block.timestamp),
                "\n",
                "Deployer: ",
                vm.toString(deployer),
                "\n\n",
                "## Contract Addresses\n\n",
                "- **MusicRegistry**: `",
                vm.toString(address(musicRegistry)),
                "`\n",
                "- **ReputationScore**: `",
                vm.toString(address(reputationScore)),
                "`\n",
                "- **RoyaltyDistributor**: `",
                vm.toString(address(royaltyDistributor)),
                "`\n",
                "- **CrowdfundingPool**: `",
                vm.toString(address(crowdfundingPool)),
                "`\n\n",
                "## Verification Commands\n\n",
                "```bash\n",
                "forge verify-contract ",
                vm.toString(address(musicRegistry)),
                " src/MusicRegistry.sol:MusicRegistry --chain base-sepolia\n",
                "forge verify-contract ",
                vm.toString(address(reputationScore)),
                " src/ReputationScore.sol:ReputationScore --chain base-sepolia\n",
                "forge verify-contract ",
                vm.toString(address(royaltyDistributor)),
                " src/RoyaltyDistributor.sol:RoyaltyDistributor --chain base-sepolia --constructor-args $(cast abi-encode \"constructor(address,address,address)\" ",
                vm.toString(address(musicRegistry)),
                " ",
                vm.toString(address(reputationScore)),
                " ",
                vm.toString(deployer),
                ")\n",
                "forge verify-contract ",
                vm.toString(address(crowdfundingPool)),
                " src/CrowdfundingPool.sol:CrowdfundingPool --chain base-sepolia --constructor-args $(cast abi-encode \"constructor(address,address,address)\" ",
                vm.toString(address(musicRegistry)),
                " ",
                vm.toString(address(royaltyDistributor)),
                " ",
                vm.toString(address(reputationScore)),
                ")\n",
                "```\n"
            )
        );

        vm.writeFile("deployment-info.md", deploymentInfo);
        console.log("Deployment info saved to: deployment-info.md");
    }
}
