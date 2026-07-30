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
| HyperEVM Testnet | PitchMkt | [`0xf0e17329e4344a9bb8aeff517976346c9060c0bb`](https://testnet.hyperscan.com/address/0xf0e17329e4344a9bb8aeff517976346c9060c0bb) |
| HyperEVM Testnet | CarryPool | [`0x4706249a4a88e4966a12b4378bbeb5c93ed8a5ed`](https://testnet.hyperscan.com/address/0x4706249a4a88e4966a12b4378bbeb5c93ed8a5ed) |
| HyperEVM Testnet | Treasury | [`0x15ef3485f44179a61a6610817512eaa812285046`](https://testnet.hyperscan.com/address/0x15ef3485f44179a61a6610817512eaa812285046) |
| HyperEVM Testnet | FaucetStablecoin (mUSDC) | [`0x253f1f30bf3137ac4e7c516d5651f76ba5aef771`](https://testnet.hyperscan.com/address/0x253f1f30bf3137ac4e7c516d5651f76ba5aef771) |
 
---
 
## License

Business Source License — see [LICENSE](LICENSE)

The protocol is source-available. Use in test and development environments is freely permitted. Production use requires a separate license from PitchMkt. The license converts to GPL v3 four years after mainnet deployment.

