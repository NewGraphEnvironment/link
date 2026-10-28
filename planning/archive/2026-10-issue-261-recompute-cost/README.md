## Outcome

#261 asked whether a group's post-consolidate recompute cost tracks the barriers downstream of it (CHWK 15.56 min against SALR's 0.72 at 1.26× the segments). Refuted: that count correlates at −0.08 with the 2026-10-23 minutes, and seven of nine decomposed groups have none. The cost is the downstream walk's shape. `fresh::frs_network_features()` drives each walk from every feature in the province and probes the group's segments once per feature, at a cost per feature set by the group's GiST; in output-bound groups (SETN) the pairs add to it. A per-group sample walk predicts the recompute minutes at Spearman 0.982 against a run-to-run 0.993, and a prefilter that returns the same features cuts most groups' walks 3.6× to 24.6×. The fix belongs in fresh: NewGraphEnvironment/fresh#272. No link code changed. The verdict lives in `research/recompute_cost.md`.

Learned on the way: a sentence that compresses a measurement (rounds it, ranks it, says "every") is a new claim about a population. Code-check took three rounds and an enumeration of about 200 claims to get the prose to match the data: a 9× probe ratio read from rounded node times (5.7×), SETN called slowest from rows run under a colder cache (under one load it costs about what CHWK does), and a speed range that dropped SETN's 1.2×.

## Measurement

- CHWK re-run 617.6 s, walks 589.4 s; SALR 46.3 s, walks 28.2 s; all digests unchanged (re-run from `1d00c04c`).
- Inner side of the CH walk per feature: SALR 1.8 µs, CHWK 10.3 µs (5.7×); CHWK/SALR natural walks 18× = 4.1× per CH walk × 4.5× rows walked.
- Prefilter, same features per segment in 32 of 32 walks; per group 3.6× (SPAT) to 24.6× (CHWK) faster, SETN 1.2× (4.83 M pairs, 526 MiB sort spill).
- 241 groups: predicted walk seconds against 2026-10-23 minutes, Spearman 0.982, log-log slope 0.99, R² 0.970; segments 0.605; features below the outlet −0.083.
- Pool (2026-10-23, `-j8`): 50,352 s summed job time, predicted walks 33,398 s; prefilter estimated to save 18,221 to 25,534 s (36 to 51 %); CHWK 1.9 % of the pool.
- Wrong turns kept: the group's code range as the probe's predictor (`range_hypothesis.*`, refuted by SETN); `IN (SELECT …)` as the prefilter (`walk_prefilter_in_select.tsv`, still reads the whole table).

## Evidence

`data-raw/logs/recompute_cost_261/` (its README indexes the scripts and outputs).

## Owed

- Re-run `predictors.R` against the next provincial run (v0.69.0, #326 segmentation roughly halves segments), since every number here is on the pre-#326 build
- File the drafted fresh / link follow-up once you approve its body (done 2026-10-27: NewGraphEnvironment/fresh#272)

Closed by: PR (opened next, from branch `261-why-is-chwk-20x-salr-at-80-of-its-size-t`); relates to #261, which stays open for the fresh follow-up.
