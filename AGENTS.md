# AGENTS.md

## Protocol

PitchMkt is a decentralised football prediction market. Each matchday, users stake stablecoins and predict the outcome of ten matches (home win / draw / away win). Entries accumulate into a shared prize pool distributed proportionally to capital staked across accuracy tiers (6–10 correct predictions). A separate jackpot pool grows until someone hits a perfect ten.

---

## Solidity Best Practices

### Security

- Follow checks-effects-interactions: validate, update state, then call external contracts.
- Use `ReentrancyGuard` on any function that transfers value or calls untrusted contracts.
- Avoid unbounded loops over user-supplied arrays — cap iteration or use pull-over-push patterns.

### Testing

- One contract per test file; name it `ContractName.t.sol`.
- Use `setUp()` to deploy fresh contracts before each test — never share state between tests.
- Name tests `test_<scenario>` (happy path) and `testRevert_<reason>` (failure cases).progression.
