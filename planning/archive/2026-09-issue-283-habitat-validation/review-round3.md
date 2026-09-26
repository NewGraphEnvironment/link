# Code-check round 3 — lnk_habitat_validate() + data-raw/habitat_validate.R (#283)

Reviewer: subagent, 2026-09-26. Diff: `diff_r3.patch`. Everything run from a copy of the repo
(`scratchpad/linkcopy3`, fixture schema renamed `zz_lnk_validate_rev3`):

- `NOT_CRAN=true devtools::test(filter = "habitat_validate")`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 81 ]`.
- Driver, `--bundles=default:fresh_default,bcfishpass:fresh --wsgs=MORR,BULK,COTR` with
  `LNK_KNOWLEDGE_DIR` set, output to scratch. Cross-checked `misses.csv` against `totals.csv`
  (buffer 0) for all 12 bundle x species x stage rows. Captured counts agree exactly
  (`any` = `n_habitat`, `spawn` = `n_spawning`, `rear` = `n_rearing_any`). So do the non-`no_segment`
  totals (= `n_obs`) and `no_segment` (= `n_unattached`). `not_accessible` is below
  `n_inaccessible` only where an inaccessible location is captured, which is the accepted
  habitat-vs-access gate difference.
- Driver, `--species=CO --wsgs=MORR` with `LNK_KNOWLEDGE_DIR` set: crashes (finding 1).

## The mechanisms

Rounds 1 and 2 found instances of three mechanisms.

**M1. One definition, re-implemented per consumer.** Each derived fact is computed separately by
every consumer, and nothing but coincidence kept the copies in step. The facts: *captured*,
*accessible*, *attached*, *stage*, *stage minimum*, *species identity*, *bundle identity*, and
*population* (which WSGs, and which points count as on the network). The consumers: the
observation SQL, the absence SQL, the predicate relaxation, the miss labels, the summary, and the
driver's totals, misses and diff.
- R1: `in_uhc` ignored the indicator the overlay uses; `n_absence_rearing` did not match `n_rearing`.
- R2: the misses `any` stage did not match the totals `any` stage; the spawn floor was taken from
  two sources; absences were unbuffered while observations were buffered.

The fixes that held replaced a copy with a single source that both consumers read
(`.lnk_hv_buffered()`, `.lnk_hv_stage_min()`). Findings 2, 3 and 4 below are copies that still
exist: the network distance, the bundle key, and the WSG population.

**M2. A value normalised at one end only.** `integer64` from the DB was treated as integer, and
`toupper(NULL)` was treated as `NULL`. Finding 5 is the same thing: species codes are uppercased
on three paths and not on a fourth.

**M3. The shape of "nothing" differs by constructor.** A scalar cannot recycle into a 0-row frame,
`do.call(rbind, list())` returns `NULL`, and `sprintf()` or `paste0()` given a zero-length
argument returns `character(0)`. The code also treats NA, 0, `NULL` and `character(0)` as the
same thing in places. Finding 1 and part of finding 6 are this.

## Findings

- **[bug — crash]** `data-raw/habitat_validate.R:169-177`: when none of `--species` has a FISS
  rule, `out <- do.call(rbind, lapply(sp_abs, ...))` is `NULL` and `attr(out, ...) <-` aborts.
  - Reproduced: `--species=CO` with `LNK_KNOWLEDGE_DIR` set dies with *"attempt to set an
    attribute on NULL"* in `fiss_absences()`. The output directory is left empty, because the
    outputs were unlinked at start.
  - Same mechanism, silent form. With `--species=CH,CO`, CO has no rule, yet it gets
    `n_absence*` = **0** in summary, totals and diff (`.lnk_hv_absences()` zero-fills the grid).
    That 0 means "not assessed" and reads as "no absence sites". Only a `message()` says otherwise.
  - Fix: return `NULL` when `sp_abs` is empty. Set `n_absence*` to `NA` for species outside
    `sp_abs` after the call, or pass absences only for those species and NA-fill the rest.

- **[fragile — two definitions of "on the network"]** `data-raw/habitat_validate.R:146`: absence
  sites snap to the nearest FWA stream within **150 m**. Observations are kept only for
  `match_type` A/B, which bcfishobs defines as *"stream; within 100m"*.
  - Measured on the knowledge snapshots: of 7,236 sampled sites that snap, **1,247 (17%)** are
    100–150 m from their stream. That is outside the distance at which an observation would be
    admitted.
  - These are the sites most likely to sit on an unmapped tributary, where the snapped segment
    belongs to another stream. So they inflate `n_absence_spawning` / `_rearing` (the
    false-positive check) with points the observation side would have refused.
  - Fix: snap within 100 m to match A/B (or state the asymmetry in the stamp).

- **[fragile — bundle identity keyed two ways]** `data-raw/habitat_validate.R:200, 259, 272`: each
  file keys a bundle differently.
  - `runs[[..]]$bundle` is the **config name** only, and `misses.csv` / `misses_binned.csv` are
    keyed on it.
  - `summary.csv` / `totals.csv` key on `schema` + `config_name`, and `diff.csv` on
    `config:schema`.
  - Two bundles sharing a config therefore write identically labelled, inseparable rows to both
    misses files. Example: `default:fresh_default,default:<recalibrated schema>`, which the log
    check allows and which is the natural #284 before/after comparison.
  - Fix: `bundle = paste0(config, ":", schema)`, as `diff.csv` does.

- **[fragile — totals and diff over different populations]** `data-raw/habitat_validate.R:87-101,
  209-217`: each bundle is scored over its **own** WSGs, and `totals.csv` sums over them. Only
  `diff.csv` is restricted to the shared set.
  - In the default no-`--wsgs` run the sets differ: `fresh_default` has 55 access WSGs and `fresh`
    has 59, with 51 shared.
  - Only in `fresh_default`: ADMS, KOTL, LARL, SLOC.
  - Only in `fresh`: BOWR, ELKR, KOTR, LNTH, MCGR, THOM, UNTH, UTRE.
  - The two bundles' totals rows are therefore different populations: different `n_obs`, km and
    absences. They read as a bundle comparison, and `n_wsg` is the only tell.
  - Fix: with two bundles, score both on the intersection (or also write shared-only totals).

- **[fragile — silent zero]** `R/lnk_habitat_validate.R:209-210, 331`: the code uppercases
  `species`, `names(species_obs)` and `absences$species_code`, but not the **values** of
  `species_obs`.
  - `species_obs = list(BT = c("bt", "dv"))` passes `stopifnot`, joins against bcfishobs' uppercase
    `species_code` (`sp.obs_species = o.species_code`), and retains zero observations with no error.
  - The summary then reports `n_obs` 0, which reads as "no observations".
  - Fix: `species_obs <- lapply(species_obs, toupper)`.

- **[fragile — stamp]** `data-raw/habitat_validate.R:322-356`: two paths can lose the stamp.
  - The stamp queries `<schema>.log` unconditionally, while `lnk_habitat_validate()` explicitly
    accepts a schema with no `log` table (`.lnk_hv_check_log` returns `character(0)`). So such a
    schema scores, writes every CSV, and then dies before `stamp.txt`, leaving outputs with no
    stamp.
  - `attr(absences, "knowledge_sha")` comes from `system2(..., stdout = TRUE)`. On a
    `LNK_KNOWLEDGE_DIR` that is not a git checkout, that returns `character(0)` with a *warning*,
    which `tryCatch(error = )` does not catch. `sprintf()` given a zero-length argument then
    returns `character(0)`, and the whole absences line vanishes from `stamp.txt` silently.
  - Neither fires today: both schemas have a `log` and knowledge is a git repo.
  - Fix: guard the log query with `dbExistsTable`, and `if (!length(sha)) NA` the sha.

Notes (not findings):
- The roxygen says the default A/B filter leaves out "the C-E waterbody matches". C is
  *"matched - stream; 100-500m; lookup"* (31,551 rows), a stream match beyond 100 m, not a
  waterbody match. The code is right; the sentence is wrong.
- `fresh installed ... @ no recorded sha` appeared in the stamp on this machine. That is
  `.lnk_pkg_git_sha()` against a local install, not this diff.

## Enumeration

Every fact derived in more than one place, every possibly-empty constructor, and every value the
relaxation or labels take from outside the predicate. ✓ = consistent (measured where marked).

### M1 — one fact, several derivations

| Fact | Where it is derived | Consistent? |
|---|---|---|
| accessible | obs SQL `coalesce(access IN (1,2), false)`, NA if unattached (:465, :506); absence SQL, same expression, unattached dropped (:728, :764); `lnk_rollup_wsg` `accessible_km` `access IN (1,2)`; miss label `!accessible` | ✓. Rollup's inner join to habitat vs obs' left join to access: measured 0 segments lacking a habitat or access row in either schema |
| spawning capture | obs + absences via `.lnk_hv_buffered(h.spawning)`; `spawning_km` on `h.spawning`; `miss_reason_spawn` keys on `obs$spawning` | ✓ (one helper) |
| rearing (stream) | obs + absences `h.rearing` (buffered helper); `rearing_km` on `h.rearing` | ✓ |
| rearing_any | obs + absences `h.rearing OR h.lake_rearing OR h.wetland_rearing`; `miss_reason_rear` keys on it; predicate rear stage ORs `pr$rear`, `pr$lake_rear`, `pr$wetland_rear` | ✓. `streams_habitat_<sp>` has exactly those three rearing columns |
| habitat (`any`) | summary `n_habitat = spawning \| rearing_any`; totals `share_habitat`; misses `any` = NA if spawning else rear reason | ✓ measured, 12/12 rows |
| attached / n_obs | summary `!is.na(id_segment)`; absences `id_segment IS NOT NULL`; `no_segment` ⇔ captured NA ⇔ id_segment NA | ✓ measured (`no_segment` = `n_unattached`) |
| attach rule | obs LATERAL (:444-457) and absence LATERAL (:736-748): two copies of one SQL | ✓ identical predicates and ORDER BY |
| buffer window | obs and absences share `.lnk_hv_buffered`; accessibility is always own segment | ✓ |
| stage | `.lnk_obs_stage` → dedup OR → summary and misses both read `is_spawn` / `is_rear`; absences stage-less, same value on every stage (documented) | ✓ |
| species admission | obs: `spec` (presence ∩ species) × `species_obs`; absences: filtered on the same `spec` (WSG, species) | ✓ |
| species pooling (BT = BT+DV) | function: `species_obs` default; driver FISS rule: regex `Bull Trout\|Dolly Varden` | ✓ today. Two lists that agree because the driver never overrides `species_obs` |
| species case | `species`, `names(species_obs)`, `absences$species_code` uppercased; `species_obs` values not | ✗ **finding 5** |
| on-network distance | obs: bcfishobs A/B ≤ 100 m; absences: nearest FWA ≤ 150 m | ✗ **finding 2** |
| counting unit | obs: one per species × blk × metre; absences: one per site | differs, but each rate is within its own set. Not a finding |
| spawn gradient floor (relax + `gradient_below_min`) | `.lnk_hv_stage_min` ← `.lnk_hv_sp_params` `spawn_gradient_min` (NA/NULL → 0), the same assembly as `frs_habitat_classify` → `frs_habitat_predicates` | ✓ single source (R2 fix) |
| rear gradient floor | link literal `0`; fresh literal `c(0, rear_g[2])` on the rules path; CSV path has no lower bound (relaxing is harmless there) | ✓. Tracks the predicate, not `parameters_fresh$rear_gradient_min` (0 in both bundles, read by no fresh code). That is correct: fresh would ignore a non-zero value, and so should the relaxation |
| stage width floor | `ranges$<stage>$channel_width[1]`; predicate inherits the same range on the rules path, the CSV path and `lake_rear` / `wetland_rear` (`size_rear`) | ✓. Every rule-level `channel_width` in both bundles' `rules.yaml` is `[0, 9999]` (18 + 12), and none sets a rule-level `gradient` |
| inclusive bounds | predicate `BETWEEN` / `>=`; relaxation sets the value to the bound | ✓ |
| `width_null` label | `is.na(channel_width)`, the column the predicate reads | ✓. NULL gradient: 0 rows in both schemas, so no gradient analogue is needed |
| UHC indicator | validate `u.spawning = 1`; overlay `lower(trim(x::text)) IN ('true','t','1')` | ✓. Loaded values are int {-4,-1,1,NA} in both bundles |
| `overlay_applied` | same expression as `lnk_pipeline_classify` | ✓ |
| obs exclusions | `%in% c(TRUE, "t")` on `data_error` / `release_exclude`, same as `.lnk_pipeline_prep_observations` | ✓ (the Releases Database drop is extra and documented) |
| config check vs run_logged vs stamp count | check: latest row per WSG; `run_logged` and stamp: any row | ✓. No NULL `date_start` rows (measured), so `DESC` NULLS FIRST cannot pick a null |
| log existence | function tolerates a missing log; stamp does not | ✗ **finding 6** |
| cost where species absent | `n_obs` 0 by `spec`; cost from habitat rows | ✓ measured: no `streams_habitat_ch/bt` rows in any species-absent WSG in either schema (24 CH, 3 BT WSGs) |
| present but unmodelled | presence says present, no habitat rows → flags FALSE | ✓ measured: none in either schema (unguarded) |
| bundle identity | summary/totals: schema + config_name; diff: config:schema; misses: config | ✗ **finding 3** |
| WSG population | totals: per-bundle WSGs; diff: shared WSGs | ✗ **finding 4** |
| observations identical across bundles | diff guard on species + WSG + observation_key, buffer 0 | ✓. Dedup representative uses locale-dependent `order()`, same session for both |
| misses population | buffer-0 runs only; `stage_rows` uses the same `is_spawn` / `is_rear` | ✓ |
| bins vs bounds | gradient bins `(a,b]` match `<= max`; width bins `[a,b)` match `>= min` | ✓ (display only) |

### M3 — "nothing" shapes

| Site | Empty input | Result |
|---|---|---|
| `.lnk_hv_spec` `do.call(rbind, ...)` | no present species | typed 0-row frame ✓ |
| `.lnk_hv_spec` `obs_species = unique(species_obs[[sp]] %\|\|% sp)` | `species_obs = list(BT = character(0))` (passes `stopifnot`) | `data.frame` errors 1 vs 0 rows: loud, not silent |
| `lnk_vd_excl` `data.frame(observation_key = as.character(keys))` | no exclusions | 0-row ✓ |
| UHC | NULL or 0-row | typed 0-row ✓ |
| `.lnk_hv_dedup` | 0 rows | early return, columns added ✓ |
| `.lnk_hv_predicates` `rep(NA, nrow(obs))` / `res` NULL | nothing attached | NA columns; `paste(NULL...)` → `character(0)` → no match ✓ |
| `.lnk_habitat_miss_reason` scalar `gradient` default | length 0 | recycles to 0 ✓ |
| `.lnk_hv_absences` `count_by` | 0 attached absences | tapply NA → 0 ✓ (tested) |
| `.lnk_hv_summary` per-cell `data.frame(scalars)` | empty cell | 1-row, `share` NA ✓ |
| outer `cbind(data.frame(schema = scalar, ...), summary)` | summary has ≥ 3 rows by construction | ✓ |
| driver `split_csv(NULL)` / `toupper(NULL)` | no `--wsgs` | `length()` test ✓ |
| driver `--bundles=` (empty) | `do.call(rbind, list())` → NULL, `nrow(NULL) > 2L` → `if (logical(0))` | loud but opaque error. Not a finding |
| driver `--buffers=` (empty) | `numeric(0)` → `!0 %in%` stop ✓ | |
| `fiss_absences` `do.call(rbind, lapply(sp_abs, ...))` | no species with a rule | NULL → `attr<-` crash ✗ **finding 1** |
| `fiss_absences` per-species frame | species with 0 absence sites | `rep(sp, nrow(s))` ✓ |
| `.lnk_hv_absences` zero-fill | species with no rule | 0 instead of NA ✗ **finding 1** |
| `stage_rows` `pick` | empty spawn/rear subset | `rep(stage, nrow(d))` ✓ (R2 fix) |
| misses/binned `ifelse` / `cut` on 0 rows | no misses | 0-length columns into a 0-row frame ✓ |
| stamp `sprintf(..., knowledge_sha)` | `system2` → `character(0)` | line dropped silently ✗ **finding 6** |
| stamp log query | no `log` table | error after CSVs are written ✗ **finding 6** |

### Values the relaxation and labels take from outside the predicate's own input

| Value | Source | Same as the predicate? |
|---|---|---|
| spawn gradient relax / `gradient_min_spawn` | `spawn_gradient_min` via `.lnk_hv_sp_params` | ✓ |
| rear gradient relax / `gradient_min_rear` | literal 0 | ✓ (fresh's literal 0) |
| spawn / rear width relax | `ranges$<stage>$channel_width[1]` | ✓ |
| `width_null` | segment `channel_width` | ✓ |
| `not_accessible` | `streams_access` | differs from the habitat gate: accepted tradeoff |
| model | cw only | accepted tradeoff |
| `format(x, scientific = FALSE)` (7 significant digits) vs predicate `%.10g` | shipped minimums (0, 0.0025, 1.5, 2, 4) are exact under both | ✓ today; a minimum with more than 7 significant digits could round below the bound |
