.PHONY: anvil deploy-local deploy-hyperevm-testnet build test clean

-include .env

# Start a local Anvil node
anvil:
	anvil

# Build contracts
build:
	forge build

# Run tests
test:
	forge test -vv

# Deploy PitchMkt to local Anvil using a named keystore account
deploy-local: build
	forge script script/PitchMkt.s.sol:PitchMktScript \
		--rpc-url anvil \
		--account $(account) \
		--broadcast \
		-vvvv

# Deploy PitchMkt to HyperEVM Testnet using a named keystore account
deploy-hyperevm-testnet: build
	forge script script/PitchMkt.s.sol:PitchMktScript \
		--rpc-url hyperevm_testnet \
		--account $(account) \
		--broadcast \
		-vvvv

clean:
	forge clean
