# Code-check round 2 — #404 (variant_cost_404)

Reviewed: the branch diff against its merge-base (`branch.diff`), and in full
`data-raw/habitat_variants_build.R`, `data-raw/logs/variant_cost_404/analyze.R`, the campaign
README, `data-raw/habitat_score/README.md`, the NEWS top section, the CLAUDE.md status entry,
`variant_timing.csv`, `steps.csv`, `split.csv`, `launch_state.txt`, `stamp_build.txt`, the
three `build_*.log` files (grepped for every `done in` line), `steps_vs_segments.png`, the
three committed `parameters_habitat_thresholds.csv` files, and
`data-raw/logs/habitat_score_331/build_20261015_full.log` + its stamp (for the m1 comparison).

## Checklist read

- `code-check.md` (330,698 bytes): the prose of all 14 H3s under `## Mechanisms` in full
  (table rows skipped); the 27 headings under "Rules that stand alone", "Security" and
  "Spreadsheets and PDFs" not read beyond the index (none names a tool or shape in this diff).
- `code-check-r.md` (178,405 bytes): read in full — Read-back shape; `on.exit()` at top level;
  a `data-raw/` script must load the source tree; `$` partial-matches; a DBI value is not a base
  type; `nzchar(NA)`; `paste()` with a zero-length argument; `identical()` on two reader results;
  CSV whitespace; `sort()`/`order()` collate by locale; `match()` treats NA as a value; `[[` on a
  named atomic vector; `data.frame()` recycles a scalar against zero-length; Postgres row order;
  Rscript reads a script as it runs; `system2(stdout = TRUE)`; `c(name = x)` keeps names;
  `read.delim()` quotes by default; `load_all()` refuses a dependency below the floor; `ifelse()`
  with an all-NA test. That is 20 headings; about 105 not read (none names a tool this diff uses).
- `code-check-shell.md` (125,440 bytes): Paths and Quoting read in full (2 headings); the diff
  carries no shell beyond `system("uptime")`; about 90 headings not read.
- `code-check-spatial.md` (155,517 bytes): 0 headings read; the diff has no spatial code.

## What was re-verified clean this round

- `write_thresholds()`: re-implemented the branch's `is_text` rule in a standalone Rscript
  against the three committed bundles; md5 identical for `default`, `bcfishpass` and
  `default_tuned`. The `""` cell (BT `rear_edge_types`) and the `"model"` cell
  (`rear_river_measure`) both quote, every numeric column stays bare, NA stays bare.
- `record_timing()` round trip: read the committed `variant_timing.csv` with
  `colClasses = "character"`, rbind-ed a typed row (with `NA_integer_` / `NA_real_`), wrote and
  re-read with `read.csv()` defaults: row count +1, no column dropped or reordered, `seconds` and
  `n_segments` come back numeric/integer, `in_total` logical, `NA` cells come back `NA` (written
  bare), the empty `watershed_group_code` of a `persist_init` row stays `""` on both the
  character read (so its replace key matches) and the typed read. The replace key
  `(variant, wsg, step %in% names(seconds))` leaves the base run's `base_model` /
  `base_recompute` rows alone when the base variant's pass re-runs on the same group.
- Instrumentation vs modelling: the only new calls inside the modelled region are
  `Sys.time()`, `load_1min()` (`uptime`, wrapped) and `n_segments_of()` (a `SELECT count(*)` on
  the base schema); no modelling call moved, and `record_built()` still precedes the timing
  write. Both pre-flight and full-pass digests agree in the logs (`778f7c72`, `15073c87`).
- Numbers: every figure in the README "Measurement" section and the CLAUDE.md entry
  recomputed from `variant_timing.csv`: pass per group 0.31–1.04 min; pooled 5.583 min;
  classify 2.036 / 36.5 %, connect 1.725 / 30.9 %, working digest 0.005 / 0.1 %, persist
  1.691 / 30.3 %, copy+ANALYZE 0.090 / 1.6 %, gate 0.019 / 0.3 %, persisted digests
  0.018 / 0.3 %; split 67.7 / 0.4 / 31.9; medians 0.348 / 0.304 / 0.286; `default` pass 6.82
  min, 0.288–1.455 per group, 48.5 / 51.0 / 0.5 %; discharge join 0.61 / 0.80 min;
  persist_init 0.17 / 0.12 s; base model 67.10 min (LPCE 1.74, KOTR 7.03; focal nine 2.95–7.03,
  summed 42.35); recompute 2.37 min; 5.58 / 67.1 = 8.3 %, 3.76 / 42.35 = 8.9 %; greedy four-job
  bound 1.563 (PARS 1.038) and 1.804; 12 × 4.0 + 5.0 = 53 of 82; steps 3 + 7 = 1.355 s. The m1
  comparison (9.8 / 12.0 / 42.7 min, 0.5 REVL to 2.4 PARS, link 0.65.1 / fresh 0.39.0) matches
  `habitat_score_331`'s log and stamp. 18 passes have `done in` lines; all residuals are
  inside 0.05 min.
