## Outcome

The README, DESCRIPTION, CITATION.cff and Rd now describe link as it runs at v0.65.0, on three things:
- **intrinsic habitat potential** per species;
- **connectivity:** access resolved past natural barriers, with fish observations as evidence of passage, and each reachable reach marked with the kind of human-made barrier below it;
- **rules kept as data.**

A gq-styled figure of real output (Arctic grayling in the Parsnip, `default` config, from the cached vignette data) shows the idea rather than describing it. bcfishpass is acknowledged in its own section for the method and the correction data link reads. CITATION.cff credits New Graph Environment Ltd. for Zenodo, and an invalid ORCID was replaced.

What was learned: a description checked against NAMESPACE, NEWS and CLAUDE.md is not checked. Three of the wrong claims were in the descriptions people see first:
- "access past crossings and dams": access is resolved past natural barriers only;
- "habitat upstream of each crossing": `lnk_aggregate()` sums only along the crossing's own stream line, and nothing calls it;
- "which barrier": no barrier id is persisted per reach.

This is the first application of the README convention drafted in the internal conventions repo. The pkgdown index stayed auto-generated (the prefix families already group it), and the fresh pin bump moved to #339.

## Measurement

Code-check, run once over the branch, took 4 reviewer rounds:
- **Round 1:** 6 findings (3 claims, 3 packaging).
- **Round 2:** 4 claims, one inside a round-1 fix.
- **Round 3:** enumerated 79 published claims: 71 held, 1 false, 7 overstated.
- **Round 4:** enumerated the 13 sentences round 3 rewrote: 8 held, 5 overstated, all inside round-3 fixes.
- **Final:** 6 rewrites checked by hand: 6/6 hold.

The mechanism is compositional. Each clause was true of some function or bundle, but the sentence tied it to the run, or to every member of a set. Qualifying a sentence grew new overstatements; saying less ended the loop.

Gap found and not fixed: per-crossing upstream habitat, network-walked and per species, is not in link today. `lnk_aggregate()` is same-stream only and cannot read the persisted habitat.

`devtools::check()`: DESCRIPTION meta OK. The 1 ERROR / 3 WARNINGs / 3 NOTEs are all pre-existing: DB-bound tests (with the tunnel down), and non-ASCII and Rd notes in untouched files.

## Evidence

`review-round*.md` in this directory (round 3 holds the full 79-claim table).

Closed by: PR for #338
