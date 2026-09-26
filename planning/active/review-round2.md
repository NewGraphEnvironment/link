# Code-check round 2 — lnk_habitat_validate() + data-raw/habitat_validate.R (#283)

Reviewer: subagent, 2026-09-26. Diff: `diff_r2.patch`. Tests run from a copy of the repo with the
fixture schema renamed (`zz_lnk_validate_rev2`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 75 ]`.
Live runs from the copy, output to scratch only:
`--bundles=default:fresh_default,bcfishpass:fresh --wsgs=MORR,BULK,PINE,COTR,UPCE` with
`LNK_KNOWLEDGE_DIR=~/Projects/repo/knowledge` (39 s), plus one single-WSG run (below).

Round-1 fixes checked:
- (1) `in_uhc_spawn` / `in_uhc_rear`: complete. The loaded UHC `spawning` / `rearing` are `int`
  (values -4 / -1 / 1 / NA) in both bundles, so `u.spawning = 1` is a valid comparison and selects
  exactly what the overlay forces.
- (2) `n_cand::int`: complete. The other count the driver reads (`n_wsg` in the stamp) is wrapped
  in `as.integer()`.
- (3) `n_absence_rearing` (stream) and `n_absence_rearing_any`: complete as named. A related
  asymmetry remains (see the buffer finding below).
- (4) `gradient_below_min`: correct for today's bundles, but the min it tests against comes from
  a different source than the predicate's lower bound (see below). It is also only attributed on
  the `p_g & !p_w` arm, so a below-window gradient that also needs a width relaxation still reads
  `fails_gradient_and_width`. That is minor.

## Findings

- **[bug — silently wrong numbers]** `data-raw/habitat_validate.R:97-107, 135-145`: FISS sites that
  caught fish but recorded no species are counted as absences of every species.
  - The driver treats a site as "not caught" whenever `species_list` lacks the species name. In
    the knowledge snapshots `species_list` is empty for 5,303 of the 8,301 driver-sampled unique
    sites.
  - Only 1,022 of those are no-fish-caught. For 3,378 of the snapped sites `total_fish > 0` and
    `fish_counted` is TRUE: fish were caught and counted, but the Step-2 species cell was blank
    (`knowledge/scripts/0220-fiss-xls-parse-nfc.R:354` builds `species_list` from non-NA species
    only). A further 407 have effort recorded but no count entered at all.
  - Measured on the live run, `fresh_default` BT, MORR+BULK+PINE+COTR+UPCE: `n_absence` = 3,095.
    Of those, **1,948 (63%)** come from "fish caught, no species" sites and 88 from "effort, no
    count". Only 739 come from sites with a species list and 320 from no-fish-caught sites.
  - The false-positive columns (`n_absence_spawning` 1,772 of the 1,948) are dominated by sites
    that are not evidence of absence.
  - Same class, smaller: `Salmon (General)` (13 sites), `Unidentified Species` (50) and
    `Unidentifiable Trout - only fry` (7) are read as "did not catch CH/BT". None of them can rule
    the species out. This is knowledge#18's lesson: classify against the source's code table.
  - Fix: count a site as an absence only when `nfc` is TRUE, or when `species_list` is non-empty
    and names no generic or unidentified taxon that could be the species. Stop or report on any
    other shape.

- **[bug — crash]** `data-raw/habitat_validate.R:196-211` (`stage_rows`):
  `data.frame(stage = "spawn", species_code = obs$species_code[obs$is_spawn], ...)` raises
  *"arguments imply differing number of rows: 1, 0"* whenever a subset is empty. The scalar `stage`
  cannot recycle against a zero-length column.
  - Reproduced: `--bundles=default:fresh_default --wsgs=UPCE --species=CH --buffers=0` dies in
    `stage_rows` after `summary.csv` and `totals.csv` are written, with no `misses*.csv` and no
    `stamp.txt`.
  - It fires for any run where a species has no spawn-staged (or no rear-staged, or no) locations.
    In the live 5-WSG set that covers COTR BT spawn, PINE CH spawn, UPCE BT/CH, so every held-out,
    single-WSG or single-species run is exposed.
  - Fix: `rep(stage, n)` or return a typed 0-row frame.

- **[bug — mislabel, silently wrong number]** `data-raw/habitat_validate.R:198-200`: `misses.csv`
  stage `any` counts `miss_reason_rear`, which keys on `rearing_any`.
  - The summary and totals `any` stage define capture as `n_habitat = spawning | rearing_any`, so a
    spawning-only location is "captured" in `totals.csv` and a miss in `misses.csv` under the same
    stage label.
  - Measured: `default` CH `any` has `n_habitat` 224 in totals but 222 `captured` in misses.csv.
    The 2 spawning-only locations appear there with a rear miss reason, as if the model missed
    them.
  - Fix: label that block `rear_all` (or similar), or derive the `any` reason as NA when either
    stage captured.

- **[fragile — one fact derived twice]** `R/lnk_habitat_validate.R:550-554` vs `:599-600, :613-619, :649`:
  the spawn predicate's lower gradient bound comes from `parameters_fresh$spawn_gradient_min`
  (`.lnk_hv_sp_params` → `frs_habitat_predicates()`, `sprintf("s.gradient >= %s", spawn_gradient_min)`).
  - The relaxation value and `gradient_min_spawn` (used for `gradient_below_min`) come from
    `rng$spawn$gradient[1]`, which `frs_params()` hardcodes to `0` (`fresh/R/frs_params.R:489`,
    `ranges$gradient <- c(0, gradient_max)`).
  - Today every `spawn_gradient_min` in both bundles is 0, so the two agree by coincidence.
  - Once a bundle sets a positive `spawn_gradient_min`, which is a live fresh-owned parameter and
    the kind #284 calibrates, the following go wrong silently:
    - relaxing gradient to 0 still fails the predicate, so `pred_spawn_g` / `_gw` are FALSE;
    - every spawn gradient miss (above max or below min) falls through to `rule_excludes` or
      `fails_width`;
    - `gradient_below_min` never fires for gradients in `[0, min)`.
  - Fix: take the spawn relax and below-min value from `spawn_gradient_min` (the value the
    predicate uses).

- **[fragile — inconsistent pair under one row]** `R/lnk_habitat_validate.R:701-731` vs `:458-497`:
  capture flags are buffered (`buffer_m` extends spawning / rearing upstream), but the absence
  counts are always evaluated on the point's own segment.
  - The `buffer_m = 100` summary rows therefore pair a buffered capture rate with an unbuffered
    false-positive count.
  - The driver writes both side by side for each buffer (summary.csv, totals.csv). A precision and
    recall read at buffer 100 flatters the buffer: capture rises, and the absence false-positive
    rate cannot.
  - Same shape as round-1 finding 3 (paired columns with different definitions).
  - Fix: buffer the absence flags the same way, or blank `n_absence_*` on `buffer_m > 0` rows and
    say so in the docs.

- **[fragile — stale artifacts beside fresh ones]** `data-raw/habitat_validate.R:66-67, 244-276, 314`:
  the default output directory is fixed (`data-raw/logs/habitat_validate_283/`, a committed-log
  location) and nothing is cleared before writing.
  - A one-bundle rerun never rewrites `diff.csv`, so the previous two-bundle diff survives beside
    the new `summary.csv` and a `stamp.txt` describing only one bundle.
  - A run that dies before the stamp leaves the previous run's `stamp.txt` describing new CSVs.
    Examples are the `stage_rows` crash above, or `--buffers` without 0, where `keys[[1]]` is out
    of bounds.
  - `--buffers` without 0 also writes `misses.csv` / `misses_binned.csv` as the single line `""`
    (`write.csv(NULL)`).
  - Fix: delete the known outputs at start (or write to a fresh subdirectory), and require 0 in
    `--buffers` when misses or the diff are produced.

Checked and clean:
- the `in_uhc` indicator types;
- log table shape in both schemas (`config_name`, `date_start` never NULL, `fresh_version`);
- the diff guard (fires on differing retained keys; identical here);
- `n_cand` type;
- SQL interpolation (schema regex in the function; driver schema is operator input);
- temp-table reuse across the four in-session runs;
- dedup naming via `tapply` name lookup (locale-safe);
- totals grouping (`config_name` never NA).

/Users/airvine/Projects/repo/link/planning/active/review-round2.md
