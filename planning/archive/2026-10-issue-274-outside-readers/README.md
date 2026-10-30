## Outcome

#274 (the next item on #377) asked first whether a partial run's recompute could be narrowed, then, revised 2026-10-28, whether groups outside a partial run that read it are left stale. They are, and many: so a run now recomputes each held reader whose last build matches what the recompute would run, and names the rest (refused, waiting, unchecked) in `<TS>_outside_readers.tsv` and a summary WARN, without changing the exit status (operator, 2026-10-29). The pieces: `data-raw/recompute_readers.R` (pure classifier) and `data-raw/recompute_readers_check.R` (facts from the database, git and the stamp the recompute would write), `recompute_readers` in `study_area_recompute.sh`, `run_finish` taking the union as the recompute set and keeping the compare on the run's groups, the dependency map in every recomputing mode, and verifier changes. The plan review (Plan agent) found the judge refuses `.rc` ids it was not asked for and that the verifier would raise on a reader's lifted segments, both of which reshaped the plan before the wiring. Code-check took four rounds; each "now" value read separately from the build's facts was a place to find a gap (a 0-row frame, the dispatcher's own fresh not required clean, a stale `FRESH_GIT_SHA` pin in `--recompute-only`, crate and fresh versions), and round 4's enumeration of every compared fact and every recompute input ended it. Verdict: `research/study_area_run.md`, "Since link#274"; mechanics RUNBOOK §8d, "Groups outside a partial run".

## Measurement

- Outside readers by the line rule: North Thompson (6 groups) 65, field scope (34) 78, parity closure (17) 85, DUNC (1) 1. Held by the target schema: 32 and 35 in `fresh`, 0 in the scratch parity schema, every one in `fresh_default`. Compatible today: none, anywhere (`fresh_default` at 0.68.0; most of `fresh`'s readers predate the log tables). So the change names readers until the next provincial run.
- A full run is unchanged: 2026-10-23's 241 groups leave nothing held outside.
- The line rule regenerated from FWA in 73.5 s equals #374's map row for row.
- Nine pairs are linked only by rows the run group holds on the reader's own segments (KOTR's three on KOTL's); 1,216 of 1,864 off-segment rows are read by the segment's owner. The line rule errs wide: ADMS "reads" BBAR, but none of BBAR's rows lie below ADMS.
- Wrong turns: the first co-held query over all 968 line-not-owner pairs hit its 15 min bound; the first fixture pair (ADMS/BBAR) had no row behind it; UPET/LPET (GR and RB only, no bcfishpass reference) and CARP (above the Peace dams a scratch schema lacks) could not serve the live check, which ran on KISK and LPCE.
- Live, scratch `fresh_274`: LPCE's run recomputed KISK (exit 0, verifiers pass); with KISK's build sha unresolvable, `--recompute-only` named it `refused` (exit 0).

## Evidence

`data-raw/logs/partial_readers_274/` (its README indexes it), with the live runs under `data-raw/logs/partial_readers_274/live/20261030_05*`.

## Owed

- The first real partial run after the provincial run exercises it; its
      `<TS>_outside_readers.tsv` is committed with that run's evidence

Closed by: PR #417 (v0.71.0)
