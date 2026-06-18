.PHONY: anvil deploy-local build test clean

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

# Deploy MatchweekFactory to local Anvil using a named keystore account
deploy-local: build
	forge script script/MatchweekFactory.s.sol:MatchweekFactoryScript \
		--rpc-url $(chain) \
		--account $(account) \
		--broadcast \
		-vvvv

clean:
	forge clean
