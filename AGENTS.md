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
- Name tests `test_<scenario>` (happy path) and `testRevert_<reason>` (failure cases).

---

## Style Guide

Follows the [Solidity official style guide](https://docs.soliditylang.org/en/latest/style-guide.html).

### Code Layout

- **Indentation**: 4 spaces (no tabs).
- **Blank lines**: two blank lines between top-level declarations; one blank line between function declarations inside a contract.
- **Line length**: max 120 characters. When wrapping, each argument on its own line; closing `);` on its own line.
- **Encoding**: UTF-8.
- **Imports**: always at the top of the file, after pragma.
- **Braces**: open on the same line as the declaration, preceded by a single space; close at the same indentation level as the declaration.
- **Strings**: double-quotes only (`"foo"`, not `'foo'`).
- **Operators**: single space on each side. Higher-priority operators may omit spaces to show precedence (`x = 2**3 + 5`).
- **Mappings**: no space between `mapping` keyword and its type (`mapping(uint => uint)`).
- **Arrays**: no space between type and brackets (`uint[] x`).

### Order of Layout

At file level:

1. Pragma statements
2. Import statements
3. Events
4. Errors
5. Interfaces
6. Libraries
7. Contracts

Inside each contract:

1. Type declarations
2. State variables
3. Events
4. Errors
5. Modifiers
6. Functions

### Order of Functions

1. `constructor`
2. `receive` (if present)
3. `fallback` (if present)
4. `external`
5. `public`
6. `internal`
7. `private`

Within each visibility group, `view` and `pure` functions go last.

### Function Modifier Order

`visibility` → `mutability` → `virtual` → `override` → custom modifiers.

```solidity
function foo() public view override onlyOwner returns (uint) { ... }
```

### Naming Conventions

| Element | Style | Example |
|---|---|---|
| Contract, Library, Interface | `CapWords` | `PredictionMarket` |
| Struct, Enum | `CapWords` | `MatchOutcome`, `TierGroup` |
| Event | `CapWords` | `EntrySubmitted`, `WinnerPaid` |
| Error | `CapWords` | `InvalidPrediction` |
| Function, Modifier | `mixedCase` | `submitEntry`, `onlyAdmin` |
| Function arguments, local vars, state vars | `mixedCase` | `matchId`, `stakedAmount` |
| Constants | `UPPER_CASE_WITH_UNDERSCORES` | `MAX_MATCHES`, `JACKPOT_THRESHOLD` |
| Non-external functions and variables | `_leadingUnderscore` | `_distribute`, `_poolBalance` |

- Avoid `l`, `O`, `I` as single-letter variable names.
- Contract filename must match the contract name (e.g., `Matchweek.sol` for `contract Matchweek`).
- Use a trailing underscore (`name_`) to avoid collisions with reserved names.

### NatSpec

All public and external interfaces must have NatSpec comments. Use `///` for single-line and `/** ... */` for multi-line.

```solidity
/// @notice Submits a matchweek entry.
/// @param predictions Array of 10 outcomes (0=home, 1=draw, 2=away).
/// @param stake Amount of stablecoin staked.
/// @dev Reverts if the matchweek is not open.
function submitEntry(uint8[] calldata predictions, uint256 stake) external { ... }
```

Required tags:
- `@notice` — what the function does (user-facing).
- `@param` — each parameter.
- `@return` — each return value.
- `@dev` — implementation details (developer-facing, optional but encouraged).
- `@title` / `@author` — at contract level.
