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
| HyperEVM Testnet | PitchMkt | [`0xc9f7cfa514605885d54fe9eebcd7041e73642be2`](https://testnet.hyperscan.com/address/0xc9f7cfa514605885d54fe9eebcd7041e73642be2) |
| HyperEVM Testnet | CarryPool | [`0xd6647c25d1ee7d2b490d241fc4edc01ea734641b`](https://testnet.hyperscan.com/address/0xd6647c25d1ee7d2b490d241fc4edc01ea734641b) |
| HyperEVM Testnet | Treasury | [`0x109c78851e527735527da36c72f4cfb1a916048a`](https://testnet.hyperscan.com/address/0x109c78851e527735527da36c72f4cfb1a916048a) |
| HyperEVM Testnet | FaucetStablecoin (mUSDC) | [`0x96acd1d869bad950da299bad61b9112e8fa60c4d`](https://testnet.hyperscan.com/address/0x96acd1d869bad950da299bad61b9112e8fa60c4d) |
 
---
 
## License

Business Source License — see [LICENSE](LICENSE)

The protocol is source-available. Use in test and development environments is freely permitted. Production use requires a separate license from PitchMkt. The license converts to GPL v3 four years after mainnet deployment.

