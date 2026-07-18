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
| HyperEVM Testnet | MatchweekFactory | [`0x6a88384571dc18e104a54cdf2ae4fac02f29e0ec`](https://testnet.hyperscan.com/address/0x6a88384571dc18e104a54cdf2ae4fac02f29e0ec) |
| HyperEVM Testnet | FaucetStablecoin (mUSDC) | [`0xb7ea5484adf800c8ae7c27e2751ce0ba00230172`](https://testnet.hyperscan.com/address/0xb7ea5484adf800c8ae7c27e2751ce0ba00230172) |
| — | TBD | TBD |
| — | TBD | TBD |
 
---
 
## License

Business Source License — see [LICENSE](LICENSE)

The protocol is source-available. Use in test and development environments is freely permitted. Production use requires a separate license from PitchMkt. The license converts to GPL v3 four years after mainnet deployment.

