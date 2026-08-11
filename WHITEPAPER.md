# PitchMkt — Whitepaper Base

---

## What is PitchMkt

PitchMkt is a decentralised sports prediction platform where users predict the outcome of every match in a football matchday and compete for a shared prize pool. Players who are unsure about a match can back two or even three of its outcomes, and the protocol prices that coverage exactly.

The protocol is designed to be transparent, intermediary-free and open to anyone with internet access and a digital wallet.

---

## How a matchday works

Every weekend a new matchday opens with ten matches drawn from a curated selection of the top European football leagues. Users have until fifteen minutes before the first kick-off to submit their prediction: for each match they select one or more outcomes — the home team wins, the match ends in a draw, or the away team wins.

Selecting a single outcome in every match produces one **column**: a complete combination of ten outcomes, one per match. Selecting two or three outcomes in a match does not create a second prediction, it widens the one being made — the prediction then spans every column consistent with those selections. A prediction that backs two outcomes in one match and a single outcome in the other nine spans two columns.

The column is the unit the protocol prices and pays. One column costs a fixed amount in stablecoins, so the cost of a prediction is that unit price multiplied by the number of columns it spans. Nobody chooses how much to stake: the cost is derived from the picks themselves and charged on submission.

A prediction is unique however many columns it spans, and there is no way to buy the same one twice. A user who wants more exposure submits another prediction. Every prediction submitted accumulates into a shared prize pool.

Once all matches are finished, the results are published in an official and verifiable way. After a 48-hour window during which any participant can challenge a result they believe is incorrect, the prize pool is distributed automatically among the winners.

---

## How prizes are distributed

Every column a prediction spans is scored on its own, and each one lands in exactly one tier according to how many of its ten outcomes proved correct. A prediction spanning several columns can therefore win in several tiers at the same time: when a match covered by two outcomes comes in, one column ends with ten correct and the other with nine, and both are paid.

The prize pool is divided into tiers based on the number of correct outcomes in a column:

- Ten correct: 33% of the pool
- Nine correct: 15% of the pool
- Eight correct: 15% of the pool
- Seven correct: 15% of the pool
- Six correct: 19% of the pool
- Fewer than six correct: no prize

Within a tier, the prize is split proportionally to winning columns: a prediction holding two of the fifty columns that reached a tier takes two fiftieths of it. Since every column costs the same, splitting a tier proportionally to capital and splitting it equally among its winning columns are the same operation.

If a tier has no winners, its entire percentage goes to the carry pool. It is never redistributed to the tiers that did have winners, so no player's prize grows because someone else's tier was left empty.

Prizes are claimed per tier, not per prediction: a prediction that won in three tiers claims each of them separately. Winners have thirty days to claim. Anything unclaimed after that period is automatically added to the carry pool.

---

## The carry pool

The carry pool is the protocol's most powerful incentive: a balance that accumulates across matchdays and can only ever be won outright.

It is funded entirely by prize money that was never awarded, from two sources: the percentage of any tier that no column reached, and any prize a winner fails to collect within the thirty-day claim window. Nothing else feeds it; in particular, the protocol fee does not. This is what keeps the carry pool honest — it is built from unawarded prizes, never from money taken out of players' pockets.

Because a tier is left empty far more often than a perfect ten is hit, the pool grows matchday after matchday. The longer it goes without a perfect winner, the bigger it gets, generating anticipation and attracting new participants.

The moment a column gets all ten correct, the carry pool is released and added on top of the top tier prize. There is no shortcut: the carry pool can only be won by a column with all ten outcomes right. Whatever that same matchday leaves unawarded then seeds the next cycle.

---

## Squads

Squads are the social heart of PitchMkt. A squad is a group of people who put their capital behind one leader so that together they can afford a prediction none of them could pay for alone.

Width is expensive. Backing two outcomes in seven of the ten matches spans 128 columns, and 128 columns cost 128 times the unit price. That kind of coverage — the kind that survives a surprise result because the alternative outcome was already covered — is simply out of reach on an individual budget.

