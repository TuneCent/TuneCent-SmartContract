# TuneCent Deployment - Base Sepolia

Deployed at: 2025-10-20
Deployer: `0x07Db16E72c7f94bB4F15A1AcADb9867620655931`

## Contract Addresses

- **MusicRegistry**: `0x6c7Cf1D78367f8C1F1DB070A6eF6863b61274918`
- **ReputationScore**: `0x86726e6f1a3f8144A13Df876443D053bccFC3522`
- **RoyaltyDistributor**: `0x2bdF2586b1177C1d94950f1bB844C92AFaDE9E2a`
- **CrowdfundingPool**: `0x5cfaFa45653e3957EC4b10E03AEE2E42CA0E0E74`

## Verification Commands

```bash
# MusicRegistry
forge verify-contract 0x6c7Cf1D78367f8C1F1DB070A6eF6863b61274918 src/MusicRegistry.sol:MusicRegistry --chain base-sepolia

# ReputationScore
forge verify-contract 0x86726e6f1a3f8144A13Df876443D053bccFC3522 src/ReputationScore.sol:ReputationScore --chain base-sepolia

# RoyaltyDistributor
forge verify-contract 0x2bdF2586b1177C1d94950f1bB844C92AFaDE9E2a src/RoyaltyDistributor.sol:RoyaltyDistributor --chain base-sepolia --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x6c7Cf1D78367f8C1F1DB070A6eF6863b61274918 0x86726e6f1a3f8144A13Df876443D053bccFC3522 0x07Db16E72c7f94bB4F15A1AcADb9867620655931)

# CrowdfundingPool
forge verify-contract 0x5cfaFa45653e3957EC4b10E03AEE2E42CA0E0E74 src/CrowdfundingPool.sol:CrowdfundingPool --chain base-sepolia --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x6c7Cf1D78367f8C1F1DB070A6eF6863b61274918 0x2bdF2586b1177C1d94950f1bB844C92AFaDE9E2a 0x86726e6f1a3f8144A13Df876443D053bccFC3522)
```

## Block Explorer Links

- [MusicRegistry](https://sepolia.basescan.org/address/0x6c7Cf1D78367f8C1F1DB070A6eF6863b61274918)
- [ReputationScore](https://sepolia.basescan.org/address/0x86726e6f1a3f8144A13Df876443D053bccFC3522)
- [RoyaltyDistributor](https://sepolia.basescan.org/address/0x2bdF2586b1177C1d94950f1bB844C92AFaDE9E2a)
- [CrowdfundingPool](https://sepolia.basescan.org/address/0x5cfaFa45653e3957EC4b10E03AEE2E42CA0E0E74)

## Deployment Status

✅ All contracts deployed successfully
✅ Permissions configured:
  - MusicRegistry authorized to update reputation
  - RoyaltyDistributor authorized to update reputation
  - CrowdfundingPool authorized to update reputation

## Next Steps

1. Verify contracts on Basescan (run verification commands above)
2. Update frontend/backend with new contract addresses
3. Test the deployment with sample transactions
