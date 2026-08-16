# PitchMkt Protocol
 
Decentralised football prediction markets on-chain. Users stake stablecoins, predict ten match outcomes, and compete for proportional payouts from a shared prize pool.
 
---

# Getting Started
 
### Prerequisites
 
- Node.js 18+
- [Foundry](https://book.getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash`
- A funded wallet for deployment
### Install
 
```bash
git clone https://github.com/pitchmkt/protocol
cd protocol
forge install
```
 
### Compile
 
```bash
forge build
```
 
### Test
 
```bash
forge test
```

Run with verbosity for gas reporting:
 
```bash
forge test -vvv --gas-report
```

---
 
## Contract Addresses
 
| Network | Contract | Address |
|---|---|---|
| HyperEVM Testnet | PitchMkt | [`0xec06bb490764488b6d8a4c5d81674198016586a8`](https://testnet.hyperscan.com/address/0xec06bb490764488b6d8a4c5d81674198016586a8) |
| HyperEVM Testnet | CarryPool | [`0xad4d2692d15f9cea0b4e5880668a5329c6fd79d9`](https://testnet.hyperscan.com/address/0xad4d2692d15f9cea0b4e5880668a5329c6fd79d9) |
| HyperEVM Testnet | Treasury | [`0x8e60099712fd21206e2ea491d8bdf77dd3d7b03c`](https://testnet.hyperscan.com/address/0x8e60099712fd21206e2ea491d8bdf77dd3d7b03c) |
| HyperEVM Testnet | Disputes | [`0xd69cff5ecca7f42ee8c53ba4750b44f4b5039d73`](https://testnet.hyperscan.com/address/0xd69cff5ecca7f42ee8c53ba4750b44f4b5039d73) |
| HyperEVM Testnet | FaucetStablecoin (mUSDC) | [`0xe9cffc7b62549b8a1bcf564c625a44c82c449b0e`](https://testnet.hyperscan.com/address/0xe9cffc7b62549b8a1bcf564c625a44c82c449b0e) |
 
---
 
## License

Business Source License — see [LICENSE](LICENSE)

The protocol is source-available. Use in test and development environments is freely permitted. Production use requires a separate license from PitchMkt. The license converts to GPL v3 four years after mainnet deployment.