The squad solves that by splitting the bill. Before the matchday opens for predictions, members buy into their squad in whole units: each unit is the price of one column, and a member can buy as many as they want. When the buy-in window closes, the leader knows exactly how many columns the squad has to spend and builds the prediction — or the handful of predictions — that spends them. They enter the global pool like anyone else's, at their full derived cost.

Every member owns the fraction of the squad they paid for, and that same fraction of anything it wins. When a squad prediction lands in a tier, the prize is split across members in proportion to their units, minus the leader's commission. Buying in whole units is what keeps this exact: the pot is always a whole number of columns, so it is always spendable to the last one, and no member's share depends on rounding.

### What a member is actually buying

Members commit their capital before they know the picks, and that is the deliberate shape of the thing. What a member buys is not a particular set of outcomes — it is a leader's judgement, and the width that judgement gets to work with. The protocol's job is to make that judgement measurable rather than to hide the risk: every leader carries a public track record of the matchdays they have called, and it is the only thing a member has to go on.

Two rules keep that trust bounded. The leader never holds the money — the pot is held by the protocol and can only ever leave it as a prediction or as a refund. And if the leader fails to submit before the matchday closes, every member is refunded automatically, with no human intervention required.

A squad is also not a way to punch above your weight. The same capital deployed individually earns exactly the same claim on the pool — distribution is proportional to capital, and the protocol does not care whether that capital arrived from one wallet or from forty. What a squad buys is not leverage, it is **affordability of coverage**: access to a breadth of prediction the member's own budget could not reach, in exchange for owning only a fraction of the result.

### The squad leader's role

The leader decides the picks and how to spend the squad's width. Their reputation is on the line every matchday. The protocol allows the leader to set a small commission on the prizes their squad earns, visible to all members before they buy in. This creates a natural market of leaders: those with the best track record raise the most, and raising more is what lets them go wider.

This mechanic turns anyone with football knowledge and an audience — content creators, sports journalists, analysts — into a natural squad leader with real economic incentives to recruit members and get the picks right.

### Why the picks need no secrecy

Once submitted, a squad's predictions are as public as everybody else's, and nothing about that hurts the squad. A prediction is not information that can be cheaply duplicated — it is a position that costs what it costs. Replicating a 128-column prediction means paying for 128 columns. Anyone able and willing to put up that capital was never going to be a member, and anyone unwilling gains nothing from reading the picks.

This is why PitchMkt needs no scheme for hiding or committing picks in advance: capital, not concealment, is what protects a squad's work.

---

## Transparency and dispute resolution

The results of each matchday are published by a group of administrators who sign jointly, including a verifiable reference to the official source. During 48 hours any participant can challenge a result they believe is incorrect by posting a deposit as a good-faith guarantee. If the challenge is valid, they get their deposit back plus an additional reward. If it is invalid, the deposit goes to the protocol fund.

If the administrators do not publish results within the established deadline, the protocol automatically refunds every participant with no human intervention required.

---

## Protocol fees

The protocol applies a 3% fee on the matchday pool. Squads have no pool of their own — their prediction competes in the same one as everybody else's — so the fee is charged once and applies identically to individual and squad predictions. That fee goes entirely to the operational running of the platform and the future development of the protocol.

It is the protocol's only cut: charged once, on the pool, with nothing further taken from prizes or from the carry pool — which, as described above, is funded exclusively by unawarded prize money.

---

## Player reputation

Every participant builds a public record of their activity: matchdays played, total correct predictions, best matchday, active streak and historical earnings. This record is visible to anyone, allowing members to choose which squad to join based on their leader's track record.

The most consistent and accurate players earn a rank that identifies them across the platform, ranging from rookie to iconic.

---

## The complete cycle at a glance

1. A matchday opens with ten matches
2. Players submit their own predictions, or buy units in a squad for its leader to submit
3. The prize pool grows with every prediction
4. Once all matches are finished, official results are published
5. A 48-hour window opens for challenging results
6. The pool is distributed automatically among the winning columns in each tier
7. Winners claim each tier they won within thirty days
8. Anything unclaimed feeds the carry pool for the next matchday
