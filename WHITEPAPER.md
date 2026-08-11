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

- Ten correct: 40% of the pool
- Nine correct: 25% of the pool
- Eight correct: 15% of the pool
- Seven correct: 10% of the pool
- Six correct: 7% of the pool
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

Squads are the social heart of PitchMkt. A squad is a group of people who decide to play together, pooling their capital to compete with greater weight in the global prize pool.

The mechanics are straightforward: the squad leader decides the picks for a shared prediction, which all members subscribe to by contributing the same fixed amount. The prediction enters the global pool carrying the combined capital of all members. If it wins, the prize is split proportionally among everyone.

Because distribution is proportional to capital, a large squad carries more weight than an individual player with the same prediction. This makes it genuinely worthwhile to recruit members: more members means more capital, and more capital means a larger potential prize if the prediction is right.

### The squad leader's role

The leader is the one who decides the prediction. Their reputation is on the line every matchday. The protocol allows the leader to set a small commission on the prizes their squad earns, visible to all members before they join. This creates a natural market of leaders: those with the best accuracy track record attract more members, and their squads carry more weight in the pool.

This mechanic turns anyone with football knowledge and an audience — content creators, sports journalists, analysts — into a natural squad leader with real economic incentives to recruit members and get the picks right.



## Transparency and dispute resolution

The results of each matchday are published by a group of administrators who sign jointly, including a verifiable reference to the official source. During 48 hours any participant can challenge a result they believe is incorrect by posting a deposit as a good-faith guarantee. If the challenge is valid, they get their deposit back plus an additional reward. If it is invalid, the deposit goes to the protocol fund.

If the administrators do not publish results within the established deadline, the protocol automatically refunds every participant with no human intervention required.

---

## Protocol fees

The protocol applies a 3% fee on every pool, both the global pool and each squad's pool. That fee goes entirely to the operational running of the platform and the future development of the protocol.

It is the protocol's only cut: charged once, on the pool, with nothing further taken from prizes or from the carry pool — which, as described above, is funded exclusively by unawarded prize money.

---

## Player reputation

Every participant builds a public record of their activity: matchdays played, total correct predictions, best matchday, active streak and historical earnings. This record is visible to anyone, allowing members to choose which squad to join based on their leader's track record.

The most consistent and accurate players earn a rank that identifies them across the platform, ranging from rookie to iconic.

---

## The complete cycle at a glance

1. A matchday opens with ten matches
2. Players submit predictions individually or through their squad
3. The prize pool grows with every prediction
4. Once all matches are finished, official results are published
5. A 48-hour window opens for challenging results
6. The pool is distributed automatically among the winning columns in each tier
7. Winners claim each tier they won within thirty days
8. Anything unclaimed feeds the carry pool for the next matchday
