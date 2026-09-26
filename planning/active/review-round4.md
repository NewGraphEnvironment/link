# Code-check round 4 — terminal verification of the round-3 fixes (#283)

Reviewer: subagent, 2026-09-26. Diff: `diff_r4.patch`. Everything was run from a copy
(`scratchpad/linkcopy4`, fixture schema renamed `zz_lnk_validate_rev4`). The repo was not touched,
apart from this file.

What was run:
- `NOT_CRAN=true devtools::test(filter = "habitat_validate")`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 82 ]`.
- Mutation: with `species_obs <- lapply(species_obs, toupper)` removed, the new case test fails
  (`test-lnk_habitat_validate.R:281`, FAIL 1). The guard fires.
- Driver, all exit 0, outputs in `scratchpad/r4out/{A..E}`:
  - **A**: two bundles, `--wsgs=COTR,MORR --buffers=0,100`, knowledge set.
  - **B**: one bundle, the same WSGs, knowledge unset. No `totals_shared.csv` or `diff.csv` is
    written, and no error is raised.
  - **C**: two bundles, `--species=CH,CO`, knowledge set.
  - **D**: one bundle, `--species=CO`, knowledge set. This is the round-3 crash case, and it no
    longer crashes.
  - **E**: one bundle, knowledge copied into a directory that is not a git repo. The stamp reads
    `knowledge @ not a git repo`.
- Cross-checks on A:
  - `totals.csv` equals the per-group sums of `summary.csv` for `n_obs`, `n_habitat` and
    `n_absence`.
  - `misses.csv` `captured` equals `n_habitat` / `n_spawning` / `n_rearing_any` in 12 of 12 rows.
  - `misses.csv` row totals equal `n_obs + n_unattached` in 12 of 12 rows.
  - `totals_shared.csv` is identical to `totals.csv`, as it must be when `--wsgs` is given.
  - Both misses files are labelled `default:fresh_default` / `bcfishpass:fresh`.
- On C, CO carries `n_absence*` = NA through `summary.csv`, `totals.csv` and `totals_shared.csv`.
  CH carries its counts. `diff.csv` has no absence columns, so NA cannot reach it.

## Findings

- **[fragile — silent zero, WSG axis]** `R/lnk_habitat_validate.R:767-780`, `data-raw/habitat_validate.R:109, 377-383`.
  This is round 3's M3 mechanism, finding 1, moved from the species axis to the WSG axis.
  - The FISS snapshots cover **5** WSGs: `knowledge/data/{cotr,lnth,pine,unth,upce}/fiss_sites_*_all.csv`.
  - After snapping, absence rows land in **50** WSGs, mostly as edge spillover (for example PARS
    148 and LPCE 607). MORR receives 0.
  - `.lnk_hv_absences()` zero-fills the whole `aoi × species` grid. So every WSG outside the
    snapshots reports `n_absence = 0`, and a partly covered WSG reports a partial count. Run A
    shows MORR CH `n_absence 0` beside COTR CH `68`. That 0 means "not in the FISS snapshot" and
    reads as "sampled, no absence sites".
  - Pooled rates in `totals` are unaffected, because 0/0 WSGs add nothing. Per-WSG rows, `n_wsg`
    and any per-WSG absence rate are affected.
  - Nothing records the covered set. The stamp says only "all WSGs, before presence".
  - Fix: record the snapshot WSGs (from the file names) in the stamp. Then either NA `n_absence*`
    in `summary.csv` for WSGs outside that set, or state in the header that n_absence is 0 there
    and should not be read.
- **[minor — stamp states a falsehood]** `data-raw/habitat_validate.R:170, 377`. Fix 1 made
  `fiss_absences()` return `NULL` when no requested species has a rule. The stamp then treats
  `is.null(absences)` as `"absences: none (LNK_KNOWLEDGE_DIR unset)"`.
  - Reproduced in run D (`--species=CO` with `LNK_KNOWLEDGE_DIR` set). The stamp claims the
    variable was unset.
  - In the same situation, `summary.csv` has no `n_absence*` columns at all (D), while run C has
    them as NA. "Not assessed" therefore arrives in two shapes, depending on whether any other
    species had a rule.
  - Fix: branch the stamp on `nzchar(Sys.getenv("LNK_KNOWLEDGE_DIR"))`, and say "no requested
    species has a FISS absence rule".
- **[minor — exported function keeps the species-axis zero]** `R/lnk_habitat_validate.R:767-773`,
  roxygen `:128-133`. The driver now NAs species without a rule. `lnk_habitat_validate()` itself
  still returns `n_absence*` = 0 for any `species` that has no rows in `absences`.
  - A direct caller who passes CH-only absences with `species = c("CH", "CO")` gets CO = 0.
  - The function cannot tell "assessed, none found" from "not assessed". The roxygen should say
    that a species absent from `absences` is reported as 0, not NA, and that the caller must NA it.
    The alternative is to NA-fill species with no rows and accept that "assessed, zero sites" also
    becomes NA.

Notes (not findings):
- `data-raw/habitat_validate.R:244`: the "share no WSGs" `stop()` moved up from the diff block. It
  still fires after `summary.csv` / `totals.csv` are written and before `stamp.txt`. The diff-block
  observation-identity `stop()` (:313) fires after the misses files. Both are loud, but both leave
  outputs without a stamp, which is the shape round 3's finding 6 closed for the log.
  `bundle_wsgs` is known before any scoring, so the disjointness check could run there.
- `data-raw/habitat_validate.R:323-326`: `diff.csv` selects each side by `schema` only, while its
  labels are `config:schema`. Two bundles on one schema, for example
  `default:fresh_default,bcfishpass:fresh_default` over unlogged WSGs, which the log check allows,
  give 4 rows per key.
  - The deltas are all 0. That is correct: capture is a function of the schema, not the config.
  - So the rows are duplicated but not wrong. A guard that the two schemas differ would close it.
- The stamp for a log table with no rows for the scored WSGs prints `(fresh NA, NA to NA)`. That
  happens for `fresh_default` over COTR,MORR. It is cosmetic, because the preceding "0 with a
  run-log row" is correct.
- Two edge cases in `knowledge_sha`. A `LNK_KNOWLEDGE_DIR` nested inside a different git checkout
  would report that checkout's sha. A missing `git` binary reads as "not a git repo".
- `make_totals` now returns NA for a column that is all-NA within a group. That applies to km too,
  where the old code summed with `na.rm` to 0. km is NA only where a species has no habitat rows
  in any WSG of the group. That was measured: no WSG × species in either schema has habitat rows
  with zero spawning. So NA means "not modelled", which matches the per-WSG summary. This is
  consistent, not a regression.

## Enumeration, re-walked against the current code

### M1: one fact, several derivations

| Fact | Now | Consistent? |
|---|---|---|
| accessible | obs `:467`, NA if unattached `:508`; absences `:730`, unattached dropped `:766`; rollup `access IN (1,2)` | y |
| spawning capture | `.lnk_hv_buffered(h.spawning)` in obs and absences | y |
| rearing (stream) | `.lnk_hv_buffered(h.rearing)` in obs and absences | y |
| rearing_any | obs `:498`, absences `:761`, predicate rear stage `:632`, `miss_reason_rear` `:700` | y |
| habitat (`any`) | summary `:805`; misses `reason_any` `:259`. Measured 12/12 | y |
| attached / n_obs | summary `:796`; absences `:729`; `no_segment` ⇔ NA. Measured totals = n_obs + n_unattached | y |
| attach rule | obs LATERAL `:446-459` and absence LATERAL `:738-750`: identical predicate and ORDER BY | y |
| buffer window | one helper `:362`; accessibility is the own segment | y |
| stage | `.lnk_obs_stage` → dedup → summary + `stage_rows` | y |
| species admission | `spec` shared by obs `:427` and absences `:719` | y |
| species pooling (BT = BT+DV) | function default `species_obs`; driver regex `Bull Trout\|Dolly Varden` | y (still two lists that agree; the driver never overrides `species_obs`) |
| species case | `species` `:210`, `species_obs` values `:211` (fix 5), names `:212`, `absences$species_code` `:718`; driver `toupper` `:69`. Mutation-tested | **y (fixed)** |
| on-network distance | obs A/B ≤ 100 m; absences `st_dwithin(..., 100)` `:148` | **y (fixed)** |
| counting unit | per-location vs per-site, each rate within its own set | y (not a finding) |
| spawn gradient floor | `.lnk_hv_stage_min` ← `.lnk_hv_sp_params` | y |
| rear gradient floor | literal 0 `:575` | y |
| stage width floor | `ranges$<stage>$channel_width[1]` | y |
| inclusive bounds | relax to the bound; `BETWEEN` / `>=` | y |
| `width_null` label | `is.na(channel_width)` `:683` | y |
| UHC indicator | `u.spawning = 1` / `u.rearing = 1` | y |
| `overlay_applied` | `:243-244` | y |
| obs exclusions | `%in% c(TRUE, "t")` `:393-394` | y |
| config check vs run_logged vs stamp count | check: latest per WSG; `run_logged` and stamp: any row | y |
| log existence | function `:298`; stamp `:348` (fix 6) | **y (fixed)** |
| cost where species absent | NA km per WSG; totals NA if all-NA in the group | y (see note) |
| present but unmodelled | none in either schema (from round 3) | y (unguarded, unchanged) |
| bundle identity | summary/totals: schema + config_name; misses `:205` config:schema (fix 3); diff labels config:schema but selects by schema `:323-326` | **y (fixed)**, residual in notes |
| WSG population | totals: per-bundle; `totals_shared.csv` and diff: the same `shared` `:242` (fix 4) | **y (fixed)** |
| observations identical across bundles | guard `:308-317` over `shared` | y |
| misses population | buffer-0 runs, same `is_spawn` / `is_rear` | y |
| bins vs bounds | display only | y |
| absence "assessed" (new fact) | driver: `names(attr(absences, "n_absence_sites"))` `:213`; function: zero-fill `:767-773` | **n** — species axis fixed in the driver only (finding 3); WSG axis not handled (finding 1) |

### M3: shapes of "nothing"

| Site | Empty input | Result now |
|---|---|---|
| `.lnk_hv_spec` rbind | no present species | typed 0-row, y |
| `.lnk_hv_spec` `species_obs[[sp]]` = `character(0)` | `list(BT = character(0))` | loud `data.frame` error, y (unchanged) |
| `lnk_vd_excl` | no exclusions | 0-row, y |
| UHC | NULL / 0-row | typed 0-row, y |
| `.lnk_hv_dedup` | 0 rows | early return, y |
| `.lnk_hv_predicates` | nothing attached | NA columns, y |
| `.lnk_habitat_miss_reason` scalar default | length 0 | recycles, y |
| `.lnk_hv_absences` `count_by` | 0 attached | 0, y (tested) |
| `.lnk_hv_summary` per cell | empty cell | 1-row, share NA, y |
| outer `cbind` | ≥ 3 rows | y |
| driver `split_csv(NULL)` / `toupper(NULL)` | no `--wsgs` | `length()` test, y |
| driver `--bundles=` empty | NULL → opaque error | loud, not a finding (unchanged) |
| driver `--buffers=` empty | stop, y | |
| `fiss_absences` rbind, no species with a rule | now `return(NULL)` `:170` | **y (fixed; run D exits 0)**, but see finding 2 on how the stamp reads the NULL |
| `fiss_absences` per-species frame | 0 sites | `rep(sp, 0)`, y |
| zero-fill for a species with no rule | driver NAs it `:211-215`; NA survives summary, totals, totals_shared (run C) | **y (fixed in the driver)**; the function still returns 0 (finding 3) |
| zero-fill for a WSG outside the FISS snapshots | 0 | **n** (finding 1) |
| `make_totals` all-NA column | NA (was 0) | y |
| `shared` with one bundle | `Reduce(intersect, list(w))` = w; only used when there are 2 bundles | y |
| `stage_rows` `pick` | empty subset | y |
| misses / binned on 0 rows | 0-row frame | y |
| stamp `knowledge_sha` | `character(0)` → `"not a git repo"` `:186` | **y (fixed; run E)** |
| stamp log query | no `log` → "no run log" `:348` | **y (fixed)** |
| stamp log, zero matching rows | `string_agg` NULL → "NA" | y (cosmetic) |
| stamp `absences` NULL | knowledge set but no rule → "LNK_KNOWLEDGE_DIR unset" | **n** (finding 2) |

### Values the relaxation and labels take from outside the predicate

| Value | Source | Same as the predicate? |
|---|---|---|
| spawn gradient relax / `gradient_min_spawn` | `spawn_gradient_min` via `.lnk_hv_sp_params` | y |
| rear gradient relax / `gradient_min_rear` | literal 0 | y |
| spawn / rear width relax | `ranges$<stage>$channel_width[1]` | y |
| `width_null` | segment `channel_width` | y |
| `not_accessible` | `streams_access` | accepted tradeoff |
| model | cw only | accepted tradeoff |
| `format(x, scientific = FALSE)` vs `%.10g` | shipped minimums are exact | y (unchanged; a minimum with more than 7 significant digits would round) |

## Verdict

The six round-3 fixes hold and none regressed. Totals, totals_shared, diff and misses agree with
each other and with the summary on the measured runs. The remaining defect is the same "not
assessed reads as 0" mechanism on the WSG axis (finding 1), plus the stamp and API wording that go
with it (findings 2 and 3).
