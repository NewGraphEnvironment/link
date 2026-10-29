# Naming link's outputs: what a token covers

**Verified:** 2026-10-29 · **Issues:** #414 (consumers: #415, knowledge#119, knowledge#120) · **Produced by:** reading the five config bundles under `inst/extdata/configs/` and the code paths below; the specs in `inst/extdata/vocabulary.csv` are written by `lnk_vocabulary_resolve()`'s helpers · **Status:** four axes; seven tokens; `default_extrabreaks` and `default_rearbreaks` have none and refuse

## The question

Config names say how a config was made, and their contents move under a fixed name. A
tuning that stores runs on several networks needs names that say what each one is and stay
true. #414 proposed three axes, each an input choice: how streams were cut, how gradient
was measured and where flow came from. Its first test was to describe today's configs in
tokens. If that needed a new token per config, the axes were wrong.

## What the first test found

**`break_order` and `observation_breaks` do not fix where streams are cut.** Two more
things move cuts:

- **Gradient classes.** `pipeline: gradient_classes` sets the gradients streams are broken
  at (`.lnk_resolve_classes()`; bcfishpass's 15 / 20 / 25 / 30 % when absent).
  `default_extrabreaks` adds seven classes at spawning and rearing ceilings,
  `default_rearbreaks` four.
- **Access rules.** Since #326, a gradient position cuts a stream only where a modelled
  species' access changes, after that species' observation lifts
  (`.lnk_pipeline_prep_minimal()`). So each species' `access_gradient_max`, its
  `observation_*` lift parameters, which species the rules model and the presence table
  all move segments. Moving one species from 30 % to 18 % adds cuts wherever 18 % is
  first reached.

The access inputs differ between the shipped configs:

| Input | `bcfishpass` | `default` |
|---|---|---|
| Species the rules model | BT CH CM CO PK SK ST WCT | adds GR, KO, RB |
| BT lifts on | BT, the salmon and ST, records from 1900 | BT and DV, any date |
| RB lifts | none | one RB record |
| Presence table | bcfishpass's | the same except no GR in LARL |

`default_extrabreaks` and `default_rearbreaks` are `extends: ~` copies of an older
`default`. They carry no RB lift rule and bcfishpass's presence table, and leave
`observation_breaks` out (so every observation cuts), because they predate #396.

**`cabd_additions_barriers` does not move cuts.** In #367 it changed only DAM tokens in
the mapping code; segments were identical.

## The axes

So access is its own axis, and the cut axis keeps naming the method:

| Axis | Prefix | Covers | Spec |
|---|---|---|---|
| cut | `cut-` | break sources in order; `observation_breaks` when observations are a source; gradient classes | canonical string |
| acc | `acc-` | species the rules model; each species' access gradient and observation lifts (`parameters_fresh.csv`); the presence table | sha256 of the parsed values |
| grad | `grad-` | how a segment's gradient is measured | `gradient=segment` |
| flow | `q-` | `discharge_source` and `discharge_fill` | canonical string |

With these axes, five configs take seven tokens:

| Config | cut | acc | grad | flow |
|---|---|---|---|---|
| `default` | `cut-full-top` | `acc-v1` | `grad-seg` | `q-fwapg` |
| `default_tuned` | `cut-full-top` | `acc-v1` | `grad-seg` | `q-wet-fill` |
| `bcfishpass` | `cut-full-ssf-all` | `acc-bcfp` | `grad-seg` | `q-fwapg` |
| `default_extrabreaks` | none | none | `grad-seg` | `q-fwapg` |
| `default_rearbreaks` | none | none | `grad-seg` | `q-fwapg` |

The two stale bundles get no rows (operator, 2026-10-29). A build of either refuses until
someone names it.

`acc-bcfp` is named for its source, because bcfishpass is the one rule set defined outside
us. link's own access rules are numbered revisions (`acc-v1`, then `acc-v2`), not named
after the company (operator, 2026-10-29).

## What stays out of tokens

- **Results.** Habitat thresholds, width against flow, and habitat rules change flags, not
  segments, and a tuning chooses them.
- **Data vintage.** Observation records, the weekly bcfishpass correction CSVs (definite
  barriers, crossings fixes, habitat classification), FWA and the discharge loads identify
  one build. `<schema>.log` and `log_input` carry them. So two outputs with the same
  tokens were made the same way, not necessarily from the same data.
- **`observation_exclusions.csv`.** It moves lifts, but it is a list of corrections to
  records, which a reviewer extends one record at a time, as the bcfishpass CSVs are
  extended. Putting it in `acc` would mint a token per review.
- **Species pooling.** `species_pooling.csv` is read by the validator only, never by the
  pipeline.

## How the acc digest is built

`.lnk_vocabulary_spec_acc()` hashes the modelled species, the seven access columns of
`parameters_fresh` and the presence table's species columns. Before hashing, it makes
every value trimmed text, treats `NA` and an empty cell as one, reads `t`/`TRUE` as
`true`, and sorts columns by name and rows in C order. So `bcfishpass`'s quoted CSV and
`default`'s unquoted one would digest the same at the same values, and so would a
reordered file or an edited `notes` column. The tests in `tests/testthat/test-lnk_vocabulary.R` hold
each of those.
