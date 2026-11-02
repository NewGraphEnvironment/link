# Code-check, PR 2 (#415 proof), round 2

## Checklist read

- code-check.md: every H3 under `## Mechanisms` (prose, tables skipped), especially "A proxy is not the property", "A guard's scope, escape hatches, and remedies" (compression and quantifier sweep), "Restore the bug and prove the guard fires", "Written data outlives the fix", "One fact derived twice".
- code-check-r.md: "A `data-raw/` script must load the source tree", "A database driver's value is not a base R type", "Postgres row order is never fixed unless the query fixes it", "`sprintf(\"%g\", x)` writes `Inf` and `NA` into SQL as bare words" (template `%` handling), "An `information_schema` lookup by the literal table name".

## What was verified, and how

- Re-ran a copy of HEAD's `lifts.R` outside the repo (scratch schemas `zzrev_lift_*`, dropped by the script; outputs to the scratchpad) on all four groups. It reproduces the committed `lifts.csv` and `lifts_obs.csv` exactly, apart from row order (run order SETN, BULK, COTR, MORK). Both controls passed again.
- Every number in `research/minimal_network.md` checked against its CSV: the segment and km table, 77 to 90 %, the 19,656 FWA cuts, the 10 access slivers, gradient (0.022, 99.99 %), build minutes, code 2 (0 to 8.5 %, BULK CO 628 to 681, COTR BT 663 to 698; accessible km move by at most 0.002 km), the rearing table, spawning "under 1 %" (SETN SK 0.94 % is the closest; MORK SK 1.6 %), overlay (53/291, 22/454, 19/333, 8/198; default 11/0/0/0), crossing fields (370 to 861, 0 to 287, SETN +659), placement (2,160 to 426; a sixth or less, COTR 16.6 %; 1.14 to 1.70 per branch), and the lifts table (every cell). RUNBOOK's "0 to 1.2 % of km" (MORK 0.004 %, SETN 1.19 %), CLAUDE.md's BULK overlay and rearing figures, and #444's body figures (0 to 1.2 % km, 0 to 0.9 % records, gradient shift 0.007 to 0.073, BULK and COTR CH rearing) all hold.
- "The salmon and steelhead overrides these groups hold are known-habitat and control lifts": the working schemas hold 1 to 28 such rows per species and `lift_n` is 0 for each, so every one survives the counterfactual. Holds.
- Classified each lift-added minimal position (SETN, COTR, BULK, MORK) by what it does to the segments, with a 1 m tolerance, since breaks are metre-rounded and an exact-millimetre match finds almost none of the new starts (SETN: 3 of 340).

## Mechanism

Round 1's defects shared one assumption: a count over one population stands for another (positions for cuts). The fixes replaced positions with starts in the table, but the same assumption survives one axis over in three places: a gross count read as a net change, one reason read as every reason, and the script at one commit read as the script that produced the evidence. Places checked for it: `research/minimal_network.md` lines 3, 18, 25, 37, 39, 43-45, 49, 53-66; the proof README lines 3 and 25; RUNBOOK line 892; CLAUDE.md's #415 block; `research/README.md`'s row; #444's body. Findings below are the ones that fail.

## Findings

- **[severity: bug]** research/minimal_network.md:65 — two wrong statements in the SETN sentence.
  - "segment starts rose by 340": 340 is starts *added*; 5 were removed (`starts_removed_by_lifts`), so the count rose by 335, which is also `segments_built - segments_no_lift` (72,354 − 72,019).
  - "the other positions fall on an FWA segment's start": of the 261 added positions (601 − 340) that add no start, 257 lie on an FWA segment start; the other 4 lie within 1 m of an existing non-FWA cut and are skipped by the 1 m rule (RUNBOOK §2). Line 55 states the same rule as the only one ("a moved position is a cut only where it does not fall on an FWA segment's start"), which omits the 1 m skip. MORK shows the same gap (3 added positions, 0 on an FWA start, 2 starts added).
  - Fix: "starts rose by 335 (340 added, 5 removed)"; "257 of the other 261 fall on an FWA segment's start, and 4 within 1 m of another cut"; on line 55, "where it does not fall on, or within 1 m of, an existing segment end".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a compression that dropped a condition; a gross count restated as a net change)

- **[severity: fragile]** data-raw/logs/minimal_breaks_415/README.md:25 — still describes the control that round 1 removed: "It stops unless the build's own overrides reproduce the build and a species with no observation lift keeps its cuts." `lifts.R` no longer has that check (it held by construction); its second control is now that every segment start one side holds and the other does not lies within 1 m of a minimal position that moved. The fix reached `lifts.R` and the write-up (line 53) but not this README, so the evidence directory's own index names a check that does not run.
  - **Rule:** code-check.md "Written data outlives the fix" (when a derived fact changes, enumerate every artifact quoting it)

- **[severity: fragile]** data-raw/logs/minimal_breaks_415/README.md:3 and research/minimal_network.md:3 — the provenance of `lifts.csv` is wrong. The README says `lifts.R` "was re-run at `234425e8`, which changed only how it reads counts; both runs gave the same numbers"; the research header says `lifts.R` produced its output "at link `6bf9ca06`". The committed `lifts.csv` was written by `lifts.R` as of `ac52e150`, which added the `starts_*` columns and replaced control 2. Run at `6bf9ca06` or `234425e8`, `lifts.R` writes no `starts_*` columns and runs the old control, so neither stated commit produces the table the write-up cites. The values themselves reproduce (`R/` is unchanged since `6bf9ca06`, and HEAD's `lifts.R` regenerates both CSVs identically); only the commit stated for them is wrong.
  - Fix: name `ac52e150` (or HEAD) as the commit `lifts.R` was last run at, and say the builds are at `6bf9ca06` with `R/` unchanged since.
  - **Rule:** code-check.md "Written data outlives the fix" (a provenance stamp must name what actually produced the artifact)