- `analyze.R`: the regex matches only `variant <v> <WSG> done in` lines (the base run's
  `base <WSG> done in` lines are excluded), `done[passes$key]` on a named vector yields NA for a
  missing key and the `is.na()` arm stops, `duplicated(fromLast = TRUE)` keeps the later log's
  value, `kind[[s]]` only ever sees names of `kind`.

## Findings

- **[fragile]** `data-raw/logs/variant_cost_404/README.md` ("Steps scale with the group" and
  "What happened during the builds") and `CLAUDE.md` status entry (the "Another process loaded
  m4" fact): the claim *"The two points above the connect fit (LHAF, UBTN) are the two passes
  that started at a load of 6.3"* is not what the data shows. Fitting the same line
  `analyze.R` draws (`lm(minutes ~ I(n_segments/1000))` over the nine `bt_rear_wet_p10` connect
  points), the residuals are UBTN +0.083, **KOTL +0.055**, LHAF +0.048, MURR +0.019, ELKR
  +0.014, PARS +0.014, REVL −0.052, UARL −0.073, KOTR −0.108: six of nine points sit above the
  line, and KOTL (load 4.5) sits higher above it than LHAF does. The PNG shows the same (KOTL
  at 39.4k is visibly above the dashed line, between UBTN and LHAF). UBTN is the clear
  outlier and did start at 6.3, but "the two points above the fit" names a set the figure
  does not contain, and the load attribution rests on it. Reword to what holds (UBTN is the
  one point well above the fit and started at 6.3; LHAF, also at 6.3, is third), or drop the
  LHAF half. Same sentence in both files, so fix both.

- **[fragile]** `NEWS.md` (0.69.3 bullet): *"`write_thresholds()` quoted two columns by name"*.
  The removed code was `names(thr) == "species_code" | grepl("_edge_types$", names(thr))`: one
  column by name and two by pattern (`spawn_edge_types`, `rear_edge_types`), three columns.
  CLAUDE.md's wording ("quoted `species_code` and the edge-type columns by name") is right;
  NEWS is the one a reader of the release note sees.

- **[fragile]** `data-raw/logs/variant_cost_404/README.md`, builds table: two cells are not in
  `launch_state.txt`, which the README says "holds each boundary as it was taken". (a) The
  pre-flight row's "host load (1 min) at launch 2.2": `launch_state.txt` records no `uptime`
  at the pre-flight launch (20:20:36Z); 2.21 is the "uptime at base end" reading at 20:20Z, 42
  s earlier. (b) The full run's "exited (UTC) 20:36:26": `launch_state.txt` says
  `full exited: 2026-10-28T20:36:35Z` (the README's own next paragraph cites 20:36:35 as the
  end snapshot). Neither moves a conclusion; both are numbers a reader will try to find in the
  cited file and not find. Either record where they came from or use the file's values.

- **[fragile]** `data-raw/logs/variant_cost_404/analyze.R:75`:
  `logs[order(file.info(logs)$mtime)]` relies on the logs' mtimes keeping the order the builds
  ran in. That holds in the writing checkout (13:19:23 / 13:21:24 / 13:36:09) and does not
  survive a `git clone`, `cp` or rsync without `-t`, where every log gets the copy time and the
  tie falls to `order()`'s stable name order, which here is the same order only by the accident
  that `build_preflight_revl` sorts before `build_variants`. On the committed data this cannot
  change the verdict: the pre-flight and the full pass both logged REVL at 0.3 min for both
  variants, so whichever wins the residual is identical. It would matter the first time a
  re-run pass logs a different total than its pre-flight. A clone-proof rule is in the data
  already: each log line carries `HH:MM:SS` and each timing row `built_at`, so pick, per pass,
  the `done in` line whose clock time is nearest the row's `built_at` (same day), or state in
  the script header that the logs must be read in the writing checkout.

No bug or security finding. The four round-1 fixes read correctly: the ladder count (12 rungs
+ the `default` pass), the self-check placement claim (the `local({ md5 })` block sits above the
`--step` branch, so every step), the builds table "wall" column, and the mtime ordering (with
the residual noted above).
