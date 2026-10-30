# Enumeration after round 2: every step from what the pipeline reads to what a spec records

Mechanism behind rounds 1 and 2: the spec is a projection of the run's inputs, and each
normalising step in it (sort, case fold, value fold, number formatting, NA folding, name
dropping, reading `cfg` where the pipeline reads `loaded`) is a place two inputs the
pipeline treats differently could share a spec. Fails toward pass. The rule now: a spec
step folds nothing unless every reader of that input folds the same way; a spurious new
token (the safe direction) is accepted.

Candidate set: every expression in `.lnk_vocabulary_spec_cut()`, `.lnk_vocabulary_spec_acc()`,
`.lnk_vocabulary_spec_flow()`, the `grad` constant and `.lnk_vocabulary_canonical()`
(R/lnk_vocabulary.R at the round-2 fix commit). 17 steps.

| # | Step | Pipeline reads | Verdict |
|---|---|---|---|
| 1 | `break_order` via `.lnk_break_order(cfg)` | the same function (`lnk_pipeline_break()`) | exact, shared |
| 2 | `observation_breaks` only when `observations` is a source | `observations_breaks` is applied only from `break_order`; no other reader (grep) | exact |
| 3 | `.lnk_observation_breaks(cfg)` value | the same function, closed set | exact, shared |
| 4 | gradient classes via `.lnk_resolve_classes(NULL, cfg)`, names and values, cfg order | the same function | exact (round 2: names were dropped, values sorted) |
| 5 | class values formatted by `.lnk_vocabulary_num()` | doubles compared numerically | exact: as.character only where it round-trips, else %.17g |
| 6 | barrier inputs: `!is.null(loaded[[k]])` for three keys | prepare gates on `!is.null(loaded$<key>)` (`lnk_pipeline_prepare.R:419,524,572,582`) | exact (was `names(cfg$files)`) |
| 7 | flow: `.lnk_discharge_source(cfg)`, `.lnk_discharge_fill(cfg)` | the same functions | exact, shared |
| 8 | grad: constant `gradient=segment` | no knob | exact |
| 9 | species: `cfg$species` as is, rules order | `prep_minimal` loops `cfg$species`, matches `species_code == sp` | exact (round 2: was upper-cased and sorted) |
| 10 | access-class map `.lnk_classes_bcfp`, names:values | the same constant in prepare | exact |
| 11 | presence groups: `formals(lnk_presence)$groups` | prepare and run call `lnk_presence()` with the default | exact |
| 12 | `parameters_fresh` column subset (7 access columns) | access reads those; `cluster_*`, `spawn_gradient_min` are habitat, `rear_gradient_min` is unread (dictionary) | subset sound (round 2 reviewer confirmed every column read is in) |
| 13 | presence column subset via `.lnk_presence_species_cols()` | both readers use the same helper | exact, shared |
| 14 | columns sorted by name | readers index by name | safe fold |
| 15 | rows sorted | first-row reads only matter with duplicate keys, now refused (species_code, watershed_group_code) | safe fold, guarded |
| 16 | values: doubles exact, others `as.character()`, NA as `\N` apart from "", no trim, no case fold | readers test values exactly (`identical(x, "t")`) | exact (round 1: folded) |
| 17 | delimiters: `\`, tab, newline escaped; sections joined by `\n--\n` | n/a (injectivity) | rows have more than one column, so no row is `--`; species codes cannot hold a newline in a YAML key list joined by `,` — a code containing `,` would collide; codes are species abbreviations, accepted |

Nothing above folds a distinction a reader makes, except #17's comma, accepted.
