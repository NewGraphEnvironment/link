# link

Experimental package — breaking all the time and loving the learning curve. Stream-network habitat-classification tooling layered over `fresh`. Under active development; APIs and outputs change without notice.

> **Read [`RUNBOOK.md`](RUNBOOK.md) first.** It is the durable mental model of the barrier → access → mapping_code machinery (what feeds what, where each rule lives, the gotchas). This `CLAUDE.md` carries conventions + status; the RUNBOOK carries the *mechanics*. Don't re-derive the system from source each session — read the runbook, and update it in-commit when the mechanics change.

## Repository Context

**Repository:** NewGraphEnvironment/link
**Primary Language:** R
**Prefix:** `lnk_`
**Branch:** `main` (current version: `DESCRIPTION` / [`NEWS.md`](NEWS.md))

## Status (2026-10-01) — per-WSG `cw`/`mad` habitat model threaded (#286)

**Each bundle's `parameters_habitat_method.csv` reaches fresh as `params_method`.**
- **The table:** all `cw`, a frozen copy of bcfishpass `example_newgraph`. Putting a
  group on `mad` is a reviewed row edit.
- **`mad_m3s`:** on the working streams only, never persisted.
- **fresh pin:** v0.36.2 (floor 0.35.0). Cyphers must be re-prepped before the next
  dispatch: the preflight asserts the argument and hard-fails otherwise.
- **Mechanics:** RUNBOOK §7 "Channel width or discharge, per watershed group". Evidence:
  `data-raw/logs/params_method_286/`.

**Facts not worth re-deriving:**
- **Never give a bundle file `source: https://github.com/smnorris/bcfishpass` unless you
  want it csv-synced.** `sync_bcfishpass_csvs.R` selects on that exact string and
  auto-merges byte drift. A frozen copy uses another `source` plus `derived_from`.
- **A `mad` group with no discharge loses all stream habitat silently.** BULK has none.
  Waterbody rules (L/W, `thresholds: false`) inherit nothing under either model, so BT
  keeps wetland rearing under `mad`.
- **fresh 0.36.0 reversed `frs_db_conn()`'s precedence** (`PG*` first). `lnk_db_conn()`
  still reads `PG_*_SHARE` first; on a machine with both groups set they connect to
  different databases.
- **`lnk_habitat_validate()` is cw-only**; a follow-up is drafted in the #286 archive.

## Status (2026-09-29) — #284 step 5: BT `rear_gradient_max` 0.1349 scored and held

**Threshold variants are scored on one shared segmentation, never on two full runs.**
- `data-raw/habitat_variants_build.R` models a closure once under `default` into
  `score284_default`, keeps the focal working schemas, and re-classifies each variant
  (a thin bundle, one cell changed) into `score284_<variant>`.
- `data-raw/habitat_variants_score.R` scores each ladder step with the new
  `lnk_habitat_validate_band()`: locations per km on the segments the step moves,
  against the core every step agrees on. Held-out WSGs decide.
- Inputs are data (`data-raw/habitat_score/`). Method and results:
  `research/habitat_thresholds.md`, "Step 5".

**Facts not worth re-deriving:**
- **Power first.** A counts-only check before the build showed the planned held-out set
  could decide one step in six (`data-raw/logs/habitat_score_284/power_windows.*`).
  BT was widened to eight held-out WSGs, and CH dropped: unscorable, spread thin.
- **Result.** Steps to 0.1349 take (ratio 0.60 and 0.71; 0.75 and 0.89
  elevation-adjusted). 0.1449 does not (8 found, 25 expected). The change adds
  1,105 km of BT rearing (+5.8 %) across the 12 WSGs, from 2 % (BABL) to 9 % (KOTL,
  UARL); `habitat_change.csv`.
- **Elevation confounds gradient.** Core BT rearing thins 24.6 → 10.2 per 100 km from
  the low to the high third, and steep bands sit high. Weights instead of cutoffs went
  to knowledge#28, the biology first.
- **The n ≥ 10 floor on locations *found* cannot refuse a band fish avoid.** A floor on
  locations *expected* at the core rate can. Both readings are in `verdict.csv`; they
  agreed here, and the choice is open.
- **Resume trusts nothing it cannot prove.** A base WSG is reused only when its log row
  is clean at this HEAD and its digest sits in the same `--out`; `built.csv` is per
  variant × WSG. Code-check took five rounds to get there (`planning/archive/2026-09-issue-284-step5-scoring/`).
- Loosening a rearing cutoff can **remove** a little rearing (1.1 km against 1,365 km):
  clusters merge.

## Status (2026-09-26, late) — observation validation (#283)

**`lnk_habitat_validate()` scores a run against fish, not against bcfishpass.**
Capture on accessible / spawning / rearing, cost in km, miss reasons from the
bundle's own predicates with gradient and width relaxed, and FISS absences.
Driver: `data-raw/habitat_validate.R --bundles=<config>:<schema>,...`. Method,
baseline and the step-5 command: `research/habitat_validation.md`.

**Facts not worth re-deriving:**
- **fresh#218 is a join artifact, not duplication.** Every persist table is unique
  on `(id_segment, watershed_group_code)`; a bare `id_segment` join fans out 22x
  (#203). Join on the full key and the persist schemas are fine.
- **`default`'s `pipeline.schema` is `fresh`, which the bcfishpass bundle writes.**
  So `schema` is required, and the function stops if `<schema>.log` records a WSG
  under another config. `fresh_default` was built by overriding the schema.
- **CH spawn-staged capture is the overlay.** 237 of 245 locations sit in
  `user_habitat_classification` spawning reaches that `default` forces. Read
  `share_*_outside_uhc`.
- **BT rearing 0.1349 scores in-sample** (it is the P95 of the same locations);
  hold records out via the `observations` argument.
- A FISS site that caught fish but listed no species is **not** an absence. That was
  63 % of BT absences in the first draft. `toupper(NULL)` is `character(0)`, which
  made an absent `--wsgs` select zero WSGs, and only running the driver found it.

## Status (2026-09-25) — per-bundle habitat thresholds (#282); #284 parked

**Thresholds now live in the bundle.** Every bundle declares
`parameters_habitat_thresholds.csv` under `files:`; classify/connect resolve it
from `cfg` and fall back to fresh's copy only for a custom bundle that declares
none. The `bcfishpass` copy is a frozen parity input. Runs log the values in
`<persist>.log_parameters_habitat_thresholds`. `default_tuned` (thin,
`extends: default`) is where #284's calibrated CH/BT values land. RUNBOOK §7
"Where habitat thresholds live" has the details, including which columns are
carried but never applied on link's rules path (edge types; MAD only in groups a
bundle's `parameters_habitat_method.csv` puts on `mad`, #286) and that
`rear_lake_ha_min` needs a rules rebuild.

**`extends:` was broken for provenance until a bundle actually used it.**
Inherited provenance resolved against the child dir (every inherited file
"missing", `config_drift` always TRUE), `config_hash` named inherited files by
absolute path (host-dependent), ignored the parent's `config.yaml`, and a depth-3
chain did not load. All fixed; hashes of non-extends bundles are unchanged.

**Full-run digests are not reproducible on main.** Two identical ADMS runs differ
by one segment: the PSCIS→modelled crossing pick ties when two modelled
candidates share a `linear_feature_id` (`R/lnk_pipeline_pscis_build.R:264-279`).
To compare two code versions, prepare once and re-run classify/connect on the
same schema (`data-raw/logs/habitat_thresholds_282/reclassify.R`). Issue drafted,
awaiting body review.

## Status (2026-09-26, late) — observation pooling is data (#290); #284 step 5 unparked

**Which observation species count as which model species is a bundle tracker now, not code.**
- `configs/default/species_pooling.csv` holds one dated, sourced row per decision, scoped to a region, sub-region or WSG.
- `inst/extdata/wsg_regions.csv` is package-level geography: the region is the first segment of each group's *outlet* wscode.
- `species_groups.csv` lets either side of a row be a group.
- `lnk_species_pooling()` resolves it and knows no species.
- **DV → BT pools in the Fraser, Mackenzie and Columbia/Kootenay, and in the Skeena only above Hazelton** (the sub-region `Skeena above Hazelton`: BULK, MORR, KISP, BABL, BABR, SUST, MSKE, USKE). Everything unlisted is not pooled.
  - **Why the split:** interior DV is a legacy name (the DV share of char records is ~90 % before 1990 and under 15 % after 2000). Skeena DV is not: 86 % or more in every decade, and 85 % of Skeena DV streams were re-sampled and still recorded DV. The Skeena split was the operator's call, 2026-09-27.
  - **The optional `obs_year_max` column** limits a row to records dated in or before a year; undated records do not qualify. It is empty in the seed.
- The state of knowledge lives in `research/species_pooling.md`, with the scenarios from `data-raw/species_pooling_evidence.R`.
- **Do not re-hard-code a species pair anywhere**; add a row.
- **`default_tuned`'s BT `rear_gradient_max` of 0.1349 hangs by a thread.**
  - Under the split, the pooled P95 is 0.1309, which clears the 0.13 line that would give 0.1249 by 0.0009.
  - With no Skeena pooling, or with interior pooling limited to pre-1995 records, it gives 0.1249.
  - #284 step 5 scoring should test both values.

**Facts not worth re-deriving:**
- **The region rule alone moved no #284 or #283 number** (all 55 + 59 WSGs are in pooled regions). **The Hazelton split does move them:** 852 DV records in LSKE, KLUM, LKEL and ZYMO drop out. No #284 verdict changes.
- **Where the new rule bites:** 29 BT-present WSGs in the Nass, Stikine, Taku, Yukon and the coast, which pooled before and do not now.
- **"No tracker" means no pooling in the resolver**, but the validator's list default (global DV→BT) is kept for back-compat. The driver resolves pooling **once**, from the first bundle declaring a tracker, and applies it to both bundles.
- **Two presence tables must agree, WSG by WSG**: the pooling bundle's and each scored bundle's. Both drivers stop if they do not, and the comparison is keyed by WSG, never by row position (review found the row-position version).
- **The #284 obs producer is not bit-reproducible.** A double-precision `sum(length_metre)` gives 1-ulp differences in `candidates.csv` between identical runs. This is pre-existing: #293.
- **Hand-kept `consumed_by` file:line refs drift on every edit above them.** The two new dictionaries are now test-checked with a whole-token match.

## Status (2026-09-26) — v0.51.1: first calibrated threshold in `default_tuned` (#284; step 5 open)

**`research/habitat_thresholds.md` is the staging table for tuning CH/BT numbers.** One
verdict per threshold (observation use vs accessible availability, FISS sites, literature).
One cell moved: BT `rear_gradient_max` 0.1049 → 0.1349. `default` and `bcfishpass` are
untouched, and everything is **unscored** until #283's validator exists. Producers:
`data-raw/query_habitat_thresholds_{obs,fiss}.R`.

**Facts not worth re-deriving:**
- bcfishobs carries **no life stage or activity for BT at all**. DV records are pooled with
  BT as the primary BT evidence (operator call, 2026-09-26: inland DV are bull trout under
  the other name, and coastal biology is treated as equivalent). BT-only is kept beside it
  as `evidence_role = comparison`.
- Observations **are** the pipeline's break points. 99 % sit within 1 m of a segment
  boundary; use the segment *starting* there (upstream), or joins double-match.
- The rearing bridge (`cluster_bridge_gradient`) governs only rearing **above** spawning:
  `.frs_cluster_both()` keeps a cluster with spawning anywhere upstream, with no gradient
  test.
- River polygons with NULL width fail the river rule's `channel_width [0, 9999]` (a
  `BETWEEN`), so they drop out of habitat. There is an unfiled draft in the #284 archive.
- FISS data-submission site data (width, gradient, effort, no-fish-captured) is parsed by
  the private `knowledge` repo. Commit aggregates only here, because link is public.
  `average_gradient_percent` there holds proportions.
- About a third of CH observation locations in `fresh_default` are lower Fraser / coastal
  Skeena (ocean-type runs), so the WSG set is not "interior only".

## Status (2026-09-01) — v0.49.0: provenance gaps closed before the 217-WSG run (#262, #257)

**Two of the four reported gaps were wired and unfed; a third named the wrong
source.** `run_label` has been threaded to the INSERT since #127 — NULL only
because nothing set `LNK_RUN_LABEL`. `.lnk_bcfp_log_current()` has been called at
run open just as long — NULL because it queries `bcfishpass.log` and local docker
fwapg holds **zero** `bcfishpass` tables. Building what the issue literally asked
for would have added code beside working code twice and recorded a wrong value the
third time. **Measure before characterising, even when the issue is your own.**

**New: `run_uid`** (one per dispatch, all hosts) beside `run_id` (one per WSG,
the PK) and `run_label` (operator text). **New `<schema>.log_recompute`** — the
recompute rewrites `streams_access` / `streams_mapping_code`, which is what
ships, and logged nothing. **bcfp pin is tunnel-free**, three tiers, with
`bcfp_pin_source` recording which answered; `bcfp_model_run_id` stays NULL there
because `log.json` has no such key, and that is correct. **`link_dirty` means
something again** (#257).

**Four traps worth not re-learning.** `on.exit()` at an Rscript's **top level
never fires** — measured on both `stop()` and `quit()`; `wsg_recompute_one.R`
already carried two dead handlers, the likely source of #246's 49 orphaned
`zz_lnk_mc_scratch_*` tables. `system2()` shell-quotes the command but pastes
**arguments raw**, so `:(top,exclude)`'s parens were eaten by the shell and the
dirty predicate returned `NA` for every input. **psql does not interpolate
`:'var'` inside a dollar-quoted string** — parameters reach the assertion block
via `set_config`. And an env var **exported on the local leg does not cross
ssh**: `LNK_RUN_UID` had to go into the ssh command string too, exactly as
`LNK_GUARD_DOWNSTREAM` did in #227.

**Both the shell-quoting and the psql one were found by running the code, not by
reading it** — each reads perfectly and fails at run time. So did the biggest
one: an end-to-end model+recompute showed the recompute row landing with
`run_uid` NULL, because the env default was wired into `lnk_pipeline_run()` only.
Every unit test passed the value explicitly and so never exercised the default.

`study_area_verify.sql` now takes `-v run_uid=` and **asserts via `RAISE`**, with
`-v expected_n=` supplied from outside — deriving the expected set entirely from
`fresh.log` is circular, since a WSG that never logged vanishes from "expected".
`data-raw/study_area_verify_negative.sh` proves it fails when it should *and
passes when it should*. Suite 1825 pass / 0 fail (HEAD baseline 1719), 16
warnings both sides.

## Status (2026-08-31, late) — first provenanced multi-host run; scope decided; public-repo hygiene

**34 field WSGs modelled across three hosts, verified against the DB rather than
an exit code.** Run `20260831_232553`: 19 on m1 (Fraser), 9 + 6 on two cyphers
(Peace, Skeena). 158 min, ~$0.83. Every post-condition passed — per-host
completeness 19/19 + 9/9 + 6/6, consolidate 2/2, burn clean, coverage verified,
116 compare rows across 34/34. `fresh` grew **93 → 95** (BOWR and PINE modelled
for the first time). Cypher rows carry `fresh_sha` — #246's acceptance criterion,
`NA` on every cypher before that work. Reusable checker: `data-raw/study_area_verify.sql`.

Measured, and they now drive planning: **modelling 83 min, recompute + compare 55
min.**

**Correction 2026-09-02: the recompute runs over the RUN's WSGs, not the whole
schema.** This paragraph used to say the opposite, and the conclusion drawn from
it — that the recompute does not scale with scope, so parallelising it beats
adding machines — does not follow. `ALL_WSGS` is the union of the host buckets
(`study_area_run.sh:1306`), and the 2026-09-01 run logged
`post-consolidate recompute (lnk_access, 34 WSGs, -j4)` for a 34-WSG run against
a 95-WSG schema. Whatever was true when this was written, #205 (cheap
access-only recompute) and #250 (parallelise) changed it and the line was never
updated. It **does** scale with scope, so 217 WSGs means ~6.4x this recompute,
not a constant.

Recomputing all *run* WSGs is deliberate, not sloppy: at ~10 s/WSG it is cheap,
and threshold-filtering by parity is what produced FINA at 75% in May —
"bucketing is now a speed knob, not a correctness lever"
(`study_area_run.sh:1361`). Whether the set can be narrowed to
`run ∪ upstream(run)` at 217 is **#274**, unmeasured.

**Scope decided (#256 closed): all 217 modelable BC watershed groups**, not the
119-WSG closure and not the 34-WSG field set.

**Three operational facts worth not relearning.** Launch long runs **detached**
(`nohup … & disown`) — a tool-managed background process gets reclaimed, which
killed a run at 33 min. **Never touch the repo mid-run**: the dispatcher uses
`pkgload::load_all()` and the recompute re-reads git state for `lnk_stamp()`.
And `fresh_sha` was **NULL on the dispatcher** and non-NULL only on cyphers, so
asserting it everywhere reported a false failure on a healthy m1. **The stated
reason for that was wrong** — corrected 2026-09-01: m1's installed `fresh`
carries `RemoteType: github`, `RemoteRef: v0.33.0` and a `RemoteSha` identical
to the cyphers'. `.lnk_pkg_git_sha()` simply never read `RemoteSha` from the
installed DESCRIPTION. The tolerance was a workaround for an *unread* field,
not an absent one, and **#264 removed both the tolerance and the need for it**
— `fresh_sha` now resolves on every host. Rows logged before v0.50.0 keep the
NULLs.

**link is PUBLIC; rtj is PRIVATE; NewGraphEnvironment is a personal account** —
no org policy backstops visibility. 33 host addresses across 101 tracked files
were redacted (`7b83578`), the run now redacts its own logs from the EXIT trap
(`7701ffc`), and `RUNBOOK.md` lost an ssh host alias and credential dates
(`fb07ae8`). None of it was a credential; the cleanup is about how the repo reads
and about link's own rule that infra identity stays in machine-local memory.
Boundary proposal + preserved details: **rtj#257**; the pure-infra issue moved to
**rtj#256**. Open: **#257** (`link_dirty` is `t` on every dispatcher row and is
false — the run's own logs dirty the tree).

## Status (2026-08-31) — v0.47.2 shipped (#246 Phases 1-2; orchestration proven on a real cypher)

**The pre-flight gates exist and are exercised.** #246's Phases 1-2 shipped as
v0.47.0-0.47.2. Root cause of the "silently skips 80 of 119 WSGs" failure was
narrower than the issue stated: `fresh` was declared in **Suggests**, and
`pak::local_install()` resolves hard deps only, so the `Remotes:` pin at
DESCRIPTION was never applied and cyphers ran the image's fresh 0.31.0. Moving
it to Imports fixes it with no change to the pak call. New
`lnk_preflight_fresh()` asserts **symbols, not a version string**, with a drift
guard that walks link's own namespace (not `R/`, which does not exist in an
installed package).

**Four cypher pilots, ~$1.00, four defects** — full record in
`research/run_record_2026_08_31_cypher_pilots.md`, logs in
`data-raw/logs/study_area_run/20260831_*`. Measured rates that now drive
everything: dispatcher **0.0391** vs cypher **0.0872** min per 1000 persisted
segments (**2.23x**), recompute 0.0112, persisted/source ratio ~3.5.

### Three corrections to earlier beliefs — do not re-derive these

1. **A wipe is NOT required for a provenanced rebuild.** #246 Phase 3 proposes
   `DROP SCHEMA fresh CASCADE`. Unnecessary: `lnk_pipeline_persist` replaces per
   WSG (`DELETE ... WHERE watershed_group_code`), and the 93 WSGs in `fresh` are
   a **strict subset** of the 119-WSG run — zero orphans. Re-running overwrites
   everything and adds 26. No destructive step, no empty window.
2. **Only Peace is FWCP.** Fraser and Skeena are **HCTF** (provincial). "The 3
   FWCP study areas" was wrong and propagated into several docs.
3. **Field scope != model scope.** A GIS project's `watershed_groups`
   (`rtj/.../project.yml`) is where crews collected; the reporting repo's
   `wsg_code` is what is modelled. Peace is 8 vs 16.

### Scope, honestly

The "provincial" 119 is the drainage closure of *current* focal areas — BC has
246 WSGs and **217 are modelable**. All-BC is 1.76x the work (4.49M vs 2.56M
source segments), so "look anywhere" means 217, not 119.

Estimates at m1+3 cyphers: field scope (34 WSGs) ~1.7h, the 119 ~4.3h, all-BC
~7.3h. The serial recompute becomes the bottleneck past m1+5 — **#250**
(parallelise it) is worth more than three extra machines.

**Primitives refreshed 2026-08-31 21:45** on m1; the vintage gate passes at its
7-day default. Open: **#246** (Phases 3-5), **#247** (`snapshot_stamp` — superseded in scope
by #265). #250 and #257 closed; #262 closed by v0.49.0.

## Status (2026-08-06) — v0.45.1 shipped (WSG drainage closure rebuilt; #227 re-scoped)

`public.wsg_outlet` is **gone as a concept**, not repaired. `fresh@v0.33.0` (fresh#214/#215) rebuilt `frs_wsg_drainage()` on per-group outlet **points** (`blue_line_key` + `downstream_route_measure`) tested with the measure-aware `whse_basemapping.fwa_downstream()`; outlets ship in fresh at `inst/extdata/wsg_outlet.csv` (246 rows, generator `data-raw/wsg_outlet.R`) and reach the DB as a `VALUES` list, so **no table is needed in any database**. Adopted here in #238. The closure-mode `test-lnk_wsg_resolve.R` tests pass again and the suite is clean.

**The old derivation was also wrong, and the missing table was masking it.** `nlevel(wscode_ltree) ASC` picks the shallowest code appearing *anywhere* in a group — including polygon slivers. MORR (Morice) clips a 2-segment, 0 km, order-1 piece of the Bulkley-coded line `400.431358` next to 1,236 segments and 275 km of the order-8 Morice line, so the Bulkley appeared to drain through the Morice. Province-wide: 62/246 groups had over-shallow outlets, 167 distinct outlets for 246 groups, and the 14-group Fraser cluster (all wscode `100`) fell through to an **alphabetical** tiebreak that put LFRA seventh — breaking the DS-first guarantee cross-WSG `;DAM` depends on. **Correct rule: filter to the group's max stream order FIRST, then shallowest code, then lowest measure.** A single ltree can never order two groups on one stem; the 4-arg ltree-only `fwa_downstream` returns FALSE for `UFRA → LFRA`.

**Closures are now tighter** — `PARS + BULK` gives 9 WSGs, not 15 (drops LKEL, MSKE, USKE, LBTN, MORR, FINA, all correctly). Study-area buckets built before and after are **not comparable**; earlier runs were over-inclusive rather than short, so their results stand. **Gotchas:** `lnk_db_conn()` lands on the tunnel (`:63333`, `bcfishpass`), while `data-raw/study_area_wsgs.R` hardcodes docker `fwapg` (`:5432`) — two databases, different load states (#222); docker `fwapg`'s `fwa_watershed_groups_poly` has NULL code columns, so derive from `fwa_stream_networks_sp`, which is populated in both. **#227 re-scoped** to just the single-WSG downstream-state guard — its body carries a three-tier design (auto-pass via a 2.4 s `cabd.dams` spatial check, fail loud, override recorded in the #127 run log) and is buildable now the closure is correct.

## Status (2026-08-28) — v0.46.0 shipped (#227 downstream-state guard)

`data-raw/wsg_run_one.R` had stated the DS-first precondition in its header since #175 and **nothing enforced it** — accessibility reads the *already-persisted* barriers of downstream WSGs, so an out-of-order run marks dammed-off segments accessible and exits 0. New exported **`lnk_wsg_downstream_check()`** verifies it. **The predicate is PATH, not membership** — that distinction is the whole design: flagging when a downstream *group contains* a blocking dam fires on BULK (18 dams across LSKE/KISP/KLUM, none below its outlet), which is the issue's own example, and would train operators to override reflexively. Testing each dam with measure-aware `fwa_downstream()` from `fresh::frs_wsg_outlets()` gives PARS its three real dams (Peace Canyon, Site C, Bennett), SLOC the Brilliant Dam, BULK nothing. ~0.5 s. **Do not "simplify" it back to membership** — `RUNBOOK.md` §8c carries the measurement for exactly that reason.

The guard applies link's filters by **sharing** the pipeline's SQL: the `cabd` / `matched` CTEs live once and are consumed by both `.lnk_pipeline_prep_dams()` and the probe (parameterized on source — staged tables vs inline `VALUES`). Refactor verified behaviour-preserving against a golden capture taken first (ADMS/KOTL/PARS byte-identical). Override needs a written justification (bare `TRUE` rejected) and lands in `<persist>.log.notes` beside `wsg_upstream`. `study_area_run.sh` exports `LNK_GUARD_DOWNSTREAM=warn` on **both** legs (local *and* inside the ssh string — missing the second means cyphers hard-fail and WSGs get *skipped*, which `lnk_access(merge=TRUE)` cannot repair); `wsg_recompute_one.R` re-runs it in `error` mode post-consolidate, which is what makes `warn` a deferral rather than a hole. **Also fixed a v0.45.0 defect:** `.lnk_log_create_tables()` built the log tables but never the schema, so a brand-new persist schema failed — the log opens before `persist_init` by design, and every schema tested until now already existed. Follow-up **#244** (`cabd_additions` dams carry `barrier_ind = t` but psc NULL, so they can never become barriers).

## Status (2026-07-11) — #231 closed misdirected; #232 opened (crossings parity)

**Key correction (do NOT re-rabbit-hole):** the pipeline builds `<schema>.crossings` **from DB primitives** (`lnk_pipeline_crossings` → `.lnk_crossings_union`: PSCIS + `fresh.modelled_stream_crossings` + CABD), **not** from `crossings.csv`. The CSV read at `lnk_pipeline_load.R:100` is **vestigial** — the union drops + rebuilds the table before break/classify/mapping_code touch it. So #231 ("consume weekly crossings.csv; repoint pipeline off fresh") was **closed as misdirected**; lessons in `planning/archive/2026-07-issue-231-crossings-from-primitives/README.md`. Freshness lever = `data-raw/snapshot_bcfp.sh` reloading the primitives into the **`fwapg`** DB (last load ~2026-05-26; `lnk_db_conn()` defaults to a `bcfishpass` DB that LACKS them). Opened **#232** — confirm link's built crossings ≈ bcfp's complete `crossings_vw` (the parity reference). Aside: `crossings.csv` was published to `s3://newgraph` (db_newgraph#15, smnorris PR #57) before we realized the models don't consume it — **db_newgraph#16** tracks reconsidering that dump.

## Status (2026-07-31) — v0.44.3 shipped (#233 config dictionaries + ownership boundary)

Both config CSVs now have data dictionaries: `configs/dictionary_dimensions.csv` (renamed from `dimensions_columns.csv`) and the new `configs/dictionary_parameters_fresh.csv` (19 rows — type, group, `owner`, `consumed_by`, default, description). **The point was not documentation, it was stopping the re-derivation:** the fresh↔link `parameters_fresh` column-ownership split had been settled long ago by [fresh#129](https://github.com/NewGraphEnvironment/fresh/issues/129) (fresh 0.12.7 *removed* `observation_*` — "fish passage interpretation belongs in link, not the network engine") but was only findable by archaeology through two repos' planning archives, so it kept getting re-worked from scratch. It is now the `owner` column — **14 fresh-owned engine params, 5 link-owned `observation_*`** — read by `audit_configs.R` §3b instead of a hardcoded `grepl("^observation_", ...)`, and written up in [`RUNBOOK.md`](RUNBOOK.md) §7 "Who owns which `parameters_fresh` column". Adding a link-owned column is now a dictionary edit, not a regex edit.

**Two findings from machine-verifying every `consumed_by` file:line (24/24) rather than inferring them:** link never reads the nine `cluster_*` columns at all — it only passes the frame through (`lnk_pipeline_connect.R:107`) to fresh's `.frs_run_connectivity()`; and **`rear_gradient_min` is read by no code in either package** (recorded as unused, not dropped — fresh owns that schema). **Gotcha worth knowing:** the bundles carry *different* column subsets — bcfishpass `dimensions.csv` has 30 columns to the three `default*` bundles' 32 — so any dictionary/coverage check must assert against the **union**, never a single bundle. Guarded in two layers because `data-raw/` is `.Rbuildignore`d and never runs for an installed package: `tests/testthat/test-dictionaries.R` (+23, the CI-side guard) and the audit's coverage / reverse-consistency / missing-dictionary flags (negative-tested — dropping one row exits 1). Also removed `audit_configs.R`'s hardcoded `setwd("/Users/airvine/...")`: the script now derives its repo root from its own location and resolves paths via `repo_path()`, so it runs from any cwd and mutates none. Open follow-ups unchanged: **#224**, **#225**, **#227** (the `public.wsg_outlet` builder — its absence is the one standing test failure, `test-lnk_wsg_resolve.R:138`).

## Status (2026-07-04) — v0.44.1 shipped (#226 vignette accessible_km)

Extended the PARS vignette with an **Accessible habitat (km)** section proving `accessible_km` bcfp-equivalence (link 6,822.5 vs bcfp 6,822.9 km BT, **−0.01%**; table from cached `inst/vignette-data/pars_accessible.rds`). **Gotcha that bit hard:** "regenerate the vignette artifacts" was NOT docs-only — the two persist configs drift in segmentation because only WSGs re-modelled post-#223 are dense. `fresh` (bcfp config) had PARS at 97,538 segs but `fresh_default` (default/grayling) was still pre-#223 (48,558); the gpkg's single `streams` layer joins `fresh` geometry to `fresh_default` `mapping_code_gr` on `id_segment`, so a naive regen attaches grayling tokens to mismatched geometry → corrupt GR map. Fix: re-model the lagging config (`data-raw/wsg_run_one.R` + `merge=TRUE` recompute via `wsg_recompute_one.R` for cross-WSG `;DAM`) so both share segmentation; `wsg_vignette_data.R` now carries a **segmentation-parity guard** that refuses a mixed build. Any cross-config artifact joined on `id_segment` must verify both sides share segmentation first. mapping_code parity refreshed 99.04%→98.91% (denser post-#223). Open follow-ups unchanged: **#224**, **#225**, **#227**.

## Status (2026-07-03) — v0.44.0 shipped (#221 + #223 accessible_km)

Fixed the BT/ST `accessible_km` over-credit: streams now break at **every** gradient frontier (`lnk_pipeline_prepare.R` unions the raw per-model positions into `gradient_barriers_minimal`, not the `frs_barriers_minimal` reduction) — matching bcfp. Added the `accessible_km` roll-up column + `lnk_rollup_wsg()` (#221). Proven across 11 WSGs × 8 species: `accessible_km` 44/44 within 0.05%, habitat holds (parked BULK SK = fresh#190). Validator/proof: `data-raw/parity_crosssection.R` + `research/parity_accessible_habitat_2026_07_03.md`. **Gotcha that bit hard:** `fresh.streams_vw_bcfp` spawning/rearing/access_<sp> are coded 0/1/2/3 → parity uses `IN (1,2)` (a `= 1` under-counts; see `research/bcfp_view_column_coding.md`). Segment count now 2–3.5× (bcfp-matching; intersects #205). Open follow-ups: **#225** (rename `gradient_barriers_minimal` → `gradient_barriers_break`), **#226** (vignette accessible_km demo), **#227** (`wsg_outlet` builder + single-WSG guard; relates to #222), **#224** (bcfp `dam_dnstr_ind` reservoir-inflow quirk — reference-side, not ours).

The 2026-05-25 handoff below (#175 study-area parity) is **complete/superseded** — kept for history.

## Status (2026-05-25) — ACTIVE HANDOFF (#175 study-area mapping_code parity)

**Picking up? Read [`planning/active/task_plan.md`](planning/active/task_plan.md) + [`progress.md`](planning/active/progress.md), then [`research/study_area_run.md`](research/study_area_run.md) and [`RUNBOOK.md`](RUNBOOK.md).** Branch `175-promote-with-mapping-code-flag-to-stand` (pushed, `34b0cd3`). Built a lean tunnel-free, M1-dispatch study-area parity runner (`data-raw/study_area_run.sh` + `study_area_wsgs.R` / `wsg_run_one.R` / `study_area_compare.R`); ran all 3 study areas (50 WSGs) — **authoritative parity median 99.66%** ([`research/provincial_parity_2026_05_25.md`](research/provincial_parity_2026_05_25.md)).

**THE key finding:** per-segment mapping_code parity needs a **post-consolidate recompute** — drainage-closed + DS-first per-host is NOT sufficient (downstream barriers can be cross-bucket / late-in-order; FINA 75%→99% only after re-modelling on the full consolidated barrier set). The recompute is the correctness guarantee; bucketing is just a speed knob. **Next: build #205** (cheap access-only recompute reusing persisted streams/habitat — the current full-pipeline recompute is ~2× on diverged WSGs), then one clean driver-automated run, then annotate the genuine divergences (UNRS reservoir, SETN salmon) + ship. Filed #204 (persist shape-drift) + #205 (cheap recompute). Do NOT start over — the methodology is solved.

## Status (2026-05-19)

Tour-prep complete. Pipeline + comparison are decoupled (#168), the orchestrator runs autonomously (#172), and the QGIS bcfp-shape symbology path is tunnel-free (#187). M1 takes over cypher dispatch during the user's Europe trip.

Recent shipped work (v0.36 → v0.40):

- **v0.36.0** (#162) — `lnk_compare_wsg` + provincial parity annotated CSV (single-source-of-truth taxonomy). 5-host orchestrator. Methodology audited on ADMS/SETN/HORS/BULK/THOM (0 UNEXPLAINED at |diff_pct|≥2%).
- **v0.37.0** (#168) — Decoupled bcfp compare from link modelling pipeline. New `lnk_pipeline_run()` (modelling umbrella) + `lnk_compare_rollup()` (reference-agnostic comparison reader). PG-state resume gate via `link:::.lnk_wsg_persisted()` replaces brittle RDS-existence check. Species auto-discovered from PG.
- **v0.38.0** (#172) — Provincial-run autonomy + 8-script noun_verb rename. `wsgs_run_pipeline.sh` / `wsgs_dispatch.sh` / `wsgs_run_host.R` accept `--wsgs=`, `--config=`, `--schema=`, `--no-cyphers`, `--force`. Single-command provincial dispatch.
- **v0.38.1** (#178 Tier 1) — Single-cypher integration test for the autonomous wrapper. Validated cypher spin → prep → dispatch → consolidate → burn cycle. Row-level verification proved consolidate is byte-exact.
- **v0.39.0** (#180, #185) — Additive multi-host runs + bucket-filtered COPY-streaming in `schema_consolidate.R`. `--reset-schema` opt-in; default is additive. Per-source `wgc_tables` enumeration (#185 fix to silent partial-copy bug when source's table set is a subset of destination's).
- **v0.39.1** (#182) — Fail loud on transient cypher prep failures. `data-raw/cypher_prep.sh` replace `set -e` with `set -euo pipefail`; wrap three `| tail -N` pipelines with tempfile + exit-check pattern. Sibling fix to rtj#163 covering cypher orchestration scripts.
- **v0.40.0** (#187) — Mapping_code tunnel decouple + portable `lnk_mapping_code()` build + `<type>_<role>` rename sweep. Persist `streams_access` + `streams_mapping_code` + `streams_habitat_long_vw` view. `lnk_pipeline_run(mapping_code = TRUE)` builds tunnel-free; access semantics now use link's own per-species barriers (via `blocks_species` predicate from #152). BC: param rename `with_mapping_code` → `mapping_code`, `<role>_species` → `species_<role>`; CLI `--with-mapping-code` → `--mapping-code`. Deprecation shims for one release; removal v0.41.0.

Open follow-ups: #189 (data-drive species residence from `dimensions.csv` — sea-run cutthroat, Dolly Varden); #175 (`lnk_compare_mapping_code` as own family member — unblocked by #187); #176 (`lnk_compare_wsg` → `lnk_compare_run` rename); #177 (persist family reshape); #183 (sibling-host parity hook).

## Architecture

```
bcfishpass CSVs (overrides)  ─┐
fresh CSV (crossings)        ─┤→ link (interpret, score) → break_source spec → fresh
bcdata (PSCIS assessments)   ─┘
```

link is connectivity-system agnostic. Column names are configurable parameters with BC/PSCIS defaults. The same functions work for any jurisdiction's crossing data.

## Data Sources (no DB required for core pipeline)

| Data | Source | How |
|------|--------|-----|
| Crossings (province-wide) | `fresh::system.file("extdata", "crossings.csv")` | 533k rows, all WSGs |
| Override CSVs | `bcfishpass/data/` directory | Filter by `watershed_group_code` |
| PSCIS assessments | `bcdata::bcdc_get_data("7ecfafa6-...")` | BC Data Catalogue API |
| Habitat thresholds | `fresh::system.file("extdata", "parameters_habitat_thresholds.csv")` | Species-specific |

### Override CSVs from bcfishpass

| File | Purpose | Key columns |
|------|---------|-------------|
| `user_modelled_crossing_fixes.csv` | Imagery/field corrections (21k rows) | `modelled_crossing_id`, `structure`, `watershed_group_code` |
| `user_pscis_barrier_status.csv` | Expert barrier status overrides (1.3k rows) | `stream_crossing_id`, `user_barrier_status` |
| `pscis_modelledcrossings_streams_xref.csv` | GPS error corrections (3.6k rows) | `stream_crossing_id`, `modelled_crossing_id` |
| `user_barriers_definite.csv` | User-identified barriers (227 rows) | `blue_line_key`, `downstream_route_measure` |

## Database Connection

Uses `PG_*_SHARE` env vars (Docker fwapg) with fallback to standard `PG*` vars. From fresh 0.36.0 `frs_db_conn()` reads them the other way round (`PG*` first), so on a machine that sets both the two connect to different databases (#286). DB is needed for match/score/habitat functions that operate via SQL. The override loading and validation can work with any PostgreSQL.

```r
conn <- lnk_db_conn()  # reads PG_DB_SHARE, PG_HOST_SHARE, etc.
```

**Local docker fwapg (dev / parity work).** `lnk_db_conn()` with no args reads `PG_*_SHARE`, which on some machines points at the (intermittent) `:63333` bcfp tunnel — the wrong DB for the `fresh.*` persist. For local-docker work pass explicit args: `lnk_db_conn(dbname="fwapg", host="localhost", port=5432L, user="postgres", password="postgres")`. Bring it up from `~/Projects/repo/fresh/docker/` with `docker compose up -d db`. `:5432` holds the local `fresh.*` persist + `working_<wsg>` schemas + `fresh.streams_vw_bcfp`; `:63333` is the bcfp tunnel (`bcfishpass.*`, no `fresh.*`).

**Join persisted `fresh.*` on the full PK** `(id_segment, watershed_group_code)` — `id_segment` is NOT globally unique across WSGs in the consolidated persist, so a bare `id_segment` join fans out cartesian (#203). Length lives on `streams`, not `streams_access` / `streams_habitat_<sp>`.

## bcfishpass tunnel rebuild cadence

The tunnel-side `bcfishpass.*` schema (used as the comparison reference in `compare_bcfishpass_wsg.R`) **rebuilds weekly on Tuesdays around 19:00–23:00 PDT**, fired by `smnorris/db_newgraph`'s scheduled GHA workflow. Query the cadence + version with:

```sql
-- localhost:63333 / dbname=bcfishpass / user=newgraph
SELECT model_run_id, date_completed, model_version
FROM bcfishpass.log
ORDER BY model_run_id DESC LIMIT 5;
```

`model_version` format `<tag>-<commits>-g<short-sha>` (e.g. `v0.7.14-113-ga7373af`) — the trailing SHA is the exact `smnorris/bcfishpass` commit Simon's rebuild used. That SHA is the deterministic ref for matching link's bundle CSVs to the tunnel's input state — required for apples-to-apples comparison.

CSV-sync workflow goal: bundle CSVs in `inst/extdata/configs/bcfishpass/overrides/` should match the tunnel's last-rebuild SHA. Drift between the two means comparison numbers shift for input reasons, not methodology reasons. See the [csv-sync rewrite plan in memory](project_csv_sync_rewrite.md).

### Pin upstream versions in issue/PR bodies

When an issue or PR body describes upstream behaviour (bcfp SQL, fresh primitives, fwapg, etc.) as the rationale or reference, **pin the upstream version**. Use `<owner>/<repo>@<version-or-sha>` format:

- bcfp: the deterministic ref is `bcfishpass.log.model_version` (e.g. `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`). Cite `model_run_id` + date alongside for human readability.
- fresh / link / other NGE: tag refs (`fresh@v0.29.0`) or short SHAs (`fresh@f42e86a`).
- fwapg / db_newgraph: same — tag or short SHA.

Without a version pin, "this behaviour exists upstream" claims rot — six-month-old issues end up describing code that no longer exists, and no one knows what was being compared against. Version-pinning makes the issue self-contained and reproducible.

Note: `<owner>/<repo>@<sha>` references a commit; this does **not** trigger GitHub notifications to the referenced repo's participants (unlike `<owner>/<repo>#<n>` issue/PR references — see `feedback_no_cross_ref_external_issues.md` in memory).

## Exported Functions

### Core
- `lnk_thresholds(csv, high, moderate, low)` — configurable severity thresholds. Ships BC defaults. CSV or inline override. Feeds into `lnk_score()`.
- `lnk_db_conn()` — PostgreSQL connection factory. `PG_*_SHARE` then `PG*` env vars.
- `lnk_config(name_or_path)` — load a config **manifest**: paths (`cfg$rules`, `cfg$dimensions`), file declarations (`cfg$files`), pipeline knobs (`cfg$pipeline`), provenance metadata. **Manifest-only — no parsed CSVs.** Cheap to call. Configs may declare `extends:` to inherit from another config. Ships with `"bcfishpass"` and `"default"` variants under `inst/extdata/configs/<name>/`.
- `lnk_load_overrides(cfg)` — materialize the data files declared in `cfg$files`. Returns named list of canonical-shape tibbles. Entries with `source` + `canonical_schema` dispatch through `crate::crt_ingest()`; others fall through to local reads dispatched on path extension. Adding a new source family is a config edit + crate registration — no link R code change.

### Override family: load → validate → apply
- `lnk_load(conn, csv, to)` — read correction CSVs into DB. Two-phase: validate all CSVs before writing any. Multi-file load. Provenance tracking.
- `lnk_override(conn, crossings, overrides)` — find orphans (IDs not in crossings) and duplicates. Non-blocking.

### Match family
- `lnk_match(conn, sources, distance)` — generic N-way matcher on `blue_line_key` + `downstream_route_measure`. Bidirectional 1:1 dedup (closest match wins both directions). Where filters isolated in subqueries. Optional `xref_csv` for hand-curated GPS corrections.

### Score family
- `lnk_score(conn, crossings, method)` — `method = "severity"` for biological impact classification (high/moderate/low). `method = "rank"` for weighted multi-criteria prioritization. Threshold-driven, NULL-safe, column-agnostic.

### Rules family
- `lnk_rules_build(csv, to, edge_types)` — transforms a species habitat dimensions CSV into the rules YAML format consumed by `frs_habitat()`. Two CSVs: newgraph defaults (`inst/extdata/parameters_habitat_dimensions.csv`) and bcfishpass comparison variant (`inst/extdata/configs/bcfishpass/dimensions.csv`).

### Barrier overrides
- `lnk_barrier_overrides(conn, barriers, observations, habitat, exclusions, control, params, to)` — processes fish observations and habitat confirmations into a barrier skip list for fresh. Counts observations upstream of each barrier via `fwa_upstream()` SQL, applies per-species thresholds, unions with habitat confirmations. Control table (`barriers_definite_control` with `barrier_ind = TRUE` rows) blocks override of flagged positions — gated per-species by `params$observation_control_apply` so residents (BT, WCT) can still override anadromous-blocking falls. Habitat path bypasses control entirely (expert-confirmed habitat is higher-trust than observations). Output: `(blue_line_key, downstream_route_measure, species_code)` table that fresh skips during access gating.

### Pipeline helpers
Six-phase bcfishpass-reproducing pipeline, driven by `lnk_config()` + `lnk_load_overrides()`. Every phase that reads a data table takes both `cfg` (manifest) and `loaded` (the named list from `lnk_load_overrides()`). Callers materialize once and thread `loaded` through.
- `lnk_pipeline_run(conn, aoi, cfg, loaded, schema, dams, cleanup_working, mapping_code)` — modelling umbrella; chains all phases below plus `lnk_persist_init` + `lnk_barriers_unify` + `lnk_pipeline_persist` into one per-WSG call. Writes `<persist_schema>.streams`, `streams_habitat_<sp>`, `barriers`. With `mapping_code = TRUE` additionally writes `streams_access` + `streams_mapping_code` (tunnel-free; v0.40.0). This is the modelling boundary — comparison is separate (`lnk_compare_rollup`, `lnk_compare_wsg`).
- `lnk_pipeline_setup(conn, schema, overwrite)` — create per-run working schema.
- `lnk_pipeline_load(conn, aoi, cfg, loaded, schema)` — crossings + modelled fixes + PSCIS status overrides. Reads `loaded$user_modelled_crossing_fixes`, `loaded$user_pscis_barrier_status`, `loaded$user_crossings_misc`.
- `lnk_pipeline_prepare(conn, aoi, cfg, loaded, schema)` — falls, definite + control, habitat confirms, gradient barriers, `natural_barriers`, barrier overrides, per-model minimal reduction, base segments. Manifest-key gating via `loaded$user_barriers_definite_control` and `loaded$user_habitat_classification` (no DB probes).
- `lnk_pipeline_break(conn, aoi, cfg, loaded, schema)` — sequential `frs_break_apply` in config-defined order: observations → gradient minimal → **barriers_definite (separate break source)** → habitat endpoints → crossings.
- `lnk_pipeline_classify(conn, aoi, cfg, loaded, schema)` — assembles `fresh.streams_breaks` (gradient FULL + falls + **barriers_definite** + crossings, WSG-filtered) and runs `frs_habitat_classify()`. `barriers_definite` enters here directly because bcfishpass appends user-definite post-filter (not via observation override).
- `lnk_pipeline_connect(conn, aoi, cfg, loaded, schema)` — per-species cluster + connected_waterbody.
- `lnk_pipeline_species(cfg, loaded, aoi)` — canonical helper for "species this config classifies in this AOI" (intersects `cfg$species` with `loaded$wsg_species_presence` presence; falls back to `loaded$parameters_fresh$species_code` when `cfg$species` is missing).

### Compare family
- `lnk_compare_rollup(conn, aoi, cfg, reference, conn_ref, species)` — reads `<persist_schema>` (no working schema) + reference DB, returns long-format diff tibble. Species auto-discovered from PG. Reference-agnostic via `reference` arg (`"bcfishpass"` only today). Use for compare-only re-runs against existing PG state.
- `lnk_compare_wsg(conn, aoi, cfg, loaded, reference, mapping_code, conn_ref, ...)` — bundled convenience wrapper that calls `lnk_pipeline_run() + lnk_compare_rollup()`. For `mapping_code = TRUE` delegates the build to `lnk_pipeline_run`'s mapping_code phase (writes to persist) and then runs the diff against the reference's `streams_mapping_code`. Old `with_mapping_code` param accepted with deprecation warning until v0.41.0.
- `lnk_mapping_code(conn, table_access, table_habitat, table_streams, aoi, table_to, presence, species_resident, species_anadromous, species_spawn_only)` — portable schema-aware build wrapping `lnk_pipeline_mapping_code()`. Explicit `table_<role>` args (NGE convention) — works against working schema (mid-pipeline) or persist schema (ad-hoc rebuild). Tunnel-free. The QGIS bcfp-shape view consumer entry point (#187).
- `lnk_parity_annotate(rollup, taxonomy, to, tolerance)` — annotates a parity rollup against `research/bcfp_divergence_taxonomy.yml`. Tags each row with `taxonomy_id, class, mechanism, status, refs`. Unmatched rows: `UNEXPLAINED | WITHIN_TOLERANCE | NOT_APPLICABLE`.

### Bridge to fresh
- `lnk_source(conn, crossings, label_col, label_map)` — returns `list(table, label_col, label_map)` that plugs directly into `frs_habitat(break_sources = list(...))`. `label_map` translates link severity → fresh access labels (`high → blocked`, `moderate → potential`).
- `lnk_aggregate(conn, crossings, habitat, cols_sum)` — per-crossing upstream habitat rollup from fresh output. Sums spawning_km, rearing_km (or custom metrics).

## Integration with fresh

```r
# link scores crossings
lnk_load(conn, csv = "overrides.csv", to = "working.fixes")
lnk_override(conn, "working.crossings", "working.fixes")
lnk_score(conn, "working.crossings")

# link produces break source spec
src <- lnk_source(conn, "working.crossings")

# fresh consumes it — zero translation
frs_habitat(conn, "MORR", break_sources = list(src))

# link reads fresh output for per-crossing rollup
lnk_aggregate(conn, "working.crossings", "fresh.streams_habitat")
```

The data flows both directions: link → fresh (scored crossings as break sources) and fresh → link (habitat classification for upstream rollup).

## fresh Break Source Label Convention

When link produces a break source via `lnk_source()`, the label values control how fresh treats each point:

| Label | What fresh does |
|-------|----------------|
| `"blocked"` | Always blocks access (all species) |
| `"gradient_15"` | Blocks species with access threshold ≤ 15% (CO, CH, SK) but not BT (25%) |
| `"potential"` | Does NOT block by default. Only blocks if user passes `label_block = c("blocked", "potential")` |
| Anything else (`"passable"`, `"bridge"`, custom) | Never blocks |

### `label_block` parameter

`frs_habitat()` and `frs_habitat_classify()` accept `label_block` (default `"blocked"`). This controls which break labels restrict access:

```r
# link scores crossings with severity labels
src <- lnk_source(conn, "working.crossings",
  label_col = "severity",
  label_map = c("high" = "blocked", "moderate" = "potential"))

# Conservative: both high and moderate block
frs_habitat(conn, "BULK",
  break_sources = list(src),
  label_block = c("blocked", "potential"))

# Aggressive: only high blocks
frs_habitat(conn, "BULK",
  break_sources = list(src),
  label_block = "blocked")
```

### `gate` parameter

`gate = FALSE` skips accessibility entirely — classifies all segments by gradient/channel width alone. Useful for total habitat potential before considering barriers. `lnk_aggregate()` can compare gated vs ungated to show how much habitat each crossing blocks.

### Any AOI

`frs_habitat()` accepts any spatial extent — not just WSG codes:

```r
frs_habitat(conn,
  aoi = "wscode_ltree <@ '100.190442'::ltree",
  species = c("BT", "CO"),
  label = "richfield",
  break_sources = list(src))
```

## Pipeline for any watershed group

The same steps replicate what bcfishpass does, for any `watershed_group_code`:

1. Load crossings from `fresh::system.file("extdata", "crossings.csv")`, filter to WSG
2. Load overrides from `bcfishpass/data/` CSVs, filter to WSG
3. `lnk_load()` → `lnk_override()` (validate + apply)
4. Get PSCIS via `bcdata::bcdc_get_data()`, match with `lnk_match()` (+ xref CSV)
5. `lnk_score()` → `lnk_source()` → `frs_habitat()`
6. Falls as `list(table = "working.falls", label = "blocked")`

To run the entire province: loop over watershed groups. Or pass any AOI with `species` for sub-basin work.

## Open Issues

- #20 — Literature/observation evidence for habitat departures
- #21 — GSDD and thermal energy as intrinsic potential variables
- #52 — Channel-class break positions vs gradient thresholds (research)
- #75 — `dictionary_dimensions.csv` as source-of-truth: auto-gen README + `lnk_rules_build()` validation (CSV seeded in v0.17.0)

## Recently closed

- README refresh (PR #81) — rewrote around manifest configs + methodology-as-data narrative. Five-line demo, real BT-row comparison from `dimensions.csv`, `extends:` example, single pkgdown ref link, no per-section function lists. Acknowledgements + License kept verbatim.
- `_pkgdown.yml` cleanup (post-v0.18.1) — dropped manual `reference:` index. With `lnk_*` naming convention doing thematic grouping naturally, the index was duplicate work that broke CI on v0.18.1 release. Now auto-generated; per-function `@title`/`@description` carry the card view.
- #78 → v0.18.1 — Attribution for redistributed upstream data + Title/Description refresh. NOTICE.md, LICENSE-bcfishpass, per-bundle `overrides/README.md` pointers, README Acknowledgements, `Authors@R [ctb]` for Simon Norris. New Title: "Habitat and Connectivity Interpretation for Stream Networks". Description mirrors README's "fresh answers / link answers" framing.
- #76 — Enabled `allow_auto_merge` on the repo so the daily csv-sync workflow's byte-drift PRs auto-merge cleanly. Validated by PR #77 landing unattended.
- #65 → v0.18.0 — `lnk_load_overrides(config)` + manifest/data split. Decomposed `lnk_config()` into manifest-only loader and new `lnk_load_overrides()` ingest with crate dispatch. Single PR, single bump. Config schema flattened into one `files:` map keyed by filename stem; `rules:` and `dimensions:` paths moved top-level (no format suffix). Pipeline phases take `loaded` alongside `cfg`. Bit-identical rollup vs v0.17.0 baseline. Companion crate v0.0.2 release added Convention C `crt_*` prefix family + schema-driven type enforcement (`crt_schema_apply`, `crt_schema_validate`, `crt_schema_read`).
- #1 — Original v0.6-era scope issue closed as superseded by the package's evolution.

## Older closed

- #69 — Dimensions-driven `in_waterbody` + `area_only` emission → PRs #71/#72/#73 (v0.14.0–v0.16.0).
- #68 — Vignette ship — superseded by #74 (v0.17.0). Vignette removed 2026-04-29 once parity claim was retracted.
- #23 — CH spawning stream order exception QA — closed as not-a-bug (premise was a misread of bcfishpass spawning bypass: it uses `waterbody_key IS NOT NULL`, NOT `stream_order_parent`. Stream-order bypass exists in CH **rearing** only, tracked in fresh#158).
- #16 — ADMS comparison (tagged via PRs #41/#42/#43 for targets-driven reproducibility). Note: the "within 5%" framing was on a small set of pre-selected WSGs and missed barrier-class gaps surfaced in 2026-04-29.
- #38 — `_targets.R` pipeline → PRs #41/#42/#43 (v0.3.0/v0.4.0/v0.5.0)
- #44 — `barriers_definite_control` override wiring → PR #47 (v0.6.0)
- #46 — Manifest-driven pipeline probes → PR #50 (v0.7.0 refactor, no bump)
- #48 — `user_barriers_definite` not eligible for observation override → PR #49 (v0.7.0)

## Correctness bar: exact reproduction

The habitat classification pipeline is validated by **exact reproduction of runs**, not by "within 5% of bcfishpass." Same fwapg DB state + same bcfishobs DB state + same config bundle → byte-identical rollup tibble, every time. Any variation between two runs with identical inputs is a defect to root-cause, not to rationalize as "ordering variance."

Comparisons to bcfishpass (including the per-WSG `diff_pct` column in the rollup) are parity diagnostics — informative, not pass/fail. A bit-identical run that drifts from bcfishpass reference is acceptable; a reproducibility failure with the same inputs is not.

When inputs change (fwapg refresh, bcfishobs update, channel_width sync), outputs will correctly differ. That's what the stamp/lineage work (#40) makes explainable — so any observed drift can be traced back to which input moved.

## Config change workflow

When changing a `configs/<name>/dimensions.csv` or any file that feeds `lnk_rules_build()`:

1. **Regenerate + diff rules.yaml before running anything.** `Rscript data-raw/build_rules.R` then `git diff inst/extdata/configs/<name>/rules.yaml`. Confirm the diff matches intent — e.g., toggling `spawn_lake=no` for SK should remove the `waterbody_type: L` rule under `SK.spawn`. Catching an unintended rule here costs seconds; catching it after a 20-min tar_make costs 20 min.
2. **Pre-flight on one WSG, not five.** After reinstalling the package (`pak::local_install(upgrade = FALSE, ask = FALSE)` or equivalent), run the single-WSG workload (`link-tarmake-single <WSG>`) on the smallest WSG impacted by the change before the full `link-tarmake-5wsg`. ADMS is smallest, BULK largest per `workloads.csv` — pick whichever is small AND exercises the affected species. **Always report the pre-flight result framed as departures from bcfishpass reference, not just raw link numbers.** Small config changes (new threshold, edge-type tweak) should land within ~±20% of bcfp values; >50% departure is a flag; >100% or a 10× swing is "investigate before rerun" — bcfishpass is mature and its numbers are a reasonable sanity baseline. The four `sources` buckets from `§6` of the research doc are better signal than the scalar rollup delta — run them on the pre-flight WSG too.
3. **DB-side sanity as shortcut.** When the fix's effect is measurable (e.g., "SK spawning km should drop because lake shoreline edges no longer count"), a direct query on `fresh.streams_habitat` grouped by `edge_type` can confirm direction of change in ~30s without any tar_make.

## SRED

Relates to NewGraphEnvironment/sred#24 — crossing connectivity interpretation package.

## Working Conventions

Operating rules learned on this repo. Migrated from machine-local Claude memory
so they travel to every machine (soul#47 recipe).

### Surface design decisions before writing code

For load-bearing choices — function naming, family vs singleton, prefix, scope — present two or three concrete options with tradeoffs and let the user pick.

**Why:** Twice in one session (#65 and the `schema_apply` naming) a design was implemented without consulting and had to be redone. Real design decisions sit *between* agreeing on direction and writing the diff; "auto mode" means execute the chosen path quickly, not skip the choice.

**How to apply:** After agreeing the *what*, ask the *how* — which prefix, one function or a family, what does the package already do? Check `soul/conventions/newgraph.md` for `noun_verb-detail` before inventing a name.

### Read the issue before re-deriving its design

When work references a function or feature that has an issue, read that issue body in full — and scan its closed predecessors — before exploring.

**Why:** An entire session went into re-deriving `frs_order_child` decisions that were documented verbatim in fresh#158, including a predecessor link to fresh#156 closed in its favour with its own analysis.

**How to apply:** `gh issue view <N> --repo <owner>/<repo>` first. Search closed issues for rejected predecessors — "closed in favor of" comments carry the rationale. Check `planning/archive/` for prior PWFs on the topic. If the issue contradicts a hypothesis you're about to test, say so before testing. Note that fresh#158 states link's `frs_order_child` is deliberately **not** chasing bcfp parity — don't assume parity is the goal for any link primitive without checking.

### Detective work before scoping a "gap"

When an issue claims data is missing relative to bcfishpass, run a count plus a row-level diff against the real data before scoping any implementation.

**Why:** link#102 (CABD waterfalls "completeness gap") dissolved in five minutes of `psql`: fresh's `falls.csv` per-WSG barrier counts are byte-identical to `bcfishpass.falls WHERE barrier_ind = true` across all 187 WSGs. The "missing famous falls" framing was wrong — those are mostly `barrier_ind = false` (fishways) or live in `cabd.dams`. A research-doc sentence had implied a divergence that didn't exist at row level.

**How to apply:** Counts from both sides → diff at WSG level → row-level spot-check on one representative WSG → only then scope. Costs 5–10 minutes; has closed issues as not-a-bug and avoided multi-day PRs. Even when data does differ, the count diff sizes the work correctly.

### Build abstract systems, not point solutions

Reuse first, hardcode last, compose. New functions join an existing `lnk_*` family; don't invent a family unless none fits.

**Why:** The pipeline had two near-identical helpers applying CSV-driven `barrier_status` overrides, and a third of the same shape was about to be added. The user wants the system rationalized, not extended — "don't be afraid to start over, might be smarter."

**How to apply:** Before adding a third helper of a shape, consolidate the two that exist. Mirror external systems by view or composition, never a hand-built table. **Don't hide diamonds** — a primitive with utility beyond its caller belongs as a public function at its natural altitude (a "what's downstream" SQL pattern serves water quality stations and sediment samples too, so it belongs in `fresh`'s `frs_network_*`, not a private link helper).

### Never file an issue or PR without body review

Draft the body, show it, and wait for explicit approval before `gh issue create` / `gh pr create`.

**Why:** "Yes write the issue" arrived in the same message as unanswered architectural questions; link#112 was filed prematurely and the user had to edit a public issue after the fact.

**How to apply:** Draft to a tempfile and show it in the response. Architectural questions in the same message mean the design isn't settled — answer those, get sign-off, then file. Only exception: a skill where filing *is* the explicit ask.

### PWF checkboxes are an integrity contract

`- [x]` means the named action ran and reported clean. If it didn't run, the box stays unchecked.

**Why:** `[x] /code-check clean` was ticked on #138 (v0.32.0) without invoking the skill. Run post-hoc, it surfaced three real fragility findings (int4 overflow, silent row loss on FWA-join NULLs, `pts.*` column collision) that should have been caught pre-merge.

**How to apply:** Leave it unchecked, or reword to what actually happened ("deferred — see follow-up"). For a `/code-check` missed on an already-merged PR, run it post-hoc and ship the findings as a follow-up patch.

### Fail loud; the release bar is the full sweep

Before any minor or major release: `devtools::test()`, `devtools::check()`, `lintr::lint_package()`, and live parity **beyond the happy-path case**.

**Why:** Each of these shipped or nearly shipped a quiet regression — a scratch primitive that matched 15613/15647 ADMS arrays but was lossy elsewhere; a consolidate driver that dropped source schemas even when restore failed (lost a cypher's data); a resume gate that conflated "RDS present" with "WSG done" and silently no-op'd a recovery run.

**How to apply:** If you tested ADMS, also test BULK or HORS. If you tested PSCIS barriers, also test dams. When the user says "ship it" and the sweep hasn't run, ask first — seconds versus days. Surface failures inline with a proposed fix rather than papering over them.

### Stamp the environment in every verification log

Verification runs record environment state, not just numbers.

**Why:** A refactor appeared to move BT rearing by 0.4 points against bcfishpass on ADMS. Hours went into hunting an extraction bug that didn't exist — the drift was entirely input state changing between two run dates. Without stamps you cannot tell which input moved.

**How to apply:** Header carries link version + SHA, fresh version + SHA, fwapg dump timestamp or schema hash, bcfishobs row count, bcfishpass reference row counts, and the reference data version. `lnk_stamp()` (#24) should drive this once it ships.

### How to talk about bcfishpass

Never position link or fresh as superseding or replacing bcfishpass. It is the system we learned from and build on.

**Why:** It's community infrastructure maintained by smnorris with contributions from many groups. Framing our work as a replacement misrepresents the relationship.

**How to apply:** "validates against", not "replaces". "builds on the foundation of", not "improves on". "community-maintained override CSVs", not "our data". Frame methodology differences (wetland rearing, intermittent streams) as *our biological defaults*, not corrections. The bcfishpass comparison is a validation step, not the package's goal.

### Never write into smnorris/* without explicit approval

No comments, issues, PRs or any write action in an upstream repo unless the user approves that specific action.

**Why:** Upstream is a third party; every write creates notifications and work for someone else. The user wants a deliberate decision each time, not a judgment call.

**How to apply:** Read-only `gh` calls are fine. Any write (`gh issue create`, `gh pr comment`, `gh api -X POST`, …) waits for "file it" on that specific action. Draft it in chat first. Applies to bcfishpass, bcfishobs, db_newgraph, fwapg, and external orgs generally.

### Sibling-repo work: branch and PR, no comms thread

Working directly in `fresh` or `crate` from a link session is fine when the user directs it. The older comms-first rule was explicitly relaxed.

**How to apply:** Proceed in the sibling repo — but still branch, still open a PR, **never push to a sibling's main**. Keep commits separate per repo; don't bundle a link change and a fresh change into one commit. Ask when an action is destructive or the intent is unclear.

### No issue references in vignettes

Vignettes describe what the package does today. Issue numbers go stale silently.

**Why:** A vignette line reading "seed for link#75, which will turn this CSV into…" would still promise a future state after #75 closed.

**How to apply:** Vignettes link to behaviour and source paths only — no `#NN`, no "will become". Issues are fine and encouraged in NEWS, PR bodies, commit messages, and `research/*.md`. Avoid them in README unless they describe a limitation users need today.

### No manual reference index in _pkgdown.yml

With consistent prefix naming, drop the manual `reference:` section and let pkgdown auto-generate.

**Why:** A manual index recreates groupings the naming already does, and breaks CI whenever a new export isn't added to it — exactly how v0.18.1's pkgdown build failed on `lnk_load_overrides`.

**How to apply:** Keep `_pkgdown.yml` to `url:`, `template:`, and `articles:`. Manual sections only earn their place in packages with mixed prefixes or weak naming.

### fresh tests itself against link's compare script

Both repos are local on the same machine, same Docker DB and tunnel. fresh can run link's compare script directly — we are not the middleman.

**How to apply:** A fresh issue should say `Rscript ~/Projects/repo/link/data-raw/compare_bcfishpass.R BULK` with target numbers, not "we'll test and report back". fresh installs link via `devtools::install_local()` and verifies before pushing.

### Infrastructure identity stays out of this repo

Host aliases, addresses, ssh key names and similar belong in machine-local
memory, not in link. Migrate the *behaviour* — which port, which failure mode,
what to do when a host key rotates — and leave the identity behind.

**Why:** link is **PUBLIC**, rtj is **PRIVATE**, and NewGraphEnvironment is a
personal account — no org-level visibility policy backstops anything. 33 host
addresses across 101 tracked files were scrubbed on 2026-08-31 (`7b83578`), and
the run now redacts its own logs from the EXIT trap (`7701ffc`). None of it was
a credential; the rule is about how the repo reads and where infra identity
lives, not about any single string being harmful.

**How to apply:** Write the mechanism, not the address. `db_newgraph` is *ours*
(we pay, Simon runs it) so scrubbing it needs no external approval — but most of
its ~140 mentions here are legitimate workflow documentation and only the
**ssh-host-alias** uses are misplaced. Same word, two meanings: do not blanket-
`sed` it. History still carries what was scrubbed; that is deliberate, and
current state is what matters. Boundary write-up: rtj#257.

**When auditing for this, prove the search can match before trusting an empty
result.** A repo-wide audit run with `\b` (which BSD grep does not reliably
support) returned nothing and was reported as "no IPs in any tracked file"; a
working pattern on the same tree found 33. Anchor on POSIX classes, and match a
file you know contains one before concluding a repo is clean.

### State the run decisions before launching, never inherit a driver default

Before any modelling run, enumerate what is being chosen and get an answer:
**config**, **persist schema**, the **resolved closure** (which WSGs actually
get modelled, not just the focal ones), the **species** that fall out of
config x presence, and the load-bearing flags — `--refresh-primitives`,
`--recompute-jobs`, `dams`, `mapping_code`.

**Why:** on 2026-09-03 the North Thompson run (floodplains#75, run_uid
`20260903_173205-67013fc3`) went out on `--config=bcfishpass` because that is
what fifteen drivers default to. The operator expected `default` — link ships a
config by that name carrying its own biological positions — and was already
seventeen WSGs deep into a floodplain product line. Two focal WSGs also resolved
to a six-WSG closure, which is a second decision the flag does not show. Their
framing is the load-bearing part: *"We already have bcfishpass available via the
tunnel. If I wanted that I would just grab from there."* link in bcfishpass mode
is a **parity instrument**, not a basis for shipped products.

**How to apply:** State the decision set above the launch command, one line each
with the alternative named — "config: `bcfishpass` (parity, writes `fresh`) or
`default` (link's own, writes `fresh_default`)" — and wait. A surprising default
in a script is not a decision that has been made; it is one that was skipped.
The two persist schemas are **not interchangeable**: TABR sits in both at 14,652
vs 12,948 segments. Explicitly not wanted: a standing "always use X" rule — the
ask is awareness per run, not a fixed answer. Fix tracked in #278, the fleet
sweep in soul#178, and the bug class is now a row in soul's `code-check.md`.

<!-- BEGIN SOUL CONVENTIONS — DO NOT EDIT BELOW THIS LINE -->


# Cartography

## Style Registry

Use the `gq` package for all shared layer symbology. Never hardcode hex color values when a registry style exists.

```r
library(gq)
reg <- gq_reg_main()  # load once per script — 51+ layers
```

**Core pattern:** `reg$layers$lake`, `reg$layers$road`, `reg$layers$bec_zone`, etc.

### Translators

| Target | Simple layer | Classified layer |
|--------|-------------|-----------------|
| tmap | `gq_tmap_style(layer)` → `do.call(tm_polygons, ...)` | `gq_tmap_classes(layer)` → field, values, labels |
| mapgl | `gq_mapgl_style(layer)` → paint properties | `gq_mapgl_classes(layer)` → match expression |

### Custom styles

For project-specific layers not in the main registry, use a hand-curated CSV and merge:

```r
reg <- gq_reg_merge(gq_reg_main(), gq_reg_custom("path/to/custom.csv"))
```

Install: `pak::pak("NewGraphEnvironment/gq")`

## Map Targets

| Output | Tool | When |
|--------|------|------|
| PDF / print figures | `tmap` v4 | Bookdown PDF, static reports |
| Interactive HTML | `mapgl` (MapLibre GL) | Bookdown gitbook, memos, web pages |
| QGIS project | Native QML | Field work, Mergin Maps |

## Key Rules

- **`sf_use_s2(FALSE)`** at top of every mapping script
- **Compute area BEFORE simplify** in SQL
- **No map title** — title belongs in the report caption
- **Legend over least-important terrain** — swap legend and logo sides when it reduces AOI occlusion. No fixed convention for which side.
- **Four-corner rule** — legend, logo, scale bar, keymap each get their own corner. Never stack two in the same quadrant.
- **Bbox must match canvas aspect ratio** — compute the ratio from geographic extents and page dimensions. Mismatch causes white space bands.
- **Consistent element-to-frame spacing** — all inset elements should have visually equal margins from the frame edge
- **Map fills to frame** — basemap extends edge-to-edge, no dead bands. Use near-zero `inner.margins` and `outer.margins`.
- **Suppress auto-legends** — build manual ones from registry values
- **ALL CAPS labels appear larger** — use title case for legend labels (gq `gq_tmap_classes()` handles this automatically via `to_title()` fallback)

## Self-Review (after every render)

Read the PNG and check before showing anyone.

### Placement

1. Correct polygon/study area shown? (verify source data, not just the bbox)
2. Map fills the page? (no white/black bands)
3. Keymap inside frame with spacing from edge?
4. No element overlap? (each in its own corner)
5. Legend over least-important terrain?
6. Consistent spacing across all elements?
7. Scale bar breaks appropriate for extent?

### Does it communicate?

Every check above is about **where elements sit**. A map can satisfy all seven
and still fail to say what it is about — so these are not optional extras, they
are the half of the review that the placement list structurally cannot reach.

8. **Is every prominent feature in the legend?** Work the other direction from
   the usual one: rank what draws the eye *in the rendered image*, then confirm
   each of the top few appears in the legend. Building the legend from the layer
   list instead answers "did I list my layers", which is a different question and
   always says yes.
9. **Is the subject obvious to someone who has never seen this area?** An AOI
   that renders identically to its surroundings is not delineated by a thin
   boundary line — the reader has to be told where to look. Containment (a fill,
   a dimmed exterior, a mask) is what does it.
10. **Does the symbology have a hierarchy, or is it flat?** If one class holds
    the great majority of the features, it will dominate regardless of how
    correct its size is. Ask what the map is *for* and de-emphasise or filter
    accordingly — and say in the caption or prose that you did.
11. **Does the basemap earn its contrast cost?** A basemap that adds no readable
    terrain is not neutral: it lowers the contrast of everything drawn over it.
    Blend parameters that mute it into a flat field are worse than no basemap.
12. **Is the type sized for the width it is published at, not rendered at?** A
    7 in figure squeezed into a ~700 px column loses roughly 40% — text set at
    `size = 0.5` for the render lands at a few pixels on the page. Check the
    figure at its delivered width.

### Why this half exists

Added 2026-08-26 after gq's flagship vignette map was reported as passing all
seven placement checks and was, on being looked at, unreadable: 89% of its point
symbols were one modelled class, the basemap was a featureless grey field, the
AOI was indistinguishable from its surroundings, and the single most prominent
feature on the map — a bright red 397-feature habitat network — **was not in the
legend at all**, while the prose beneath the figure described its styling in
detail (gq#61).

The seven checks had returned green, accurately. They were simply not asking.

See the `cartography` skill for full reference: basemap blending, BC spatial data queries, label hierarchy, mapgl gotchas, and worked examples.

## Land Cover Change

Use [drift](https://github.com/NewGraphEnvironment/drift) and [flooded](https://github.com/NewGraphEnvironment/flooded) together for riparian land cover change analysis. flooded delineates floodplain extents from DEMs and stream networks; drift tracks what's changing inside them over time.

**Pipeline:**

```r
# 1. Delineate floodplain AOI (flooded)
valleys <- flooded::fl_valley_confine(dem, streams, area_field = "upstream_area_ha")

# 2. Fetch, classify, summarize (drift)
rasters   <- drift::dft_stac_fetch(aoi, source = "io-lulc", years = c(2017, 2020, 2023))
classified <- drift::dft_rast_classify(rasters, source = "io-lulc")
summary    <- drift::dft_rast_summarize(classified, unit = "ha")

# 3. Interactive map with layer toggle
drift::dft_map_interactive(classified, aoi = aoi)
```

- Class colors come from drift's shipped class tables (IO LULC, ESA WorldCover)
- For production COGs on S3, `dft_map_interactive()` serves tiles via titiler — set `options(drift.titiler_url = "...")`
- See the [drift vignette](https://www.newgraphenvironment.com/drift/articles/neexdzii-kwa.html) for a worked example (Neexdzii Kwa floodplain, 2017-2023)


# CI Monitoring

When this repo has GitHub Actions workflows, scan recent runs on session start. Catches failed pkgdown deploys, broken vignette builds, and stale citation regenerations that would otherwise linger until the user manually checks.

## On Session Start

```bash
gh run list --limit 5 --json status,conclusion,name,createdAt,databaseId \
  --jq '.[] | select(.conclusion == "failure")'
```

If any failures since the last visit, surface to the user before starting other work:

> Workflow `<name>` failed `<time>` ago (run `<id>`). Investigate with `gh run view <id> --log-failed`. Fix or proceed with current task?

User decides; do not auto-fix.

## Particular Failures Worth Naming

- **pkgdown** — docs site on GitHub Pages broken
- **R-CMD-check** — package may not install
- **Vignette / build-vignettes** — vignette docs incomplete
- **update-citation-cff** — CITATION.cff stale

## Why This Matters

Without this scan, post-merge workflow failures linger until someone (often the user) notices a stale docs site or a missing vignette. The session-start sweep catches them on the first re-entry into the repo.

## Pairs with `/gh-pr-merge`

The skill watches workflows triggered by a fresh merge in real time — that's the targeted catch. This convention is the backstop for failures that landed when no one was watching (merges via web UI, scheduled triggers, manually-triggered workflows).

## A green run does not mean the site is current

CI conclusion and published content are two different facts. Check the second one
directly when it matters — the deploy commit, not the run status:

```bash
git fetch -q origin gh-pages && git log -1 --format='%s' FETCH_HEAD
# "Deploying to gh-pages from @ owner/repo@<sha> 🚀"  <- is <sha> your HEAD?
```

GitHub can create a workflow run minutes after the push that triggered it, and
out of order with a later push. Observed 2026-08-26 in `fly`: `7a7700c` built and
deployed at 17:21, then its own *parent* `be77eca` had its run created at 17:22:52
— twelve minutes after that push — and deployed over it. Both runs green, `gh run
list` all success, published site one commit stale.

Things that do **not** fix this, so don't reach for them:

- `cancel-in-progress: true` — cancels an *overlapping* run. Here the runs never
  overlapped (`created == started` on both, second created after first finished),
  so there was nothing to cancel.
- A `concurrency:` group — the r-lib pkgdown template already sets one at the job
  level (`group: pkgdown-${{ github.event_name != 'pull_request' || github.run_id }}`).
  Grepping for a top-level `concurrency:` key misses it and invites a redundant
  "fix". Serializing runs doesn't order events that arrive late.

There is no workflow-side fix, because the reordering happens before the workflow
exists. The remedy is detection: check the deploy provenance, and re-dispatch
(`gh workflow run <file> --ref main`) if it's behind. Harmless when the stale
commit changed nothing the site publishes — confirm via `.Rbuildignore` / `_pkgdown.yml`
rather than assuming.

## Don't push to the default branch between a merge and its CI settling

The r-lib templates set `concurrency` with `cancel-in-progress: true`, so a second push
to `main` cancels the first push's still-running workflows. That is correct behaviour and
it is not the problem; the problem is that a **cancelled** run and a **failed** run look
the same in the status column, so a routine follow-up push turns a green merge into
something the next person has to go read a log about — and the log does not exist.

The routine follow-up is the one that bites, because it is the one nobody counts as a
push: a `CLAUDE.md` drift sync, a typo fix, a `.gitignore` line. `/compact-prep` step 6
runs `claude_md_drift.sh apply`, which **pushes**, and after `/gh-pr-merge` that lands
seconds after the merge.

Order them: watch the merge's runs to completion, *then* push anything else. Measured
2026-09-08 in gq — the merge's pkgdown and R-CMD-check were allowed to finish green and
the deploy provenance checked before the sync went out, and the sync's own runs then went
green on their own SHA. Holding it cost about three minutes.

Where a push has already gone out and cancelled something, `/gh-pr-merge` step 10 has the
reading: `cancelled`/`skipped` is `⊘ superseded`, not `✗ failed`, and the thing to confirm
is that the **newer** SHA's run passed. Do not re-dispatch the cancelled one.

## Don't use `gh run watch` to wait

It polls hard enough to trip GitHub's *secondary* rate limit, which `gh api
/rate_limit` does not report — every primary bucket reads full while calls return
403. Retrying extends it. Poll sparsely with `gh run view <id> --json status,conclusion`,
and prefer `git fetch` over the REST API for anything git can answer.

## A setup failure and a build failure look identical in the status column

`gh pr checks` and the Actions UI report one word per job. A run that died fetching its
own toolchain and a run that died because the code is broken both read `fail`, and only
the second says anything about what you just shipped.

```
Error in download.file(...) : status was 'SSL connect error'
download of package 'pak' failed
Error in loadNamespace(x) : there is no package called 'pak'
```

That is `setup-r-dependencies` failing before the package was ever built. Seen
2026-09-02 on a tagged spacehakr release, where the same workflow had passed on the merge
commit minutes earlier with identical content — the natural but wrong reading is "the
release is broken".

**Read which step failed before drawing a conclusion**, especially on a release commit
where the instinct is to distrust the tag:

```bash
gh run view <id> --log-failed | grep -iE 'error|fatal' | head
```

If it died in dependency setup, rerun once. If it dies the same way again it is the
upstream CDN, and the honest move is to say so and stop — not to keep spending runs on
something no change in the repo can fix.

## A job-level `concurrency` group must vary with the matrix, or the jobs cancel each other

`concurrency` at the **job** level is evaluated **per matrix job**, so a group string that
does not vary with the matrix puts every runner in one group — and with
`cancel-in-progress: true` they cancel each other. At most one platform runs per push,
which is the entire justification for having a matrix.

```yaml
# WRONG: identical for all three entries
concurrency:
  group: check-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

# right
  group: check-${{ github.workflow }}-${{ github.ref }}-${{ matrix.config.os }}
```

`fail-fast: false` does not help — that governs failures, not cancellation.

**It fails in the quiet direction.** A cancelled run reports `cancelled`, not `failure`,
which `/gh-pr-merge` step 10 correctly reads as `⊘ superseded` — so two platforms that
never ran look like two platforms that were superseded by a newer push. Nothing is red and
nothing says the coverage was lost.

The decisive evidence is GitHub's own context-availability table: `matrix` is listed for
`jobs.<job_id>.concurrency` and **not** for the top-level `concurrency`. If it were not
evaluated per job, the context could not be in scope there.

```bash
curl -s https://raw.githubusercontent.com/github/docs/main/content/actions/reference/workflows-and-actions/contexts.md \
  | grep 'concurrency'
```

Cheapest confirmation on a live workflow: the first run's job list. Three jobs
`in_progress` at once is the pass; one running while two read `cancelled` is this.

The entries above concern cancellation **between pushes**, which is the behaviour you
want. This is cancellation **within one push**, which is never what you want.

*4 lines of evidence for this rule are in `conventions/ci-monitoring.md`, which `/code-check` reads in full.*


# Code Check — R
Traps in R: the language and base/utils behaviour, package internals (`R CMD build`, `.Rbuildignore`, roxygen, lintr, `data-raw/`, testthat, pak), and the DBI/duckdb/arrow data layer.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check-r.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

### Read-back shape must match write-back shape
A script that reads a file, transforms it, and writes it **back to the same path** is idempotent only if the reader accepts the shape the writer produces.

### Moving prose into a code chunk hides it from tools that scan the document
- Tools that scan an R Markdown document for prose — citation detection, cross-references, spell-check, word counts — skip code chunks.

### `fs::dir_ls(glob = )` matches the FULL path, so a bare filename pattern matches nothing
- `fs::dir_ls(dir, glob = "form_*.gpkg")` returns **zero** for a directory full of `form_*.gpkg` files.

### `glue()` trims common leading whitespace
- `glue::glue()` strips the common indentation of its input, so a template whose output must preserve exact indentation (XML, YAML, Makefiles, Python) comes out subtly wrong — valid-looking, wrongly indented.

### `f(g(x)) <- v` needs a `g<-`, not an evaluated `g(x)`
- R parses **any** call on the left of `<-` as a replacement function, all the way down.

### A replacement function on an `xml_missing` node is a silent no-op
`xml2::xml_find_first()` returns an `xml_missing` object when nothing matches — not `NULL`, not an error.

### `download.file(quiet = TRUE)` never tells you the HTTP status — read it from `curl`
Read an HTTP status from `curl::curl_fetch_disk()`'s `status_code`, never from `download.file()` messages, whose first warning unwinds a `tryCatch` before the status arrives and whose quiet error omits it.

### `on.exit()` at a script's top level never fires
- `on.exit()` registers a handler on the *current frame*.

### A `data-raw/` script must load the source tree, not the installed package
- `requireNamespace("pkg")` succeeds whenever **any** version is installed, so a guard shaped like `if (!requireNamespace("pkg")) pkgload::load_all()` silently runs against the installed one.

### `lintr` also resolves against the installed package, not the source tree
A lint warning of `no visible binding` for a constant added on this branch is usually the installed package being stale; check `exists(name, asNamespace(pkg))` and reinstall before changing any code.

### Regenerated binaries churn git even when nothing changed
- Formats that embed a creation timestamp or other run-varying metadata produce a different file on every rebuild.

### Tests that silently do not run
`expect_snapshot()` **skips on CRAN**, and `testthat` treats a non-interactive run as CRAN by default.

### A `skip_if_not()` skips only its own `test_that()` block
Before blaming a failure, or its absence, on a skip, find the `test_that()` block the skip sits in.

### `expect_gt()` and friends take no `info` argument
`expect_true()`, `expect_false()` and `expect_equal()` accept `info =`; the comparison expectations — `expect_gt`, `expect_lt`, `expect_gte`, `expect_lte` — do not, and passing one is an **error**, not a warning:

### pak Behavior
- pak stops on first unresolvable package — all subsequent packages are skipped

### Reproducibility
- Branch pins (`pkg@branch`) are not reproducible — document why used; the fuller pin policy (no suffix by default, never a bare SHA) is under "Two repos pinning the same remote" below

### A duplicate knitr chunk label fails the build, and reading the diff will not find it
Chunk labels must be unique **within a document**.

### `R CMD build` ships every top-level directory not in `.Rbuildignore`
- Internal coordination directories — `comms/`, `research/`, `planning/`, `dev/` — land in the tarball and therefore in the library of anyone installing from GitHub.

### `R CMD build` ships the `.git` FILE when you build from a worktree
A package built from a `git worktree` ships `.git` (a file holding the developer's absolute path), because R excludes only a `.git` directory; list `^\.git$` in `.Rbuildignore`.

### `.Rbuildignore` has no comment syntax — every line is a live regex
`tools:::inRbuildignore` loops over every non-empty line and ORs `grepl()` of it against the file list.

### Base name shadowing in formal args
- Avoid `names`, `length`, `data`, `c`, `t`, `T`, `F`, etc. as formal argument names.

### Cross-function consistency for label/string normalization
- When two functions in the same package both decide whether a string is a "system value" (or any normalized form), they MUST use the same comparison.

### `$` on a list partial-matches, so a longer sibling key answers for a missing one
- `x$foo` on a list returns `x$foo_bar` when `foo` is absent and `foo_bar` is the only key with that prefix.

### A database driver's value is not a base R type — and it fails twice
A column fetched through DBI does not arrive as the base type its SQL type suggests.

### arrow dplyr backend: no grouped slice — bridge to duckdb
- arrow's dplyr backend errors on grouped `slice_max`/`slice_min` (`arrow_not_supported("Slicing grouped data")`).

### as.POSIXct on a Date pins UTC midnight; on a character it uses the machine zone
Construct instants explicitly: a `Date` always becomes UTC midnight whatever `tz =` says, and a character with no zone is read in the machine's zone, so pass `tz =` at parse time.

### as.POSIXct on character infers ONE format for the whole vector
- `as.POSIXct(x)` on a character vector picks a single format by finding the first candidate that parses **every** element — and `strptime` **ignores trailing characters**.

### Inserting a helper between a roxygen block and its function rebinds `@export`
- roxygen2 attaches a block to **whatever object follows it**.

### open_dataset(unify_schemas = TRUE) requires aligned types
- Cross-prefix/file schema unification only merges what types allow: `timestamp[us, tz=UTC]` will not merge with naked `timestamp[us]`, `Grade: string` not with `Grade: double`.

### duckdb larger-than-memory dedup: shard the work — settings won't save you
- duckdb's **window operator** (QUALIFY row_number ...) does not spill enough to survive big partitions (OOM'd an 8 GB limit on a ~124M-row input).

### `nzchar(NA)` is TRUE — non-empty checks silently pass NA
- `nzchar(NA)` returns `TRUE`, so the natural "is this cell filled in" test — `all(nzchar(trimws(x)))` — waves through a column full of `NA`.

### A `for` loop that builds `aes()` captures the loop variable lazily
`aes()` quotes its arguments, so `aes(fill = lab[i])` is not evaluated until the plot is drawn — by which time `i` holds its **last** value.

### `paste()` with a zero-length argument returns length ONE, not zero
`paste0("x", character(0))` is `"x"`, so a key built per element gains one phantom member when the vector is empty; guard the empty case before building keys.

### `strsplit()` drops a trailing empty field, so a trailing separator vanishes
Leading empties survive and trailing ones do not, which is what makes it hard to reason about from memory.

### `identical()` on two reader results tests the reader, not the file
`identical(read_csv(f), read_csv(f))` can be **FALSE** for the same unchanged bytes: readr tibbles carry a `problems` attribute — an external pointer — that differs between reads (readr 2.2.0; `spec` is identical, measured).

### Under `R CMD check`, tests run from a temp dir against the INSTALLED package
Two shapes, both green under `devtools::test()` and broken under `R CMD check`, `devtools::check()`, a tarball check, or an installed-tests run — the direction that costs the most time.

### `dbConnect(SQLite(), path)` CREATES the file, so a read has a write side effect
SQLite creates a database on connect.

### CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests
- `readr::read_csv()` defaults to **`trim_ws = TRUE`** and silently strips leading and trailing whitespace.

### `R CMD check` rejects a filename containing a space
- "checking for portable file names" fails on any file in the built package whose name has a space.

### `sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent
Character sorting in R is locale-sensitive by default, which makes any *canonical* string built by sorting — an XML node with its attributes ordered, a joined key, a manifest — a function of the session's locale rather than of the data:

### A library call that dispatches on a global option is not a pure function
A function whose *units* or *algorithm* are chosen by a session-wide setting behaves differently depending on what the caller did before reaching your code.

### `identical(-0, 0)` is TRUE in R, and the two still digest differently
A hash over R's serialized bytes — which is what `digest::digest()` takes by default — separates positive and negative zero, even though every value comparison says they are the same.

### Two repos pinning the same remote at different tags is an unsolvable install
`Remotes:` pins are per-repo, but resolution is global.

### `file(open = "wb", encoding = )` does not re-encode on write
The `encoding` argument to `file()` governs how bytes coming *in* are interpreted.

### A scalar helper called from `glue()` or `mutate()` recycles instead of erroring
`glue()` vectorises over its inputs.

### Never name a durable artifact by a hash the library reserves the right to change
`rlang::hash()` carries **no cross-version stability guarantee**, and rlang says so in its own NEWS for 1.3.0:

### `vapply(..., USE.NAMES = FALSE)` strips ALL dimnames, row names included
A named `FUN.VALUE` looks like it guarantees row names on the returned matrix.

### `source()`ing a config into the render environment leaks it into the next render
`source(params$config)` inside an Rmd puts every config value into the environment `render()` evaluates in.

### One very long table cell hangs paged.js, and it presents as a Chrome timeout
A ~600-character free-text field in a `kable` cell wedged `pagedown::chrome_print` indefinitely.

### `stats::aggregate()` has three separate silent behaviours, and each fails in a different direction
All three measured on R 4.5, all three met inside one 800-line script (drift#67).

### `deparse(body(f))` excludes formal defaults, so a body scan cannot see a default
A guard that scans function bodies for a forbidden literal is blind to that literal in a **signature**.

### `deparse()` re-encodes non-ASCII, so it answers about itself rather than the file
Scan R source for non-ASCII the way `R CMD check` does (`tools:::.check_package_ASCII_code()`: raw lines, comments skipped), not through `parse()` and `deparse()`, which turn `\uXXXX` escapes into literal characters and back.

### `package_version()` errors on a pre-release version string
`package_version("3.9.0beta1")` raises rather than returning `NA`, so strip a pre-release suffix before asserting a version floor.

### `tryCatch(warning = )` DISCARDS the value the expression produced
A `warning =` handler is not a filter — it replaces the whole expression, so a call that **succeeded** and merely warned returns the handler's value and the result is thrown away.

### `match()` treats NA as a matchable VALUE, so two unknowns join to each other
`match(NA, c("1", NA))` is **2**.

### `expect_message(expr, regexp)` checks only the FIRST condition, so a progress line hides the message under test
testthat 3e captures the first message the expression emits and matches the regexp against **that one**.

### `pak` refuses to install a package that needs no compiler
`pak::pak()` routes through `pkgbuild::check_build_tools()`, which fails with *"Could not find tools necessary to compile a package"* whenever `xcode-select -p` points at `/Applications/Xcode.app/...` while the Command Line Tools are what is actually installed — **regardless of whether the package has any compiled code**.

### `as.integer("NaN")` is `0`, and `as.integer(NaN)` is `NA`
The string round trip is the bug.

### `expect_false(identical(x, y))` cannot fail when the two are different types
`identical()` is type-strict, so it is already `FALSE` for any pair that differs in storage mode — and an assertion that the defect would make *true* then cannot fire.

### `unlist()` prefixes a `split()` group's name, so reassembling by name silently yields all-NA
Putting per-group results back in input order by naming them looks right and returns nothing:

### `tolerance` in testthat is RELATIVE, so it pins a published figure far more loosely than it looks
`expect_equal(x, 12.529, tolerance = 2e-2)` accepts anything within **two percent** — so a figure published to three decimals survives drifting to `12.629`.

### `cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation
Two ways a `cli` message loses a value.

### `[[` on a named ATOMIC vector with an absent key is an error, not `NULL`
A list returns `NULL` for a missing `[[` key.

### `data.frame()` recycles a scalar against a zero-length column
It does not yield a 0-row frame — it raises, because a length-1 column and a length-0 column cannot be recycled together:

### A dot-prefixed column name can be swallowed by the verb's own formal
`mutate(x, .d = expr)` does not create a column called `.d`.

### `summarise()` and `mutate()` evaluate in order, so a later argument sees the summarised column
Once `frames = sum(frames)` has run, `frames` inside the next argument is that one-row sum, not the group's vector.

### `\<` and `\>` are word boundaries in R's default regex, not escaped `<` and `>`
Leave `<` and `>` unescaped when you build a pattern from data.

### `tempfile()` lives in the session tempdir, so a path printed in an error names a file R is about to delete
R removes its session `tempdir()` on exit, including after `stop()`.

### R's `yaml` returns a mixed int/float sequence as a list, not a numeric vector
`yaml::read_yaml()` simplifies a sequence to a vector only when every element has the same type, so `[0.164, 9999]` comes back as `list(0.164, 9999L)` while `[0.0, 9999.0]` is `c(0, 9999)`.

### testthat's failure snapshots land in `tests/` and ride in on `git add -A`
testthat 3e writes `tests/testthat/_problems/*.R` and `tests/testthat/testthat-problems.rds` when tests fail.

### A pick whose `ORDER BY` ends on a key that is not unique in the group returns an arbitrary row
`DISTINCT ON (k) … ORDER BY k, a, b` is deterministic only if `(a, b)` is unique within each `k`.

### `sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words, which Postgres reads as column names
A numeric formatter such as `sprintf("%.10g", x)` has no SQL form for non-finite values, so an open-ended range (`c(min, Inf)`, typically a blank `max` filled with `Inf` by a params loader) produces `x <= Inf`, and Postgres fails with `column "inf" does not exist`.

### An `information_schema` lookup by the literal table name misses what Postgres resolves
`WHERE table_schema = 's' AND table_name = 'T'` compares the text you passed, but Postgres folds unquoted identifiers to lower case, puts temp tables in `pg_temp_N`, and resolves unqualified names through `search_path`.

### Rscript reads a script as it runs, so never edit a script while a run of it is in flight
Copy the script and run the copy (`cp scripts/x.R "$TMPDIR/x_frozen.R" && Rscript "$TMPDIR/x_frozen.R"`) for anything long-running, or leave the file alone until the run exits.

### A range total taken as the difference of two large running totals loses the small ranges
Sum a range directly (segment tree, per-range `sum()`, or grouped sums) rather than as `cumsum[hi] - cumsum[lo]` when ranges are small relative to the running total.

### A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared
`R CMD check` warns "'::' or ':::' import not declared from" for any package a test reaches with `::` that `DESCRIPTION` does not list, and under `error-on: "warning"` that reddens every runner.

### Inside a dplyr verb, a column named like a local variable wins
Inject a local value into a data-masked verb with `!!x` or `.env$x`, never a bare `x`: `transmute(d, aoi_id = id)` inside `for (id in ids)` reads the frame's own `id` column whenever one exists, with no warning, and the result is well-typed and plausible.

### `earthdatalogin`'s search and download calls overwrite the netrc when they find no Earthdata entry
Call NASA's CMR search with `curl` and download with `curl` given the netrc directly (`netrc = 1, netrc_file = <path>, cookiefile = ""` follows the URS redirect), or check `earthdatalogin:::has_edl_netrc()` yourself first.

### A fetcher's test helper must make the network fail, not just mock the reader
When a test mocks a downloader's reader and supplies fixture files, also mock the search and download functions to `stop()` by default, and re-mock them only in the tests that exercise that path.

### testthat 3e `expect_message()` returns the condition, not the expression's value
Assign inside the call, `expect_message(h <- f(x), "msg")`, never `h <- expect_message(f(x), "msg")`.

### `c()` dispatches on its first argument, so `c(NULL, <Date>)` is a plain number
Put a Date first when `c()` combines an optional piece with Dates: `c(NULL, <Date>)` takes the default method and returns a bare day count.

### `bind_rows()` of all-`NULL` is a 0 x 0 tibble, and a typed template must take its types from the rows' source
Bind per-group results under a zero-row template so an all-dropped result keeps its columns, and build that template's key columns from the same object the rows are built from (`combos$variable[0]`, not `character()`).

### `sample.int(prob =)` without replacement is not a probability-proportional draw, so weighting its result again double-counts
Draw a subsample to be design-weighted **uniformly** (`sample.int(n, k)`), or keep every unit.

# Code Check — Shell
Tool-level traps in bash, sed, git and `gh`, and in the host toolchain those commands depend on.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check-shell.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

### `git diff a..b` compares TIPS; a change on `a` shows up as the branch's
Use three-dot `git diff a...b` for what a branch changed; two-dot compares the tips, so changes that landed on `a` show up as the branch's, inverted.

### git pathspec excludes: use the long form
- `:!path` is short-form magic, and git keeps parsing magic characters after the `!`.

### `sed 1d f1 f2 f3` strips only the FIRST file's header
`sed` treats multiple file arguments as one concatenated stream, so a line-address script applies once across the whole set rather than per file.

### `sed -n '/X/,$d' file` prints nothing at all
`-n` suppresses auto-print, and `d` only deletes — so nothing is ever emitted and the output is empty.

### Reading a file line-by-line drops the last line without a trailing newline
- `while IFS= read -r line; do ...; done < file` skips a final line that has no newline after it.

### Empty arrays under `set -u` on bash 3.2
- macOS still ships bash **3.2**, where `"${ARR[@]}"` on an empty array is an unbound-variable error under `set -u`.

### Quoting
- Variables in double-quoted strings containing single quotes break if value has `'`

### Heredoc precedence in pipelines
- `cmd1 | cmd2 <<EOF` — the heredoc binds to `cmd2` (the rightmost simple command).

### Paths
- Hardcoded absolute paths (`/Users/airvine/...`) break for other users

### Diagnose env/PATH problems in the shell that actually runs, not the ambient one
- Get ground truth **before** forming any theory: `env -i HOME=$HOME TERM=$TERM bash -lc 'echo $PATH | tr ":" "\n" | nl'` (swap in `zsh` to check the other side).

### Parallel writers sharing one output file interleave mid-record
- `xargs -P N ... >> shared_file` (or any fan-out where N processes append to the same fd/path) is only safe while each record fits in a single `write()`.

### `mktemp` template needs enough X's, and a failed `mktemp` leaves an empty var
- BSD/macOS `mktemp -d -t <name>` requires the template to contain at least 3 `X`s (`XXXXXX` is the safe default).

### `cmd dir/*` dies on ARG_MAX at scale — and only after the expensive work succeeded
- A glob expands to argv.

### A `curl` in a parallel fan-out needs `--max-time`
- Without it, one hung connection pins a worker slot indefinitely.

### BSD vs GNU sed/grep portability (macOS hits this constantly)
- macOS ships BSD `sed`/`grep`.

### On this Mac `stat` and `date` are GNU, so the same flag letter means something else
Here Homebrew puts GNU coreutils ahead of `/usr/bin`, so BSD-style `stat -f` and `date -r <epoch>` mean something else; prefer a flavour-free form (`find -newermt`, `python3`), or call the binary by absolute path.

### `&` binds to the whole `&&` list, so assignments never reach the parent
- `cmd1 && VAR=$(...) && nohup prog > "$VAR.log" & disown` backgrounds the **entire list**, not just `nohup`.

### `gh` CLI
- **`gh pr create` resolves branch from CWD, not `--repo`**.

### On a fork, `main` may track upstream by design — comparing it answers nothing
`gh api repos/ORG/REPO/compare/upstream:main...ORG:main` returning `ahead: 0, behind: 0, status: identical` reads as *"this fork has no local work"*.

### A destructive setup and its undo must not share one timeout-able command
Never chain a destructive setup and its undo (`git stash && slow && git stash pop`) in one timeout-able command; compare with `git show HEAD:path`, or restore from one `trap … EXIT` handler guarded by a flag set once the setup happened.

### `git checkout <path>` restores from the index, not from HEAD
After a `git add`, `git checkout <path>` reinstates the broken *staged* copy — so the "fix" reproduces the failure and reads as though the edit was wrong.

### A value validated with one numeric grammar and consumed with another
Normalise a numeric string once (digits only and at most 9 of them, then `x=$((10#$x))`, then a bounded range): `test` reads base 10, `$(( ))` reads a leading zero as octal and wraps past 2^63.

### `wait` with no argument waits for every background job in the shell
Wait on the PIDs you started (`wait "$pid"`), because a bare `wait` also blocks on every other background job in the shell.

### `if ! cmd; then rc=$?` captures the negation, not the command
Inside the branch, `$?` is the status of the `!` compound — which is **0 by construction**, because the negation succeeded.

### A `pgrep -f` waiter matches its own command line, so it never exits
Wait on a PID with `while kill -0 "$PID"; do sleep 30; done`, never on `pgrep -f "job"`, whose pattern matches the waiting loop's own command line so it never exits.

### `timeout` is GNU coreutils — a portable deadline
An assertion around something that might hang can only pass or hang, never fail (`code-check.md`, "Restore the bug and prove the guard fires").

### `aws s3 cp` cannot tell a missing key from a missing bucket
`aws s3 cp` gives one exit 1 and 404 text for a missing key and a missing bucket, so probe `s3api head-bucket` then `head-object`: only a 404 from a reachable bucket means absent; a 403 is permissions.

### A verification command can be shadowed by a shell function or alias
- The shell is initialized from the user's profile, so `diff`, `grep`, `ls`, `cat` and friends may resolve to a wrapper rather than the binary you assume.

### psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0
Two traps in the same file type, both of which read perfectly and fail at run time.

### A second `trap … EXIT` replaces the first
`trap` registers **one** handler per signal.

### A `local` statement cannot read a variable it is assigning in the same statement
`local a="$1" lab="$2" m="/tmp/marker_${lab}"` expands `${lab}` **before** `lab` is assigned.

### Inside an `EnterWorktree` session, the Bash tool refuses command text that names git
The harness applies an isolation guard to a session that entered a worktree: *"a worktree-isolated session's git operations must target its own worktree."*

### A `git filter-repo` seed carries the source repo's tags, and a path sed misses the language's path constructor
Two traps from seeding one repo out of another's history (fish_passage_template_reporting#236, 2026-09-02), both silent.

### `git check-ignore -v` prints the matching pattern, and its exit status is not a per-file verdict
`-v` reports the **last matching pattern**, negations included.

### `sips -Z` scales up as well as down
`sips -Z N` resamples so the longest side is N — in **either** direction.

### Assert capabilities, not versions — a tool upgrade can remove one silently
A tool upgrade across the fleet can remove a capability without reporting failure.

### An amd64-only image needs `--platform`, and it works on your machine because it is cached
`docker run` resolves from the local image store before it reaches a registry, so on an arm64 Mac an amd64-only image runs fine once pulled — **and the command that pulled it is not necessarily the one in the code.**

### Headless Qt in a container needs `QT_QPA_PLATFORM=offscreen`, and without it the run hangs or crashes
Pass `-e QT_QPA_PLATFORM=offscreen` to any `docker run` that starts QGIS or another Qt program with no display.

### `s3cmd ls` given several paths lists only the FIRST, and says nothing
Query one path per `s3cmd ls` call, or `--recursive` on the prefix and `grep`: given several paths it lists only the first, with exit 0.

### `grep -c` prints the count AND exits 1 when it is zero
Write `n=$(grep -c …) || n=0`, never `|| echo 0` inside the substitution: `grep -c` already prints `0` and exits 1, so that fallback appends a second line, while the bare assignment aborts a `set -e` script.

### A failed `git fetch` leaves the comparison you make next reading stale refs
`git fetch` and the check that follows it are two commands, and nothing links them.

### macOS `/usr/bin/awk` aborts when a regex meets a byte slice that cuts a multibyte character
Test a `substr()` slice with `==`, never with `~`, `match()` or `sub()`: the stock macOS awk counts bytes in `substr()` but converts a regex operand to wide characters, and a partial UTF-8 sequence kills the whole program.

### A variable in a sed replacement is parsed, so its `\` and `&` are not literal
Never interpolate data into the replacement half of `sed "s#…#$var#"`: sed reads `\(` as `(`, and `&` as the whole match, so the line written is not the value held.

### A fetch can fail and still deliver the commit, so when you need an object, test the object
When the goal is a specific commit, resolve its sha first (`git ls-remote`) and test `git cat-file -e "$sha^{commit}"` after the fetch rather than the fetch's exit status.

### A default `GIT_SSH_COMMAND` outranks the machine's own ssh choice
Supply a default ssh command only when `GIT_SSH_COMMAND`, `core.sshCommand` and `GIT_SSH` are all unset.

### `curl -o` without `-L` saves the redirect page as the download
`curl` does not follow redirects unless it is given `-L`, and it exits 0 on a 3xx.

### `conda run` captures its child's output, so a pipe gets nothing
`conda run -n env cmd` buffers the child's stdout and re-emits it, and that re-emission does not reach a pipe.

# Code Check — Spatial
terra, sf, bcdata, GDAL/OGR CLIs.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check-spatial.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

### Negative coordinates get parsed as CLI options — every BC bbox hits this
- BC longitudes are all negative, so `--bounds -124.73 49.485 -124.595 49.565` fails with `Error: No such option: -1`.

### bcdata: an empty result raises AttributeError, it does not return an empty collection
- A bbox query matching nothing exits non-zero with `AttributeError: You are calling a geospatial method on the GeoDataFrame, but the active geometry column to use has not been set.` — geopandas complaining about an empty frame, several layers below the query.

### bcdata: `BBOX()` rejecting a bbox that is a length-4 numeric vector — seen once, unquoting fixed it
If `bcdata::BBOX()` rejects a length-4 numeric bbox as not a length-4 numeric vector, try unquoting it with `!!`; this was seen once and the mechanism is not established.

### terra: operator dispatch and edge cases in package code
- **SpatRaster `%in%` is not dispatched when terra is *imported* (only when *attached*).**

### terra: `extract()` returns no row for ground beyond the raster, and counts cells by centre
- Two traps in one call, and both make a partial result look complete.

### A `...` constructor may discard trailing arguments based on the class of the first one
- A constructor that takes `...` is free to branch on **what its first argument is** and build the result from that alone.

### terra: `mask()` is `touches = TRUE`, so two "clip to the polygon" routines disagree by a cell ring
Swapping one polygon clip for another looks like a refactor and is a **methodology change**.

### terra: `sources()` on a derived raster is `""` or a random temp path, never the input
- A raster that came out of `crop()`, `project()`, `mask()`, or arithmetic is **derived**, so it has no source file.

### `sf::st_as_binary()` returns a LIST of raw vectors, so `is.raw()` on it is FALSE
The obvious way to feed WKB into a canonicalizer is a `is.raw(x)` branch that hex-encodes it.

### Canonicalize geometry before hashing it — ring order and orientation are not fixed by topology
`code-check.md`'s cache-key row prescribes hashing WKB (`sf::st_as_binary(sf::st_geometry(x), endian = "little")`) rather than the sfc object.

### sf: `st_join(largest = TRUE)` ignores the join predicate
`st_join(largest = TRUE)` matches by intersection area whatever `join =` says, and drops zero-area geometries, so point and line overlays cannot use it.

### sf: name validation must account for the geometry column
- The active geometry column is a named entry in `names(x)`, but its name is **not fixed** — `"geometry"` from `sf::st_read()` of some sources, `"geom"` from a GeoPackage/PostGIS layer, `"geometry"` or `"_ogr_geometry_"` elsewhere.

### sf: `st_intersection()` / `st_difference()` return a GEOMETRYCOLLECTION that QGIS will not draw
- Intersecting or differencing two polygon layers yields a `GEOMETRYCOLLECTION` wherever the inputs *also* touch along a line or at a point.

### sf: reproject the polygon to get a lat/lon bbox, never transform the projected bbox corners
- To hand a geographic (EPSG:4326) bounding box to a bbox-filtered query (WFS/OGC features, `?bbox=`), reproject the whole AOI **geometry** then take its bbox: `sf::st_bbox(sf::st_transform(aoi, 4326))`.

### An offset regex must be anchored to a time, or a date looks like a zone
- Refusing or stripping a trailing UTC offset with something like `[+-][0-9]{2}(:?[0-9]{2})?$` also matches the end of a plain ISO date: `"2026-08-15"` ends in `-15`, which reads as a −15 hour zone.

### A reader that accepts a UTC offset may not be applying it
GDAL accepts a UTC offset in a GeoPackage `DATETIME` and silently drops it, returning wall-clock digits that are then read in the machine's zone, so one file gives a different instant on every machine.

### Ask the file about its field names, not R
`sf::st_read()` returns a data frame, and R makes column names syntactic on the way in.

### QGIS embeds a layer's style in the `.qgs`, so rewriting the `.qml` sidecar changes nothing
A `.qgs` carries each layer's style **inside** its `<maplayer>` node — the sidecar's children are copied in when the layer is declared.

### A GeoPackage is a SQLite database, and that leaks in three ways
Writing to one directly (a `layer_styles` row, an attribute fix) is a plain `INSERT` and needs no GDAL.

### The same leak reaches R and OGR SQL, and a GeoPackage's bytes are not its content
Edit a live GeoPackage through GDAL (`ogrinfo -sql`) rather than RSQLite, and assert row state rather than `dbExecute()`'s count, which includes trigger writes.

### Restoring a GeoPackage from a copy: refuse sidecars before the first read, delete them before the copy-back
A byte copy of the main file is a snapshot only when no `-journal`, `-wal` or `-shm` exists and the header is in rollback mode (bytes 18-19 = `01 01`).

### A coordinate stored as an attribute can disagree with the geometry it describes
A spatial layer that also carries `LATITUDE` / `LONGITUDE` columns has the same fact twice, and nothing keeps them consistent.

### GeoJSON in a projected CRS is silently non-portable
`sf::st_write()` and `ogr2ogr` will write GeoJSON from a projected object and emit a `crs` member naming it:

### `sf::st_perimeter()` needs lwgeom on projected data, and lwgeom is not a dependency of sf
An exported sf function whose body branches on `requireNamespace("lwgeom")` is an undeclared dependency: `R CMD check` does not report it, and a test suite cannot see it on a machine that happens to have lwgeom installed.

### terra keeps a result in memory whenever it fits, so a per-class loop over a large grid accumulates full-grid rasters
`ifel()`, `focal()`, arithmetic and `rasterize()` return in-memory SpatRasters whenever the result fits under `memfrac` (60% of RAM by default).

### `geom_sf(data = NULL)` draws nothing, silently
A `NULL` `data` argument does not error and does not warn — the layer inherits the plot's data, which for `ggplot()` with no global data is empty, so it contributes a **zero-row layer**.

### terra: `app()` calls a vector-tolerant `fun` once per CELL, and reads a 5-column return on a 5-column raster as transposed
Two contracts inside `terra::app()` that read as the opposite of what they are, both measured on terra 1.9.34 (drift#9, 2026-09-05):

### terra: `levels<-` and `coltab<-` copy before they strip; `set.cats(NULL)` is the in-place form
`levels<-` and `coltab<-` deep-copy before stripping, so a caller-untouched test cannot fail under them; `terra::set.cats(r, layer = i, value = NULL)` strips in place and mutates whatever raster it is given, so use it on a copy you own.

### terra `metags()`: the empty case is `NULL`, and the sidecar is half the artefact
Three measured facts about raster **container** metadata, all of which fail quietly (floodplains#83, 2026-09-05, terra 1.9.34 / GDAL 3.8.5).

### `ggmap`: a fixed `zoom` silently crops points off the basemap, and `calc_zoom()` does not fix it
`ggmap::get_map()` fetches ONE fixed-size image at whatever `zoom` it is given.

### terra: `zonal()` outside its six-function fast path materializes the WHOLE grid in R
`terra::zonal()` dispatches to C++ only when `fun` is one of `max`, `min`, `mean`, `sum`, `notNA`, `isNA`.

### sf: close a rotated ring by copying the first vertex, never by recomputing it
Rotating a polygon by multiplying its whole vertex matrix — `xy %*% rot` — looks exact, and for a ring built closed it is not.

### terra: `plot(type = "classes", levels =, col =)` maps colours by POSITION, per layer
A `levels`/`col` pair is not a value-to-colour mapping.

### terra: `wrap()` carries the tempfile basename in `varnames`, so a committed artifact churns
Set `varnames` and `longnames` before `wrap()` or writing a raster produced with `filename = tempfile()`, or the random tempfile basename makes a committed artifact change on every run.

### `terra::plot()` leaves the device in a state where a keyword-placed `legend()` draws nothing
`graphics::legend("topleft", …)` after a `terra::plot()` or `terra::plotRGB()` **silently draws nothing** — no error, no warning, and the rest of the figure renders normally.

### A name is not a key: `GNIS_NAME` matches features all over BC
`filter(GNIS_NAME == "Buck Creek")` returns every Buck Creek in the province.

### `sf::st_read()` on a KML drops `<SchemaData>`, silently
GDAL has two KML drivers and picks `KML` by default, which does not read the `<SchemaData>` block.

### GDAL applies `-srcnodata` and an alpha mask together, and the mask loses
Two ways of saying "these pixels are not data" reach `gdalwarp` independently, and giving it both is not an error — it is an instruction to do both.

### `parallel::mclapply()` over a remote raster aborts every fork on macOS, and the wrapper exits 0
GDAL's curl handles do not survive a fork.

### terra: `align()` defaults to `snap = "near"`, so the aligned window need not contain the input
`terra::align(e, r)` snaps each edge of `e` to the **nearest** cell boundary of `r`, which moves an edge *inward* as readily as outward.

### GDAL reserves 3,276 MB per process before reading a cell, and PSOCK workers outlive their master
Two independent reasons a parallel raster job uses far more memory than its data, both measured 2026-09-20 on a 64 GB machine (fly#58) while a sweep was killed four times.

### `terra::distance(x, target = NA)` measures FROM the NA cells, so every data cell reads 0
Reaching for it to answer "how far is each data cell from the nearest nodata" gives the opposite: `distance()` fills the **target** cells with their distance to the nearest non-target, so data cells come back `0` and any `dist < threshold` test is true everywhere.

### `summarise()` on a grouped `sf` returns an `sf`, and the geometry rides into your CSV
`dplyr::summarise()` dispatches to `summarise.sf` on an `sf` object.

### A raster's drawn footprint is its valid data, not its extent
Before comparing a rendered shape against a raster, get the raster's valid-data window, not its bbox.

### `sf::gdal_utils()` does not raise when GDAL cannot open the source
Test the result before parsing it: `gdal_utils("info", ...)` on a source GDAL cannot open - an unreachable url, a missing key - **warns and returns `character(0)` or `NA`**, and the next `jsonlite::fromJSON()` dies with *"invalid char in json text"*, which names nothing about the cause.

### A shift measured on one grid is wrong when applied on another
Apply a displacement in the CRS it was measured in: transform the point there, add the shift, transform back.

### Writing KML: `<color>` is `aabbggrr`, and a remote icon href renders nothing offline
Do the hex swap in **one** helper and omit `<Icon><href>` entirely.

### `rio cogeo validate` exits 0 when the file is NOT a valid COG
It reports the verdict in text and returns success either way, so the exit status carries no information at all:

### `terra::rast()` on a SpatRaster returns an empty template, not a copy
Pass a SpatRaster through as is (`if (inherits(x, "SpatRaster")) x else terra::rast(x)`): `rast(x)` on one builds a new raster with the same geometry and **no values**, so a function that normalises its input with `terra::rast()` silently receives an all-empty grid when handed an object rather …

### `terra::rasterize(filename = , datatype = <integer>)` writes the background as 0, not NA
Rasterise in memory and then `writeRaster(datatype = …)`: written directly through `filename` with an integer `datatype` (INT1U, INT2S), cells no polygon covers come out as 0, while the file's NoData is 255, so they read back as data (terra 1.9.46 and 1.9.50; rspatial/terra#2195).

### GDAL's `average` warp across a rotated CRS weights the wrong pixels; average in the target CRS instead
To take class fractions or means from a fine grid in one CRS onto a coarse grid in another, resample nearest onto a grid aligned with the target and `fact` times finer (`terra::disagg(terra::rast(target), fact)`), then `terra::aggregate(fact, mean)`.

### `terra::densify()` on lon/lat follows great circles, so a raster extent's parallel edges bow poleward
Pass `flat = TRUE` (with the interval in degrees) when densifying a lon/lat extent before projecting it.

### Planetary Computer STAC: a floodplain-scale read hits three limits a reach never does
Query a large AOI by its convex hull, re-sign items before each tile, and give `datetime` explicit times (`…T00:00:00Z/…T23:59:59Z`).

### gdalcubes reports failed chunk reads only on stderr, so a partial cube passes as complete
Do not guard on it by capturing output.

### terra reads a multi-variable gdalcubes NetCDF with its variables in alphabetical order
Select layers by name after `terra::rast()` of a `gdalcubes::write_ncdf()` output, never by position.

### terra's COG writer emits a `.aux.json` sidecar when the raster carries a time
Strip `time` (and `units`, `varnames`, `longnames`, `metags`, `scoff`) before `writeRaster(filetype = "COG")`, or have the publisher move `<file>.aux.json` with the raster.

### `sf::st_read()` promotes a mixed POLYGON/MULTIPOLYGON layer to all-MULTIPOLYGON
Read with `promote_to_multi = FALSE` whenever a layer will be written back.

### `sf::st_make_valid()` rewrites geometry that was already valid
Run it on the invalid rows only (`!st_is_valid(x)`), or keep the original geometry and use the made-valid copy just for the computation.

### terra: `unique()` and `freq()` on a factor return its labels, not its codes
Read a factor raster's codes from a copy with its levels stripped (`levels(y) <- NULL`, or `set.cats(y, layer = 1, value = NULL)` on a copy you own), never from `terra::unique(x)[, 1]` or `terra::freq(x)$value`: on a factor both return the active category's labels, so matching …

### A GDAL failure partway through `sf::st_read()` returns the rows read so far, with only a warning
Treat any warning during a read whose completeness matters as a failed read: wrap it in `withCallingHandlers(st_read(...), warning = function(w) stop(...))`, retry, then stop.

### `terra::project()` over a remote strip-organised TIFF issues a range request per strip, so download it first
Check `gdalinfo` for `Block=<width>x1` before reading a remote raster through `/vsicurl/`, and where it is strip-organised (one row per block, no overviews) download the whole file to a tempfile and read that.

### LidarBC tiles can carry an undeclared nodata of -3.4e38, which a mean takes as data
Clamp a LidarBC DEM or DSM to plausible elevations before any aggregate: `terra::clamp(r, -100, 5000, values = FALSE)`.

### bcdata returns a column whose values are all missing as character, not numeric
Coerce every field you do arithmetic on (`as.numeric(v$PROJ_AGE_1)`) right after `bcdata::collect()`.

# Code Check Conventions
Structured checklist for reviewing diffs before commit.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

## Mechanisms
Fourteen shapes that keep producing bugs.

### A guard that fails toward pass
A check decides whether to do something consequential — cut a tag, run a migration, report a sweep clean.

### A fixture that cannot reach the failure mode
Hand-picked fixtures test the cases you thought of.

### A proxy is not the property
A condition that stands in for the thing you actually want.

### Verification that reads its own output
A check whose reference was produced by the thing it checks cannot disagree with it.

### A guard's scope, escape hatches, and remedies
Every guard grows the things that silently disable it.

### A fix lands in one of two callers that share a harness
Two entry points over one library, two workflows over one action, two scripts sourcing one shell lib.

### Restore the bug and prove the guard fires
A test that stays green against the code it was written to reject is decoration, and reading it will not tell you.

### A shared working tree, and what generators leave in it
A working tree has one checked-out branch.

### A wrapper's exit is not the work
A wrapper reports its own exit.

### Zero-length, empty, and unset are three different things
`paste0(character(0), "x")` is `"x"` — one phantom row from an empty frame.

### The probe is broken before the world is
When an ad-hoc probe reports that long-shipped code is broken, the prior belongs on the probe.

### Written data outlives the fix
Changing the writer changes nothing already written.

### Serialization loses meaning silently
Set `na=` and `null=` explicitly on every writer, because a serializer's default for no value is usually a valid-looking value (`"NA"`, `{}`, `'None'`) that every schema check accepts.

### One fact derived twice
A count taken from one artifact and the things counted produced from another, with a guard comparing the two.

## Rules that stand alone
General, and not an instance of a mechanism above.

### Do not edit files a long test run is reading
- `devtools::test()` (and most runners) load each test file **when they reach it**, not at launch.

### Test a persistent change through its per-process override first
A setting that is changed once and persists — `xcode-select -s`, a git config key, a registered default, an installed symlink — usually has an environment variable or flag that overrides it **for one process**.

### Adopting Existing Config
When importing config from one location into a canonical one (legacy `~/.bash_profile` → dotfiles repo, old script's env → repo, another project's `settings.json` → soul):

### Test the cold/create path of idempotent code, not just the warm no-op
- Idempotent provisioning code (a resolver-file writer, a config installer, a "create unless present" block) has two paths: the **cold** path that actually creates/writes, and the **warm** path that detects "already present" and skips.

### Fetch an expiring credential just before its first use, not at job start
Put the step that fetches short-lived credentials immediately before the first step that uses them.

### Do not write to an artifact a human is testing on
- Handing someone a deployed thing to test — a synced project, a staging database, a preview build — and then continuing to push changes into it makes two writers for one artifact.

### Percent-encode a URL at construction, not at consumption
- A URL built by string-concatenation from filenames inherits whatever those filenames contain.

### A preview flag is only safe if it previews
- `--dry-run`, `DRY=1`, `--plan` conventionally mean "show me what would happen".

### Bare `y`, `n`, `on`, `off`, `yes`, `no` are booleans in YAML 1.1
- The YAML 1.1 core schema resolves `y`, `Y`, `n`, `N`, `yes`, `no`, `on`, `off`, `true`, `false` (and their case variants) to **booleans**.

### Documentation Staleness
- Moving/renaming scripts: update CLAUDE.md, READMEs, usage comments

### An ordered dispatch makes severity ordering load-bearing, and nothing enforces it
A `CASE`, an `if/elif` chain, or any first-match dispatch that reports a *verdict* carries an unwritten invariant: every serious arm precedes every advisory one.

### A link to a repo-hosted artifact must be *tracked*, not merely present
When the published site **is** the repository — GitHub Pages serving `docs/`, or a `raw.githubusercontent.com` URL — the question "does this file exist" is the wrong predicate.

### An assertion that matches an interpolated value cannot see the claim around it
`expect_error(f(x), "some_column")` looks like it pins the guard.

### A pluralisation marker takes the quantity of whatever was substituted last
`cli`'s `{?a/b}` reads the most recent quantity in the string, and **any** substitution resets it — including a length-1 one that is not what the marker is about.

## Security

### Process Visibility
- Secrets passed as command-line args are visible in `ps aux`

### Secrets in Committed Files
- `.tfvars` must be gitignored (contains tokens, passwords)

### Firewall Defaults
- `0.0.0.0/0` for SSH is world-open — document if intentional

### Credentials
- Passwords with special chars (`'`, `"`, `$`, `!`) break naive shell quoting

### Gitleaks pre-commit hook
Configuration patterns and false-positive handling for the `gitleaks` pre-commit hook (kdot's Brewfile ships `gitleaks` + `pre-commit`; cyclops standardizes the hook):

### "Public bucket" ≠ listable: GetObject vs ListBucket
- A bucket policy granting only `s3:GetObject` on `bucket/*` makes exact-key fetches public but NOT listing — and dataset discovery (`arrow::open_dataset()`, duckdb globs, STAC `/vsicurl/` directory reads) requires `s3:ListBucket` on the **bucket ARN** (no `/*`; it's a bucket-level action).

## Spreadsheets and PDFs

### A stored value is not wrong just because the raw number looks wrong
Before reporting that a spreadsheet value is off by a factor, check the cell's **number format**.

### Verify PDF links from the annotations, not the extracted text
`pdftotext` returns anchor text, not the href.

### Extracted PDF text carries corrupted glyphs, and a tolerant parser turns them into wrong numbers
Never strip non-digits to clean a number extracted from PDF text: corrupted glyphs (an `O` for a `0`, a Private Use Area micron sign) become plausible wrong values, so anchor on the label and check against an independent identity.


# Comms Conventions

This repo has a `comms/` directory — you're in the cross-repo Claude-to-Claude messaging system. Full protocol in `comms/README.md`. Peer list (who to scan) in `soul/conventions/comms_peers.md` (internal-only). Load-bearing behaviors below.

## On Session Start

1. **Inbound scan.** `<this-repo>/comms/*/` — files with `status: open` and mtime newer than your last `comms/` commit are mail for you.
2. **Outbound scan.** For each peer in `comms_peers.md`, check `<peer>/comms/<this-repo>/*.md` — files with `from: <this-repo>, status: open` are your un-answered sent mail.

If either surfaces open threads, raise to the user before starting other work.

## Commit Prefix

- `comms(→peer):` — you committed a file in peer's repo (outbound)
- `comms(←peer):` — you committed a file in your own repo (inbound reply)
- `comms:` — meta (close, reopen, rename, README update)

Arrow points to the repo whose `comms/` contains the file you committed.

## Non-negotiables

- One commit per appended message.
- **Push immediately.** Un-pushed comms is invisible to the other Claude.
- Code + comms = separate commits.
- Status flips bundle with the triggering message.
- **Use `git commit --only <file>`** for any commit in a peer's repo (thread files). Immune to index races from parallel sessions.

## Propagation: soul publishes, peers pull

Soul is the source of truth for `comms/README.md`. Peers sync by running `/comms-init` in their own repo, from their own Claude session. **Do not push README updates into a peer's repo from another session** — cross-session index races can bundle unrelated staged files into misleading commits.

Within your own session, the only things you commit into a peer's repo are **thread files** (hosted in the receiver's repo per the receiver-hosts rule). Everything else — README syncs, infra — the peer-Claude pulls itself.

### Cross-repo thread commits: which branch?

Commit on peer's **current branch** — whatever they've got checked out. Don't stash, switch, or force main.

If peer isn't on main, surface to the user: _"thread landing on `<peer>`:`<branch>`, won't hit main until PR merges. Continue or hold?"_ If peer has complicated local state (mid-rebase, partial merge), defer to the user.


# NGE Feature Workflow

For non-trivial issue-driven work, follow this checklist. Each step exists for a reason — skipping leads to rework, broken builds, and avoidable bugs that we've hit repeatedly.

## The Sequence

1. **Start with `/planning-init <N>`** — given an issue number, enters plan mode for codebase exploration, presents a phase breakdown for user approval, then scaffolds branch + PWF baseline with the approved phases. One command replaces the manual issue → explore → plan → branch → scaffold dance.
2. **Write robust tests first** — failing tests that reproduce the issue or document the new behavior. Tests are the contract; they fail until the work makes them pass.
3. **Name with intent** — functions, parameters, internal helpers carry the naming style of the package they live in. Look at existing exports as the guide; consistency over cleverness. For files rather than functions — shell scripts and operational R scripts under `scripts/` or `data-raw/` — the standard is the `noun_verb-detail` pattern in `newgraph.md`, noun first.
4. **Examples that run** — every exported function gets a runnable `@examples` block. Pkgdown renders them; CI executes them. An example that doesn't run is documentation rot.
5. **Code-check before each commit** — `/code-check` on staged diff. Catches what tests miss: edge cases, hard-coded paths, unguarded variables, security issues.
6. **Atomic commits** — each commit bundles code change + checkbox flip in `task_plan.md`. The diff and the progress live in the same commit; `git log -- planning/` tells the full story.
7. **`/planning-archive` when complete** — moves PWF to `archive/YYYY-MM-issue-N-slug/`, creates a fresh `active/`. Then `/gh-pr-push` opens the PR; `/gh-pr-merge` handles the release bookkeeping.

## Where the checkpoints are not

Step 1's plan approval is the authorization for every step after it. Run steps 2–7
through to the **open PR** without stopping to report between phases — the merge in
step 7 is outside the mandate unless the instruction includes it; put the decisions that
genuinely change what gets built at the plan gate, batched, with a recommendation
first; report once when the PR is open. The rule, its boundary (before a plan
exists, a question wants an answer) and its exceptions are `karpathy.md` §8.

## Re-read origin before you open the PR, not just before you cut the branch

Verifying local is current with origin (`code-check-shell.md`, "Before you *cut* a
branch") protects the branch point. It
says nothing about the build window, which is where a parallel session lands: measured
once, a second session filed, built and merged the same feature in 18 minutes, entirely
inside the first session's planning phase, and merged 15 seconds before its first
commit. Both sessions' pre-flight checks passed and both were correct when they ran; the
duplicate surfaced hours later as a version-bump conflict across eight files.

Before opening a PR, and again before merging:

```bash
git fetch -q origin
git log --oneline HEAD..origin/main          # what landed while you worked
git diff origin/main -- DESCRIPTION NEWS.md  # a version you did not bump
```

**A version bump you did not make is the tell**, and usually the only one — the tree is
clean, the branch is healthy, and nothing in git hints that someone solved your problem
an hour ago.

On a collision, do not resolve conflicts file by file. The merge conflict hides the
useful question, which is *which body of work survives*. Ask, then re-land the delta on
top of what shipped; two independent attempts at one problem are usually complementary
rather than redundant, and a mechanical resolution keeps whichever half git preferred.

## An issue number you did not file yet is somebody else's

GitHub allocates one sequence across issues **and** PRs, on creation. So a number
written down before the issue exists — a branch name, a code comment, a config header,
a commit trailer — is a reservation nobody honours, and in an active repo it will
eventually name a real issue about something else entirely.

That is the expensive direction. A number pointing at *nothing* is obvious; a number
pointing at a **stranger's issue** resolves, renders as a link, and reads as provenance.
Nothing downstream checks that the issue it names has anything to do with the code
beside it.

Measured 2026-09-08 in rtj. Work with no issue was branched as `322-sern-thompson-2026`
on a guess, and four `rtj#322` citations went into a `project.yml` header and two
shared-library comments. A parallel session then filed #322 — about a STAC registration
script. Every citation was wrong, all four looked fine, and the real issue for the work
(#319) went uncited until the merge.

- **Cite an issue only after it exists.** If the work has no issue and does not warrant
  one, write no number: a comment that explains itself is better than a wrong pointer.
- **Before merging, resolve every issue number the branch introduces** and check the
  title is about this work — one call, and it is the only thing that separates a good
  citation from a plausible one:

  ```bash
  git diff --stat origin/main...HEAD >/dev/null   # three-dot: the branch's own changes
  git diff origin/main...HEAD | grep -oE '(^\+.*)(rtj|rfp|gq|soul|link)#[0-9]+' \
    | grep -oE '[a-z_]+#[0-9]+' | sort -u
  # then, per hit:
  gh issue view <N> --repo NewGraphEnvironment/<repo> --json title -q .title
  ```

- **Name the branch for the work when there is no issue** (`sern-thompson-2026`), and
  rename it once one exists — `git branch -m` before the first push costs nothing.

Sibling of the section above: both are parallel sessions moving underneath work that
looked settled when it started.

## The version lives in one place

Do not restate the current version in `README.md` or `CLAUDE.md` prose. A version
string typed into prose drifts from the moment it is written — the release step
maintains `DESCRIPTION` and `NEWS.md`, and one report repo's
`CLAUDE.md` was found eight minor versions behind, its `README.md` one behind, with both
canonical files correct. Link to `NEWS.md` instead. Where a claim genuinely must stay in
prose, `/gh-pr-merge` step 7 greps for the previous version string outside the two
canonical files and updates the prose restatements it finds, reporting each.

## When to Skip

For one-line typo fixes, version-bump-only PRs, or trivial documentation edits, the full workflow is overhead. Use judgment. The threshold is roughly: **multi-step issue, multi-file change, or anything that requires scoping** → use the workflow.

## Skills That Slot In

- `/planning-init <N>` — start
- `/planning-update` — sync checkboxes mid-session
- `/code-check` — before every commit
- `/planning-archive` — when issue closes
- `/gh-pr-push` — open the PR
- `/gh-pr-merge` — merge with release bookkeeping

## Issue bodies get edited, not appended

When work changes what an issue should say, **edit the body**. Don't add a
comment that corrects it, and retitle when the scope moves.

**Why:** an issue is read as a spec by whoever picks it up. A body saying one
thing with a comment three screens down saying the opposite costs the reader the
reconciliation, every time.

**How to apply:** `gh issue view N --json body -q .body` into a file, revise,
`gh issue edit N --body-file`. Name what changed and why when the correction is
load-bearing — the goal is a body that reads correctly top to bottom, not an
erasure of history. Comments are for genuine commentary: a merge notice, a
cross-repo pointer, a question. Applies to PR bodies too. Commit messages are
immutable history and are never rewritten this way.

**The failure mode that keeps recurring: research findings feel like
commentary.** They are not — they are the spec. If a finding changes what
someone would *build*, it belongs in the body, with the durable version in
`research/` and the body linking to it. What `research/` holds, how a file is
named and what its header carries is `planning.md`, "`research/` — what is
known, outliving the issue that found it".

**Bodies drift at the moment work finishes, not while it is in flight.** Four
instances in a single day of rfp work, all of the same shape — the code learned
something and the issue did not:

| drift | what a reader saw |
|---|---|
| premise disproved by measurement | an issue arguing for a fix that was no longer needed |
| a conclusion asserted in the body but never landed in code | body and tree contradicting each other |
| the shape of the work moved during exploration | a spec describing a design nobody built |
| a decision made and shipped, body still listing options A–D | "decision needed" on a decision a year old |

Vigilance does not catch this, because the drift happens exactly when attention
moves to the merge. `/gh-pr-merge` reconciles at that moment — see its step 3b.

## Why This Exists

We've hit snags repeatedly when half-doing this — branches that mix concerns, tests bolted on after, code-check skipped (and then a bug ships in the diff), examples that fail in pkgdown. Each step is small; the cumulative reliability gain is real. The convention is here so it becomes the default expectation, not a thing the user has to remind every session about.


# LLM Behavioral Guidelines

<!-- Source: https://github.com/forrestchang/andrej-karpathy-skills/main/CLAUDE.md -->
<!-- Last synced: 2026-02-06 -->
<!-- These principles are hardcoded locally. We do not curl at deploy time. -->
<!-- Periodically check the source for meaningful updates. -->

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

Some rules here fence their citations in a `<!-- evidence -->` block, which a repo's
`CLAUDE.md` omits and `/code-check` reads in full. A new citation goes inside that
rule's block, creating one at the end of the rule if it has none; the remedy stays in
the rule. `code-check.md`'s header states the rule once, and
`skills/compact-prep/SKILL.md` step 5 carries the habit.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. You Have No Clock Between Tool Calls

**Every duration claim comes from `date`, never from how much waiting felt like
it happened.**

Background `sleep` returns immediately from the agent's side, and the number of
times you have polled is not evidence of elapsed time. Two consecutive tool
calls can be 15 seconds apart by the clock while feeling like ten minutes of
waiting.

The failure is stating it out loud before checking. Observed 2026-08: a CI run
was reported to the user as "pending for over an hour — unusually long, probably
a stuck runner", after roughly eight background sleeps. One `date -u` showed the
run was **three minutes old** and entirely normal. The whole diagnosis — stuck
runner, duplicate triggers, something wrong with the workflow — rested on a
duration that had been invented.

**How to apply:** before saying *any* duration — "still running after N
minutes", "this has been X a while", "longer than usual" — run `date -u` and
subtract a real start time. `gh run list --json createdAt` gives it for CI. If a
claim about slowness would change what the user does next, it needs a measured
number or it does not get made.

The same rule covers process state. `ps` and task-status listings have both been
observed wrong; check the artifact (an output file's size, its mtime, the
service's own API) rather than the wrapper.

### The same blind spot picks the wrong waiting tool

Not having a clock also makes a **chain of background sleeps** feel like
waiting when it is not. Observed 2026-08 on the same session as the above:
roughly a dozen `sleep 570; check` background tasks were spawned to wait out a
55-minute test suite and then CI. Two consecutive foreground checks printed the
*same minute* — no wall time had passed between them, because the sleeps run
detached and the polling happened around them rather than after them. Every one
of those tasks was waste, and killing them produced a batch of eleven
exit-code-144 notifications that read like failures.

Pick the instrument by how many answers you need:

| you need | use |
|---|---|
| one notification when a condition becomes true | `Bash(run_in_background)` with an `until` loop that exits |
| one per state change, ending on its own | `Monitor` with a command that emits and then exits |
| a value you must have before the next step | a **foreground** call, so the blocking is explicit |
| a long job that notifies when it exits | `Bash(run_in_background)` with the command as plain foreground text: no `&`, no `nohup` |

A repeated `sleep N; grep` is right in none of them. **Tell: if you are about to
spawn a second waiter for the same thing, the first one was the wrong shape.**

A `Monitor` filter must also match the failure states, not just the success
one — silence looks identical to "still running", so a watcher that greps only
for the happy path stays quiet through a crash.

**Never end a backgrounded call's command with a trailing `&`.** A trailing `&` (or
`nohup … &`) with nothing in the same command waiting on it, sent with `run_in_background`,
lets the wrapper exit at once, so the notification reports **exit 0** whatever the job
then does: once it killed the job, and in another session the job ran to completion. Either
way the notification says nothing about the job. Pick one mechanism from the table, never
two. A `&` whose job the same command goes on to wait for, as in `with_deadline()`
(`code-check-shell.md`), is not this, and nor is the `nohup … &` fix in that file's
"`&` binds to the whole `&&` list" rule when the call itself is not backgrounded.

*5 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Don't edit files a long-running suite is still reading

`devtools::test()` and its equivalents load each test file **when they reach it**,
not at launch. A 30-minute run therefore reads whatever is on disk at that moment,
so edits made mid-run are half-applied and the result describes a tree that never
existed.

Cost two full Docker suites (~1 hour) on rfp#178, both reporting `FAIL 1`. The
failure was a test written *during* the run, executing against source from *before*
the fix that made it pass — nearly reported as a regression. **The tell is a moving
denominator:** 3490 passes, then 3496, then 3500, on "the same" tree.

Before a long run, commit. While it runs, do work that touches nothing it reads —
issue bodies, PR text, reading, planning. If an edit cannot wait, kill the run
rather than let it produce a result that has to be re-litigated. And when a long run
fails, get the `file:line` before forming any theory: a mid-flight edit and a real
regression look identical in a summary line.

**It is not only test runners.** `Rscript file.R` parses incrementally too, so editing
any long-running script mid-run resumes the parser at a byte offset into shifted
content. The tell is different and worse: a **syntax error quoting a line that does not
exist**, which reads as a defect in code that is fine. The moving-denominator tell above
needs two runs to see; this one arrives looking like an answer.

*6 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

## 6. Subagents Are Evidence, Not Dependencies

**Spawn on your own judgment. Don't block on one. Don't trust its status. Verify its claims in both directions.**

### Spawning is your call, not the user's

Deciding to spawn a subagent is an engineering judgment, the same kind as choosing
to write a test or run a grep. **Do not ask permission for it.**

The user is usually not positioned to answer. Knowing whether a fan-out beats a
sequential read requires knowing the shape of the work — which you have and they do
not, so the question forces them to guess at a technical call. Under **Always Away**
it is worse than useless: the work stalls until they wake up, for an answer that was
yours to make. *"I wouldn't be in the know enough to know when that is"*
(airvine, 2026-08-27) is the whole problem in one line.

This does not soften §1's asks — *"if uncertain, ask"* and *"if something is unclear,
stop and ask"*. Those are about **what the user wants**: intent, scope, an ambiguous
requirement, a tradeoff only they can weigh. This is about **how you carry it out**.
Ask about intent; decide about mechanism. A question starting "should I use…" is
almost always the second kind, and almost always yours to answer.

#### Standing authorization: the harness bars the Agent tool by default on Opus 5

Sessions on Opus 5 carry a hardcoded instruction from the CLI itself —
*"Do not call the AgentTool unless the user requested it"* — alongside the same
line for workflows and deep-research. It is not a setting anyone here
misconfigured, and **it cannot be turned off locally**: the string is a literal in the
CLI bundle, gated by remote config. Nothing in `~/.claude/settings.json` reaches it, so
do not spend a turn looking there.

The symptom is a skill quietly doing less than it says: `/code-check` reporting
*"the subagent rounds did not run — your session instruction bars the Agent
tool"*, which is the review the command exists to perform. It reads as a
configuration problem, so the fix gets looked for in the wrong place.

**The clause is conditional, so this convention is the request.** Invoking a
skill that mandates subagents — `/code-check`'s three rounds, the Plan review in
`planning.md` — **is** the user requesting them. Spawn them. This paragraph is a
standing user instruction, written for exactly that purpose (airvine,
2026-08-29), and CLAUDE.md project instructions override default behaviour by
their own terms.

It authorizes the mandated spawns and nothing wider: the bounds in this section
still hold — two or three concurrent, about five per task, no fan-out from a
child — and a workflow or deep-research run fanning out dozens of agents remains
a spending decision that needs an explicit ask.

**Spawn without asking when:**

- A skill or convention mandates it — `/code-check`'s review rounds, the Plan review
  in `planning.md`. That decision is already made; re-asking it is friction carrying
  no information.
- You want fresh eyes on your own work. The mechanism and the measurements behind it
  are in `code-check/SKILL.md`.
- A sweep over many files will **locate** what matters faster than reading serially.
  The sweep finds candidates; it does not replace the read — `planning.md` is
  explicit that agents sometimes report existing files as absent, so read directly
  whatever you are going to act on.
- Independent items can run concurrently and nothing downstream needs them ordered.

**Do it yourself when:**

- One grep answers it.
- The work depends on conversation context a subagent will not have.
- You would sit idle waiting — spawn and keep working, or do it inline.

**Bounds and defaults you enforce yourself, rather than converting into questions:**

- **Two or three concurrent is the working default, and about five per task** is
  where spend stops being incidental. Concurrency and cumulative total are different
  quantities — `/code-check`'s three rounds plus a Plan review plus an ad-hoc sweep
  never exceeds three at once while spending well past a handful. Bound both.
- Past that total, **say so in your next message.** An escape you grant yourself
  silently is not a bound; it has to land in front of the user, after the fact.
- **Do not let a subagent fan out again.** Intent does not enforce this — the child
  decides what it calls — so use the structure: the `Explore` and `Plan` types are
  defined without the `Agent` tool and *cannot* spawn. `general-purpose` can, so when
  you use it (as `/code-check` does), put "do not spawn subagents" in the prompt. The
  one case on record (see "Don't block" below) never had a root cause established, which
  is exactly why this bound is structural rather than advisory.
- Unnamed, delivering by file — `planning.md` carries the mechanics.
- **Report after, not before.** Say what you spawned, and relay what it found (per
  `code-check/SKILL.md` — a subagent's report never reaches the user on its own). A
  user can object to a spawn that already happened; they cannot usefully approve one
  that has not.

**What is genuinely the user's call is budget, not mechanism.** A workflow or
deep-research run fanning out dozens of agents is a spending decision and needs an
explicit ask. Two or three reviewers is not — that is just doing the work.

The cost of a review is the visible half and the benefit is not. Two reviewers over one
conventions draft returned **20 findings** and caught **six** false factual claims in it.
None of that happens if the spawn waits on a user who is away.

*9 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Don't block

Spawn a background subagent, then keep working on the lowest-risk part of the
task — scaffolding, data files, tests. When findings arrive, treat them as a
review of landed work rather than a precondition for starting it.

If a result genuinely must precede the next step, run it synchronously
(`run_in_background: false`) so the blocking is explicit and visible.

Three observed cases where waiting would have been the expensive choice:

- A research agent spawned 5 children and deadlocked for **~3 hours**, still
  reporting as "running". The user caught it, not the agent.
- A `Plan` agent asked to review a `task_plan.md` *before the baseline commit*
  returned after the issue was implemented, reviewed, merged and tagged.
- The same pattern on a later issue: findings arrived after all four phases had
  shipped. Because the work had not waited, this cost nothing — three findings
  were still new and landed as follow-up commits.

That last one is the shape to aim for. Concurrent review is not a degraded
version of blocking review; it is often better, because the reviewer reads real
code instead of a plan.

### Don't trust status

**Never report an agent as "still running" without evidence.** Agent status and
`TaskList` have both been observed to be wrong — `TaskList` reported "No tasks
found" for an agent that was alive and later replied. Check the output file's
mtime before claiming progress, and say what you checked.

**And never record a review as "Clean" on the strength of an idle notification.**
From the parent's side an idle ping is indistinguishable from an agent that had
nothing to say, so a lost review reads as a pass — a whole `/code-check` pass was once
reported as finding nothing while three reviews were stranded, one of which had found
a data-loss bug (measured 2026-08-25; the numbers are in `planning.md`, "Spawn review
agents UNNAMED"). Passing `name` turns a spawn into a persistent teammate that idles
instead of completing; pass it only for a collaborator you will keep messaging, and
shut it down when done. The rule that survives either spawn shape:
the reviewer **writes its findings to a file and reports only the path**, and a
missing or empty file means the round produced nothing and is re-run — never
"Clean". `planning.md` carries the mechanics; `code-check/SKILL.md` applies them.

### Verify claims, in both directions

Subagent output is evidence, not verdict. Both failure modes are real:

- **Acting on a wrong finding.** One labelled BLOCKER — "`glue()` will choke on
  the literal braces in this fragment" — was disproved by a 30-second probe,
  because glue does not re-parse interpolated values. Acting on it would have
  meant rewriting a working generator.
- **Dismissing a late review wholesale.** In that same review 2 of 9 findings
  were real, including a dead link. In a later one, a finding that a
  `path|layername=` check would delete KML/GPX layers was correct, and was
  confirmed against 207 real datasources before the fix landed.

The rule that separates them: **cheap probe first, then act.** Reproduce the
claim before you fix it, and before you dismiss it. A finding you cannot
reproduce is a finding you do not yet understand.

### Fan out inside one process

A workflow that shells out **once per item** costs one permission prompt per item,
unless the command happens to be allowlisted. The same work done **inside one
process** costs one prompt total, and nothing says so until the run is already
going. Measured 2026-09-04 (knowledge#4): a harvest script issuing two `curl` calls
per report inside each subagent meant hundreds of approvals across a run — the user
had flagged it as *"a big time suck last time"* without knowing the cause — while a
sibling script doing the same fetch-download-upload work with Python `urllib` in a
single process cost **one** prompt for the entire run. Same task, same volume, three
orders of magnitude apart in interruptions.

It breaks **Always Away** directly: an unattended run that stops for approval on item
3 of 200 has not failed loudly, it has gone idle, and the wrapper reports nothing.

- **Prefer one process doing N items over N processes doing one.** Loop inside the
  language runtime; shell out once, for the batch.
- Where a per-item subprocess is genuinely required, allowlist its command **before**
  the run, not one refusal at a time during it — the allowlist fixes the commands you
  predicted, and the one that blocks is the one you did not.
- Diagnostic: if a run keeps stopping for approval, look at whether the loop sits
  inside or outside the process boundary before adding allowlist entries.

---

## 7. Evidence, Not Impressions

**Measure before you characterise. Presence is not provenance. "Unknowable" is a
claim.**

Six principles that all fail the same way: something *feels* established — because
it is visible, because it is present, because someone said so — and gets offered
with the confidence of a measurement.

### Measure before you characterise

When a decision turns on **what something contains**, open it and count. Do not
describe it from its structure, from an issue's claim about it, or from a tag list.
A heading tells you a thing is *present*, never that it is *populated* — an empty
`<conditionalstyles/>` and one with rules look identical in a list of child names.

Four instances in one rfp session, each corrected by the user's follow-up question
rather than by review: a tradeoff described as three times its real size; an issue's
stale claim repeated as current; an installed version reported as sixteen releases
behind when a parallel session had updated it eighteen minutes earlier; and "nothing
on main addresses this" from a local `main` three commits behind — one `git fetch`
away from the truth.

**A measurement carries the time it was taken.** One made earlier in the same
session is not a current one, least of all for anything another session can change
underneath it. For anything git-backed, `git fetch` first: reading a local clone and
reporting it as the state of the world is the same error with a longer fuse.

**And before hand-rolling a parser for a probe, check whether the code already has
one.** A bespoke parser silently narrows the population it can see, and the result
looks like a measurement rather than a sample — worse than not measuring, because it
carries a number. Measured 10 of 80 with a hand-written matcher; routed through the
package's own resolver it was 14 of 117.

### Presence is not provenance

When something's **presence** is offered as evidence for **how it got there**, find
the fact that actually discriminates. A QGIS project's `3.30.1` stamp was offered as
evidence a desktop had opened it — but the template it was copied from carries that
stamp, so a never-opened project reads the same. What actually proved it was a
tracking key the template does not contain.

The tell: reaching for the *most visible* fact rather than the *discriminating* one,
because the visible fact is consistent with the conclusion. **Consistency is not
support.** Before offering "X shows Y", ask what else would produce X. If anything
would, X is not evidence.

When the user pushes back on an inference, re-derive rather than defend. The
conclusion often survives; the reasoning that reaches it is usually different.

*5 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Documents that share an ancestor corroborate nothing

Sibling of the rule above, one level out: there a *fact* was consistent with the
conclusion, here several *documents* are. Finding the same claim in three places
feels like triangulation and is not — if one was written from another, they are one
source wearing three hats, and the agreement is a copy, not a confirmation.

**The tell is agreement with no independent derivation.** Ask of each restatement:
what did its author read? If the answer is "one of the others", the count is one.
Prose repeats; code does not, so the discriminating check is almost always to read
the thing the prose describes.

**The release note is where this costs the most, because its readers cannot check it.**
Where a release note is written from the issue rather than from the artifact, its numbers
have been copied rather than derived, and no reader is positioned to notice.

Five habits:

- **Derive every number in a release note from the artifact it describes**, at the moment you
  write it. Not from the issue, not from the last release's notes, not from memory.
- **For any sentence of the form "you can tell X by looking at Y", check that Y actually
  separates X from not-X.** A discriminator that fires on everything discriminates nothing,
  and it reads as helpful right up until someone relies on it. A checksum over a re-encoded
  artifact is the standing example: it answers "are my bytes current" and can never answer
  "did the values change".
- **A carve-out is a number too, and reasoning one from the shape of a literal understates
  it.** Run the check over the population before writing the exception. A literal naming two
  excluded items does not mean every other input is covered: it names *two*, so a one-item
  tree is always missing at least one of them — including each of those two, which are
  missing each other — and the coverage is **zero for every one-item tree**, not merely
  capable of being zero. That error runs in the direction that understates the reach of a
  defect, in the document a reader uses to decide whether to backport.
- **When a document states a quantity or a scope, read the code that produces it
  before repeating it.** Especially a status section — it describes a moment, and
  nothing fails when the moment passes.
- **When you find one instance stale, grep for the sentence, not the file.** A claim that
  sits in three documents is not fixed by repairing the one that was quoted; the other two
  still read as authoritative.

*31 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### "It can only be answered by testing" is a claim with an author

An issue or a colleague saying a question needs a field season, a device or a deploy
is stating a claim, not a property of the problem. Spend the cheap probe first.

rfp#186 opened with "three questions decide whether this is viable, and none can be
answered by reading." Two fell in about twenty minutes — one to reading a call
graph, one to re-reading a file already on disk — turning "run a field season, then
decide what to build" into "build it, then confirm one thing."

The claim is usually made by someone who knows the domain, at a moment before they
looked. Not wrong so much as **unexamined**, which is what lets it survive into the
plan. Then **bound what the probe closed**: reading a desktop plugin says nothing
about the mobile app. An over-claimed probe is worse than none.

### A real bug is not necessarily the reported bug

A defect found while investigating a symptom is **evidence, not the answer**. Before
offering it as the cause, check that it produces *exactly* the symptom described,
including the details that sound incidental.

Two confident wrong causes in a row on rfp#196 — a layer missing from a map theme
(a real bug, fixed) and a sub-pixel geometry (a real measurement). Both true;
neither explained the report. The actual cause was draw order, and the user named it
himself. The discriminating fact was in his words all along: *"as soon as I stop
tracking I can't see the track"* rules out both theories in one line.

Finding a genuine defect feels like finding *the* defect — the relief of having an
explanation is what stops the check. Write the reported symptom out and ask whether
the proposed cause produces **all** of it. Say which parts are still unexplained:
"this is a real bug and it may not be your bug" is honest and cheap.

### An enumeration is not a checklist

A probe listing what exists — subkeys present, columns found, files listed — answers
"what is here", never "what do we want". Scope arriving this way looks
evidence-backed, so it survives review.

On rfp#68, "the two Mergin subkeys that exist" became "the settings to verify",
then an item on a field checklist a human had to walk outdoors to complete. Nothing
in the codebase read or wrote `PhotoNaming`. Before a probe's output becomes work,
grep for each item and ask whether anything consumes it. When it duplicates
something already done another way, name the comparison — the existing approach
usually wins for a reason worth stating.


### A relative descriptor is meaningless without its anchor

"Upstream", "downstream", "above", "below", "before", "after", "parent" — each is
relative to something named **elsewhere in the document**, often paragraphs away and
sometimes only in a table. Resolve the anchor before drawing any inference from the
term.

Getting it wrong does not produce uncertainty, it produces a confident and specific
wrong answer — and it fails in the worst direction, because you now believe you have
*evidence* against a claim rather than merely lacking evidence for it.

Measured 2026-09-02. A field report read *"downstream sampling confirmed the presence
of coho"*. Taken as downstream of the crossing under discussion, it appeared to
disprove the user's recollection that coho were present above that crossing. The
sampling site was actually at a road crossing 1.5 km further up the stream, so its
"downstream" was still **1.1 km above** the crossing in question — the claim was true
and the correction nearly removed it from an email to the infrastructure owner, on the
one point the email existed to make.

**Where a source describes a sequence — crossings on a stream, releases in a
changelog, stages in a pipeline, commits on a branch — write the order out before
interpreting a single relative term in it.** The ordering is usually one sentence in
the source and takes seconds to find; the inference built on the wrong anchor survives
every later check, because nothing downstream re-examines it.


### A safeguard whose mechanism is a human reading a diff is not a control

When a design says "the writes are uncommitted, so the diff is the review", check
whether anyone reads diffs. Here nobody does — the user says "commit" without opening
one, stated plainly and confirmed 2026-08-28 — so every per-action confirmation loop
built on that premise was latency wearing the costume of a control. Two skills had one.

Gate on **blast radius** instead, because that fires without anyone reading anything: a
write that reaches one repo just happens; a write that reaches every repo (a soul
convention) may be appended to freely but edited or removed only through an issue. Where
a real check is needed, make it mechanical — a grep for a contradicting rule, an
assertion that nothing above the `CLAUDE.md` marker moved, a guard that resolves every
heading against a base SHA. Those are the controls; a prompt is not.

The user still wants a short, honest account of what was written. That is a report, not a
review, and confusing the two is how the loops got built.

### Not finding it is not evidence it does not exist

Before building a fetcher, harvester, backup or sourcing routine, **search the sibling
packages for the verb**. One command, and it is the difference between adding a function
and adding a second copy of one.

```bash
# Enumerate the org's installed packages rather than listing them: a hardcoded list
# named four packages; thirteen other org packages were installed on the machine this
# was measured on (2026-09-05), and the gap will grow again. Match
# on any URL-ish field, case-insensitively: RemoteUsername is set only by GitHub
# installs (a package installed from a local checkout has none) and the org name is
# not always cased the same. Forks of upstream packages come along; that is fine.
# `collapse` matters: paste() over fields that are all NULL is character(0), and
# `if` on a zero-length grepl() aborts the whole enumeration (measured, soul#171).
for p in $(Rscript -e 'for (p in rownames(installed.packages())) {
  d <- packageDescription(p)
  u <- paste(c(d$URL, d$BugReports, d$RemoteUrl, d$RemoteUsername), collapse = " ")
  if (grepl("newgraphenvironment", u, ignore.case = TRUE)) cat(p, "\n") }'); do
  echo "== $p"; grep -E "^export" "$(Rscript -e "cat(system.file(package='$p'))")/NAMESPACE" \
    | grep -iE "source|fetch|harvest|backup|manifest|download|ingest|store|snapshot|read|write|conform"
done
ls ~/Projects/repo/rtj/scripts/gis/     # operational drivers live here, not in a package
```

**Then read the README ownership table and the above-marker `CLAUDE.md` of any package
plausibly adjacent — exports understate remit.** A package README can state a remit no
export names: that it exists so a report does not have to harvest its own copy, that it
pins per-snapshot sources, schema, md5 and row count. The grep finds functions; the README
is the load-bearing artifact, and it is the one nothing prompts you to open.

The failure is not carelessness — it is that **a decision is invisible from where the work
is happening**. The tool exists, is correct, and is three repos away in a directory you had
no reason to open. So the path of least resistance builds it again, and the duplicate is
plausible precisely because the original was never visible.

**Tell:** you are about to write something whose name is a verb the ecosystem already does
somewhere. Fetch, sync, harvest, backup, source, register, publish.

Two corollaries worth holding:

- **A function existing in two places is worse than it existing in neither.** Two live
  copies drift silently, and the drift is invisible until someone has both installed.
- **Check what the *architecture* says, not just what exists.** Not every instance is
  duplicate code; a wrong-home *proposal* is the same failure, and an issue that already
  assigned the boundary settles it for less than arguing from first principles costs.

Sibling of *"An inventory is only complete relative to a boundary"* in `code-check.md`, one
step earlier: that one is about a search that was complete for the wrong scope, this is
about never having searched the scope where the answer lived.

*25 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

#### The storage version: one store is not the world

The same error with buckets instead of packages. The shape is a single negative check
reported as a fact.

The most general case: **`aws s3` and `s3cmd` address different clouds and are invisible to
each other.** A repo whose backup script uses `s3cmd` has stores that no `aws s3 ls` will
ever list, so "I checked S3" is not a statement about where the data is.

Two habits, each one command:

- **Enumerate the stores before searching them.** `s3cmd ls` and `aws s3 ls` with no
  argument each list only their own provider's buckets; the backup script names the rest.
- **Prefer the definition to the artifact.** The job that stages data says what exists; a
  bucket only shows what some past run happened to leave.

A negative result is only ever as wide as the store you looked in. Stating it without that
qualifier is how a gap in your own search becomes a fact in an issue body.

And the same shape once more for **checkouts**: a `grep` across `~/Projects/repo` searches
the repos this machine happens to have, not the ecosystem. Repos are cloned per-machine and
the set differs between them, so a local grep that returns clean has answered a question
about this disk. Use `gh api -X GET search/code -f q="org:NewGraphEnvironment <term>"`,
and note it indexes **default branches only**, so a file on a feature branch is invisible to it
and needs `gh api repos/<owner>/<repo>/contents/<path>?ref=<branch>`.

*12 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

## 8. Decisions Up Front, Then Run

**Ask at the plan gate. After approval, run to the PR. Before a plan exists, a question wants an answer.**

The first three subsections are one rule on one axis — *when* to come back to the
user — and they are only correct as a set; each was learned separately in a different
repo and re-derived, usually by getting one of them wrong first. The rest are
handover rules that belong beside them because they decide what the user is handed
when you do come back.

### After plan approval, run every phase to the PR

Plan approval is the authorization for every mechanical step after it. Run every
phase, commit atomically per phase, archive the PWF, push, open the PR, and report
**once**, at the end. Do not stop between phases to report progress: the decisions
that needed the user were taken at the gate, and a check-in that only reports
spends attention already committed. Under **Always Away** the cautious answer is the
wrong one — the work stalls on a question the user answered by approving the plan.

The instruction arrives as one short message covering many commits, reviews and
repos: *"Go all phases to PR"* (airvine). **The merge is a separate instruction** — *to the PR*
ends at the open PR, and `/gh-pr-merge` runs when the user invokes it or the
instruction says so.

Two things are inside the mandate; these are not:

- **Correcting the plan is inside it.** A review that disproves an approved design
  decision gets fixed mid-run and reported in the summary; that is the run working,
  not a reason to stop — unless the correction is itself a fork of the kind below (a
  key, an identifier, a schema), which goes back to the user. Blockers that cannot be resolved are filed as issues and
  named in the final report rather than held open.
- **Our own repos are inside it.** Filing issues, opening PRs and editing bodies in
  NGE repos is normal work.
- **Outward-facing actions are not** — see "Never post outside our own repos" below.
  Neither is anything a convention names as its own gate: the merge (airvine, 2026-09-05;
  `gh-pr-push/SKILL.md`, "Ask user before merging"), a change to the machine
  (`newgraph.md`, "State the plan before changing the machine"), or a push into an
  artifact a human is testing on (`code-check.md`). A push to the feature branch is
  inside the mandate.

*7 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Before a plan exists, a question wants an answer

The same terseness that means "go" after approval means "answer me" before it. A
turn that ends in a question mark, with no approved plan, gets an answer and a
one-line offer of the work — not the first commit toward it. Twice in one day
(floodplains, 2026-09-02) a question was read as approval and editing started — once
after *"why not fix before publish?"*, and once after a gap had been explained, stopped
with *"do not take on 70. i want to understand"*. When the ask is to understand something, keep it short and concrete; a
worked example beats a taxonomy. *"small answers here"*, *"keep it short"* (airvine).

This is the boundary condition on the rule above, which is why they are one section:
a standing mandate to run autonomously, stated alone, is exactly what reads every
terse message as "go". **The mandate starts at plan approval.**

### What still interrupts, and where it goes

A decision that permanently shapes stored data — a key, an identifier, a schema
choice, a deprecation shim versus a hard rename — is the user's, and it goes to the
**plan gate**, batched, as two or three concrete options with the recommended one
first and the consequence stated. Two such forks put at one gate (flooded#47) were
both load-bearing and neither was derivable from the issue: the rename would also
have broken a production driver in another repo, which only the sweep surfaced.
Asked at the gate a fork costs one round-trip and buys the whole run; discovered
mid-execution it costs a stall with nobody there to answer it. Found mid-run, it is
still not the agent's to decide: ask it the same way — options, recommendation first,
phone-answerable — commit, and continue on the phases that do not depend on it while
the answer is outstanding (`planning.md`, "When Something Keeps Failing" — escalating
is not stopping).

During plan-mode exploration, keep a list of "this changes what I build" forks and
ask them together before `ExitPlanMode`. Questions are welcome; status updates are
not. Mechanism — whether to spawn reviewers, which regex, how to build a fixture — is
never a question (§6, "Spawning is your call"), and anything with a conventional
default is not one either: pick it, say so, move on.

### Never post outside our own repos without approval

Never post to a venue outside NGE's own repositories without the user's explicit
approval for that specific post — upstream GitHub issues and PR comments, mailing
lists, forums, third-party trackers. **Drafting is welcome and expected**: write the
comment, show it, wait. It is the sending that needs the word. *"Never post things
upstream without my explicit approval"* (airvine, 2026-09-02, after an offer to draft
comments on two of a vendor's upstream issues).

**Why:** an upstream comment is published under the organisation's name to a venue we
do not control, is indexed immediately, and cannot be unpublished. It is a
communications act, not an engineering one, and the judgement about tone, timing and
what we are willing to say in public is the user's.

- Our own repos are unaffected; filing and editing issues there is the standing
  disposition and needs no asking.
- **Reading upstream is unrestricted and worth doing.** Checking issue state before
  filing ours has caught a wrong citation in our own roxygen and found an upstream
  issue already proposing the feature we were about to request.
- Offer the draft in the reply, not as a fait accompli, and say plainly that nothing
  has been posted when the work obviously produced something postable.

### Hand the user bare commands

When the user must run a command themselves — an interactive login, a
sudo-needs-TTY operation, anything the Bash tool is blocked from running — give the
**bare command**, in a fenced block, ready to paste. Never prefix it with `!`.
*"Give me the cmd without the ! - that never works btw"* (airvine, 2026-08-21);
*"stop giving me the ! at the start. that doesn't work. i need the raw cmd"* (`cd`, 2026-08).

**Why, twice over.** Default session guidance proposes the `!` prefix as a way to run
a command in-session, so this recurs in every repo unless written down. On this
operator's terminals it either does not run at all, or — where it does — **it ran from
`$HOME` rather than the session's working directory** (one measurement, 2026-09-02), so a
handed-over relative path created the file somewhere nobody was looking. Absolute paths are right whichever
directory it resolves against. So:

- Emit the command plain. Applies to fenced blocks and inline commands alike.
- **Absolute paths** in any handed-over command that touches files
  (`~/Projects/repo/<repo>/…`), whichever form the user ends up running it in.
- Keep it paste-safe: prefer `grep`/`awk` over a nested `python3 -c "…"` inside a
  single-quoted remote command, so the quoting survives the trip.

**A file under `~/Downloads` is unreadable by the agent process, and no retry helps.**
`Read`, `cp` and `pdftotext` on `~/Downloads/*` all fail with `Operation not permitted`.
It is macOS folder protection (TCC) on the process, not a Claude Code permission mode, so
`/permissions` does not change it; Desktop and Documents behave the same. Do not retry
variants — ask for **one** copy into the repo, with absolute source and destination paths,
then continue from the copy. (Granting the terminal app Full Disk Access removes it on one
machine; the fallback stays for the next machine.)

*4 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Link every issue and PR you name to the user

When a message to the user names an issue or a PR, make the number a link the user can
click: `[soul#191](https://github.com/NewGraphEnvironment/soul/issues/191)`,
`[soul PR #192](https://github.com/NewGraphEnvironment/soul/pull/192)`. Terminal output
renders markdown, so a bare `#191` costs the user a browser, a repo, and a click through
several pages to learn what it was — for every number in a report that may carry a
dozen. *"want to be able to follow up without opening new browser and clicking through
mult pages to find"* (airvine, 2026-09-05).

- **Issues under `/issues/N`, pull requests under `/pull/N`.** They are different paths,
  and the type is not always obvious from a number. When unsure, ask `gh` rather than
  guess — it returns the canonical URL for either:
  ```bash
  gh issue view 192 --repo NewGraphEnvironment/soul --json url -q .url \
    || gh pr view 192 --repo NewGraphEnvironment/soul --json url -q .url
  ```
- **Cross-repo references carry the repo**: `rfp#268`, never a bare `#268` from inside
  soul.
- **A bare `#N` is not ambiguous — it is a working link to the wrong repo.** The host
  resolves it against the session's own repo, so a bare number in a discussion *about* a
  different repo silently retargets, and the wrong repo's issue of that number can be close
  enough in subject to read as correct. Naming the collision in prose afterwards does not
  fix it; the link has to be re-qualified.
- **Spot-check a subset, not every link.** Before sending a report with many numbers,
  resolve two or three through `gh` — the ones you typed from memory or whose type you
  inferred — and let the rest ride. Checking all of them would slow every message; checking
  none is how a wrong repo or an issue-path link to a PR ships.
- **Scope is messages to the user** — terminal replies, the compact-prep report, PR and
  issue bodies where a reader lands from outside the repo. Commit messages and issue bodies
  read *on* GitHub autolink `#N` already; do not bloat those.

*5 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Surface upstream defects; do not work around them

When a dependency or an external API misbehaves, surface it and ask rather than
coding around it. *"dont' do workarounds for things like zotero api problems. surface
and ask as there may be simple solution"* (airvine, 2026-09-03).

**Why:** a workaround hides the defect from whoever could fix it properly, and the user
often has upstream context or a simple fix the session lacks. Most of the dependencies
in question are **first-party** — an upstream bug is usually ours — so a local patch
is strictly worse than an issue: it leaves the bug in place for every other consumer
while making this repo look fine. Same instinct as `newgraph.md`'s "install missing
packages, don't workaround", applied to a *broken* dependency rather than a *missing*
one.

**How to apply:** reproduce it minimally, file an issue in the owning repo with the
repro and the exact lines, report it, and carry on if it is not blocking. The rule is
*do not hide it*, not *do not continue*: the day it was recorded, a search function
failed on a list column and broke a documented pipeline step; the local guard would
have taken minutes and hidden a bug affecting every consumer, so it was filed with a
three-line repro and the pipeline continued, since its data path did not use search.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.


# pkgdown Publishing

What a pkgdown deploy puts on the public internet, and the two ways that has
already gone wrong.

## A pkgdown site publishes every root-level markdown file

`pkgdown:::package_mds()` renders **every** `.md` in the package root except a
hardcoded allowlist — `README`, `LICENSE`, `NEWS`, and two GitHub templates.
There is **no config option to exclude a file**.

So `CLAUDE.md` gets published. So would `INTERNAL.md`, `NOTES.md`, or a PWF
`task_plan.md` left at the root.

**Repo visibility does not protect you.** GitHub Pages serves publicly
regardless of whether the repo is private, and there is no private Pages mode
below Enterprise Cloud. A private repo with a pkgdown deploy has public docs.

Measured 2026-08-23: `CLAUDE.html` was live on six NGE sites. On `rfp` and `gq` —
both private repos, so their `CLAUDE.md` legitimately carried the internal-only
conventions — that put the SR&ED section on the public web: claim structure,
field code, fiscal year, and the consultant by name.

The visibility filter was working correctly the whole time. It rests on an
assumption pkgdown breaks: that a private repo's `CLAUDE.md` stays private.

### Remove it before the build, not after

There are three copies, not one:

| file | what it is |
|---|---|
| `CLAUDE.html` | the rendered page |
| `CLAUDE.md` | a **verbatim copy of the source**, served as-is |
| `search.json` | the full-text index, containing the text |

Deleting `docs/CLAUDE.html` after the build leaves the other two. It looks like a
fix and achieves nothing. Remove the file from the CI checkout **before**
`build_site()` runs:

```yaml
- name: Keep internal notes out of the published site
  run: rm -f CLAUDE.md
```

### Gate on a declared allowlist

Each repo states which extra root pages it *intends* to publish. Anything else
fails the build, so a new root markdown file cannot leak silently:

```yaml
- name: Fail if an unexpected page reached the site
  run: |
    allowed="404 authors index LICENSE LICENSE-text"   # + declared extras
    ...
```

Add to `allowed` only after deciding the page should be public. `link` publishes
`NOTICE` and `RUNBOOK` deliberately — it is a public repo and both are genuine
documentation. That is the decision the allowlist is meant to record.

Test the gate against **both** known answers before shipping it: it must exit
non-zero on a site that does contain the file, and zero on one that does not. A
guard that only ever returns one value is indistinguishable from a broken one.

## Deploy with `clean: true`

`JamesIves/github-pages-deploy-action` defaults matter here. With
`clean: false`, the action **never deletes** — every file ever deployed stays on
`gh-pages` forever, whether or not the source still produces it.

Two consequences, both observed:

- Removing a file from the repo does **not** unpublish it. Measured on `gq`:
  `task_plan.html`, `progress.html` and `findings.html` were still returning 200
  long after the PWF documents had been moved out of the root.
- A leak cannot be fixed by fixing the build. The stale copies need a separate
  explicit purge, which is a step people forget.

`clean: true` makes the deployed site equal to what the build produced, so
removing a file from source removes it from the web on the next deploy. That is
the property you want, and it makes the site auditable.

### Check before flipping it

`clean: true` deletes anything on `gh-pages` not present in `docs/`. Confirm
none of these exist first:

- **`CNAME`** — a custom domain file would be deleted and the domain would break.
  (NGE repos have none; the domain comes from the org site repo, and project
  sites inherit it as subpaths.)
- **`dev/`** — versioned docs from `development: mode: devel`, if the deploying
  build is not the dev one.
- **hand-added assets** not produced by the build. Favicons and web manifests
  under `pkgdown/favicon/` *are* produced by the build and are safe.

Use `clean-exclude` for anything that must survive.

```bash
gh api "repos/OWNER/REPO/contents?ref=gh-pages" --jq '.[] | "\(.type) \(.name)"'
```

## Removing something already published

1. **Stop generating it** — the pre-build removal above.
2. **Remove the deployed copy** — automatic once `clean: true` is in; otherwise
   an explicit purge.
3. **De-index** — a Search Console removal request per property, *after* the URL
   404s.

Do **not** add a `robots.txt` block first. Blocking crawl prevents crawlers from
seeing the 404, which keeps stale search entries alive longer than doing
nothing.

`gh-pages` history is not a problem the way normal git history is: on a private
repo the branch is not publicly browsable, and only the currently-served content
is public. Deleting the file genuinely ends the exposure — no history rewriting.

## pkgdown drops a footnote's body and keeps its marker

A pandoc footnote — `text[^k]` with a `[^k]: …` block — renders in an article as a
**superscript marker with no footnote section under it**. The marker is emitted
(`class="footnote-ref"`), the content is not, and nothing warns.

So the failure is silent and lands on exactly the material a footnote is for: the caveat, the
definition, the reconciliation. Measured 2026-09-06 in drift#66, where a footnote carrying the
reconciliation of two circulating hectare totals — the sentence that stops a reader treating them
as a disagreement — was absent from the published page while `rmarkdown::render()` of the same
source showed it fine.

- **Do not write footnotes in a pkgdown article.** Promote the content to a block quote, a
  parenthetical, or its own short paragraph. If it is worth a footnote it is usually worth being
  visible.
- **Check the rendered HTML, not the source.** The tell is a marker with nothing to jump to:

  ```bash
  grep -c 'footnote-ref' docs/articles/<name>.html     # markers emitted
  grep -c 'class="footnotes' docs/articles/<name>.html # section emitted — expect these to agree
  ```

Same family as the cross-reference gotcha already noted for vignettes (`\@ref(fig:…)` compiling
to a literal): bookdown output formats do not carry all of bookdown's machinery through pkgdown,
and each missing piece fails quietly in its own way. Verify anything structural — footnotes,
cross-references, numbered captions — against the built page the first time you use it.


# Planning Conventions

How Claude manages structured planning for complex tasks using planning-with-files (PWF).

## When to Plan

Use PWF when a task has multiple phases, requires research, or involves more than ~5 tool calls. Triggers:
- User says "let's plan this", "plan mode", "use planning", or invokes `/planning-init`
- Complex issue work begins (multi-step, uncertain approach)
- Claude judges the task warrants structured tracking

Skip planning for single-file edits, quick fixes, or tasks with obvious next steps.

## The Workflow

1. **Explore first** — Enter plan mode (read-only). Read code, trace paths, understand the problem before proposing anything. When the work codifies a pattern that already exists in multiple places (reference implementations across repos), read **every** reference in full, not just the canonical one — variation across references surfaces patches before v0.1 instead of as churn later (soul#52: reading all 4 references preempted 5 of the 7 fixes a dry-run would have found). Don't substitute Explore-agent summaries for direct reads; agents sometimes report existing files as absent.
2. **Plan to files** — Write the plan into 3 files in `planning/active/`:
   - `task_plan.md` — Phases with checkbox tasks
   - `findings.md` — Research, discoveries, technical analysis
   - `progress.md` — Session log with timestamps and commit refs
3. **Plan-review with the Plan agent — concurrently, not as a gate** — Once `task_plan.md` is scaffolded, spawn the Plan subagent (`Agent({subagent_type: "Plan", prompt: "..."}`) and ask it to critically review the task_plan against the issue body + actual codebase. Categorize findings as Blocker / Gap / Ordering / Assumption / Scope / Acceptance. The agent reads files fresh — it catches what you miss when you've been thinking about the design too long. Real example: caught 21 issues including hardcoded literals across 4 files not listed in the plan, untested DB column mismatches, and a baseline-cache-shadow that would have produced a 6-second no-op run.

   **Do not wait for it.** Spawn, then start the lowest-risk phase. Background agents have repeatedly returned late — in one case after the entire issue had shipped — so treating the review as a precondition stalls the work for as long as the agent takes (see `karpathy.md` §6). Fold findings in whenever they land: pre-baseline they edit the plan; mid-implementation they become follow-up commits — unless the finding is a stored-data fork of the kind `karpathy.md` §8 reserves for the user. A review that arrives after the code is written is not wasted — the reviewer reads real code instead of a plan, which is how one late review still contributed three fixes that no earlier reading had found. If you genuinely cannot proceed without the result, run it with `run_in_background: false` so the blocking is explicit.

   Verify before acting, in both directions. Findings have been confidently wrong (a "BLOCKER" disproved by a 30-second probe) and confidently right about things nobody suspected. Reproduce the claim first.

   **"Both directions" includes the reviewer's conclusions, not just its findings.**
   A review is wrong in the *alarming* direction loudly — a BLOCKER you probe and
   disprove costs one round-trip. It is wrong in the *reassuring* direction
   silently, because nothing prompts you to check a sentence telling you that you
   are finished. Measured 2026-08-30 in gq#77: round 4 fixed its own finding and
   characterised the residual as "definitional". Two commands showed it was not —
   the leftover axis had exactly one member and no margin, the same shape as the
   instance that reviewer had just fixed. Treat *"this is now terminal / complete /
   definitional"* as a claim with an author, exactly like an issue asserting a
   question can only be answered by testing.

   Corollary on when to stop: **convergence is not a reviewer saying you have
   converged.** Across four rounds on that PR, five instances of one defect class
   were found, and three separate "this is terminal now" claims — two of them mine
   — were wrong. What ended it was enumerating the complete candidate set and
   showing nothing sat above its source, not another round.

   **Spawn review agents UNNAMED.** Passing `name` to the `Agent` tool changes what you get: a named spawn becomes a persistent *teammate* that goes **idle** rather than completing, so there is no final report to auto-deliver and its output must be pulled with `SendMessage`. An unnamed spawn is a fire-and-return subagent whose report arrives on its own in the completion notification. Measured 2026-08-25 on one machine, one session, unchanged settings: the unnamed spawn returned in **6.4s**; three named reviewers returned nothing at all, sending only empty idle pings. Pass `name` only for a collaborator you intend to keep messaging, and shut it down when done — it pings indefinitely otherwise.

   That mis-spawn is what produced the silent-delivery failures below, so check `name` before suspecting settings. Teammate mode (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode`, merged globally from `soul/settings/defaults.json`) shapes what a *named* spawn becomes; it is not by itself why findings go missing, and an unnamed spawn delivers fine with it enabled.

   **Get the findings into a file — but check who is doing the writing.** Message delivery has silently failed twice: one review arrived as idle notifications with no content, and one was routed to a different session on the user's phone, surfacing only because the user mentioned it. From this side an idle ping is indistinguishable from an agent that had nothing to say, so the loss is invisible. A file (`planning/active/review-<N>.md`) survives routing, survives the agent exiting, and is greppable later.

   **The `Plan` and `Explore` agent types have no Write tool, so they cannot write that file.** Both plan reviews on 2026-08-26 (gq#61, gq#40) were instructed to and were structurally unable to; one said so outright — *"I have no Write/Edit tools and am explicitly barred from creating files; an agent instruction can't lift that"* — and returned the full review as reply text instead. Both arrived intact, ~26 findings each. So:

   - **Read-only agent** (`Plan`, `Explore`): ask for the findings **in the reply**, then write them to `planning/active/review-<N>.md` yourself. The file is still the deliverable; you are just the one creating it.
   - **Agent type that can write**: put the file-path instruction in the first prompt, not as a follow-up.

   Asking for a file the agent cannot produce costs a round-trip, and — worse — sets you up to read an absent file as an absent review. Check the agent type's tools before writing the instruction.

   **A reviewer asked to prove a guard fires will patch your working tree, and that races
   your own test runs.** "Restore the defect and watch it go red" is the right instruction
   (`code-check.md`), and a subagent given it edits the same files the parent is testing.
   From the parent's side the result is a test run that reports failures belonging to
   nobody's code — the reviewer's planted defect, caught mid-flight. Tell reviewers to work
   in a copy (`cp -r` to a temp dir, or a worktree) and say so in the prompt; they honour it
   when asked. Then snapshot the files you care about and `cmp` them before **and after**
   every run whose result you intend to act on, so "the tree was intact for this
   measurement" is a fact rather than an assumption. Same hazard as a mid-flight edit in
   `karpathy.md` §5, arriving from an agent instead of from you.

   **Review the fixes, not just the code.** The second pass is where the value concentrates, because a fix written under a wrong assumption reproduces the same defect. Measured on gq#52: pass 1 found 13 defects, pass 2 found 7 more — including a blocker sitting *inside the fix* for pass 1's blocker, the same class twice (`lty`, then `fill_alpha`) because completeness was reasoned about rather than computed. Pass 3, scoped narrowly to the file edited most, found no new instances; **convergence is the signal to stop, not a fixed number of rounds.**

   Convergence is measured, not felt — a quiet round and an exhausted reviewer look
   identical. The rule that terminated trap#28 (five rounds; each of the first four
   found its best defect *inside the previous round's fix*) was to **enumerate the
   candidate set mechanically and show nothing sits above its source of truth**: parse
   the files and walk every `cli_abort`/`warning`/`stop` rather than recalling them, so
   "all of them are pinned" is a count. For the guards a fix introduced, the equivalent
   instrument is a mutation table (`code-check.md`, "Restore the bug and prove the guard
   fires"). `code-check.md` states the enumeration rule under "A guard's
   scope, escape hatches, and remedies" — terminate by enumeration, not by a reviewer
   saying you have converged. `/code-check` treats three rounds as the floor and keeps
   going while a round finds a defect inside the previous fix.

   Ask for the **mechanism**, not more instances. Pass 3's best finding was that an invariant was enforced by two lists happening to agree — which is what had produced instances two and three.

   The thing reviewers catch that self-probing does not is **interop**: 18 tests inspected a legend object and none handed it to the renderer, which rejected it outright. Ask the consumer.
4. **Lock naming before the baseline** — If naming feedback surfaces during planning (legacy filename, inconsistency with an existing file family), fold the rename into the convention + task_plan BEFORE the baseline commit, not as a follow-up. Pre-baseline it's free; retrofitting after implementation cascades (soul#52: `build_exec_pdf.R` → `run_pagedown_exec_summary.R` locked in pre-baseline meant zero downstream rework).
5. **Commit the plan** — After Plan-agent review + fixes. This is the baseline.
6. **Work in atomic commits** — Each commit bundles code changes WITH checkbox updates in the planning files. The diff shows both what was done and the checkbox marking it done.
7. **Code check before commit** — Run `/code-check` on staged diffs before committing. Don't mark a task done until the diff passes review.
8. **Archive when complete** — Move `planning/active/` to `planning/archive/` via `/planning-archive`. Write a README.md in the archive directory with a one-paragraph outcome summary and closing commit/PR ref — future sessions scan these to catch up fast. Where the work produced measurements, that README is also the evidence record; see below.

## The archive README is the measurement record

Debugging and benchmarking sessions are systematic investigation: a stated unknown, an
experiment, a number, a conclusion, and usually two or three informative dead ends. That
is SRED evidence, and it scatters — into PR bodies, issue comments, and log files whose
names encode a timestamp and nothing else. In six months the chain *we did not know X,
we measured Y, therefore Z* survives only in a chat transcript.

**The archive README is where that chain lives.** Not a separate run record: the PWF
triple already holds every part of it — the question in `task_plan.md`'s frame, the
method in `progress.md`, the numbers in `findings.md`, the dead ends in its "Errors
Encountered" table. A second document would restate all of it and be half-populated.
The README is the index over them.

So an archive README for work that produced measurements carries two more sections:

```markdown
## Measurement

m1 0.0391 vs cypher 0.0872 min/1k segments — hosts are 2.23x apart.
Moved the provincial estimate 5.0 h -> 4.3 h and changed how work packs across machines.

## Evidence

`data-raw/logs/study_area_run/20260831_19*` — four spins, one defect each.
```

Three rules on those sections:

- **Numbers carry units, and say what changed because of them.** A measurement nobody
  acted on is still worth recording if it turned an assumption into a number — say that
  too. "Confirmed the expected" is a real outcome.
- **Cite a prefix or glob, never a file list.** A list rots the moment a run is re-run;
  a prefix survives. This is why campaign subdirectories exist (`newgraph.md`, "Which
  logs to commit").
- **Keep the wrong turns.** A diagnosis made, retracted on a bad inference, then
  confirmed by measurement *is* the evidence of systematic investigation. Sanitising it
  into a tidy conclusion destroys exactly what makes the record worth keeping.

**The case this does not cover.** Measurement that predates an issue has no PWF to
attach to — `/planning-init` takes an issue number, and exploratory runs often *produce*
the issues rather than follow them. That measurement belongs in the issue or PR it
spawned, with the log directory's own README as the index. Do not build a third system
to close this gap. The *finding* it settles goes where every settled finding goes —
`research/`, next section — which is not a third record of the run but the one place its
verdict is kept current.

## `research/` — what is known, outliving the issue that found it

Three homes, one job each: **the PWF archive is the story, committed logs are the
measurements, `research/` is the durable verdict** — floodplains' `research/README.md`
had that framing before this section existed. A research file holds what is now *known*: a
settled method, a measured fact about an external system, a search that established an
absence — so that someone picking the work up months later does not re-derive it.
`planning/archive/<issue>/` holds what was *done*, in order, for one issue, and is rarely
opened by anyone who never saw that issue. The research file is the one they will look for.

What does **not** go there: a work log; a run record (Run / Hardware / Software /
Configuration blocks — that is the archive README's `Measurement` and `Evidence`, above);
the raw numbers (committed logs). Measured 2026-09-06 across the seven repos carrying a
`research/`, 40 topic files: link's `provincial_parity_2026_05_*.md` are four run records in
25 days, each dated by the run it records and carrying that run's setup and metrics, while
its living documents, `bcfishpass_methodology.md`,
`study_area_run.md` and `provincial_run_runbook.md`, are single files revised as the
knowledge moved. The second shape is the one that moves the state of knowledge; the first
duplicates the archive.

### One topic file, revised in place — git is the version record

`research/<topic>.md`, noun-first, **no date in the filename**. A new measurement that
changes what is known revises the topic file; it does not add a dated sibling.
`git log --follow research/<topic>.md` is the dated history, the archive README it cites
is the *why*, and the logs are the numbers — everything an R&D claim needs, with no second
copy of any of it.

Existing dated files — `20260711_…`, `…_2026_05_25.md` — are **not renamed**. They are
cited by path from `CLAUDE.md` files and from other conventions (`bookdown.md`,
`karpathy.md` §7), and a rename breaks the citation the way it breaks log evidence
(`newgraph.md`, "Which logs to commit"). Convergence is forward-only, and the README says
when.

### The header is the provenance, in prose

No research file in any repo carries YAML frontmatter and nothing consumes it, so
provenance is one line under the H1. floodplains' is the shape to adapt — it already carries
the date and the issues, and names its log prefix in the body:

```markdown
**Date opened:** 2026-07-11 · **Issue:** #8 · **drift:** 0.6.0 (`dft_stac_fetch(tile_size=)`,
drift#36) · **Status:** OPEN — design set, runs pending.
```

Three things the line must carry — `**Verified:** <date> · **Issues:** … · **Produced by:** …`
is the minimal form:

- **When it was last true.** The file's date, and a section-level date wherever one
  section is re-verified alone. A research file whose numbers cannot be re-derived ages
  into folklore, and one that states a scope or a quantity drifts silently when the code
  moves — three link documents, two of them research files, asserted a recompute "runs over
  every WSG in the schema" after two commits had changed it (`karpathy.md` §7, "Documents
  that share an ancestor corroborate nothing"). When code changes a behaviour a research
  file describes, grep `research/` for the sentence. Files written before 2026-09-06 gain
  the line when next revised; no fleet sweep is required.
- **What produced it.** The script path or log prefix for a measurement; the source list or
  reference-manager collection for a literature review. Never a number without its producer.
- **Which issues it came from and which it spawned.** The issue body links the research
  file (`feature-workflow.md`, "Issue bodies get edited, not appended"); the research file
  names its issues; and an archive README whose `Measurement` was distilled into a research
  file links it. Both ways, every time — one direction leaves the other end unfindable.

### The directory carries a README

An index: one row per file, what it covers — rfp's is the model. Where other repos hold
related work, a "Related work" list of links. Where two naming patterns coexist, the
cutover line in the form `newgraph.md` uses for logs:

```markdown
Naming: `<topic>.md`, revised in place, from 2026-09-06.
Files dated before that carry a `yyyymmdd_` prefix; they are not being renamed.
```

The README is the index. `CLAUDE.md` links the README once and cites an individual file
only where a rule depends on it. Twenty-three topic files with no README and a `CLAUDE.md`
citing four of them by path — link, measured 2026-09-06 — is the state this prevents.

### R packages and public repos

`research/` is top-level and excluded from the tarball: `^research$` in `.Rbuildignore`
(`code-check-r.md`, "`R CMD build` ships every top-level directory not in
`.Rbuildignore`"). Not `inst/notes/` or `inst/research/`, which ship inside the installed
package — the three packages carrying those (eight files, 2026-09-06) migrate by issue,
forward-only. In a package, `research/` is also where durable reference notes go, because
`docs/` belongs to pkgdown and `inst/` ships. And a public tool repo's `research/` is
public: report findings from internal work aggregated, never by the names of who it was for.

## Atomic Commits (Critical)

Every commit that completes a planned task MUST include:
- The code/script changes
- The checkbox update in `task_plan.md` (`- [ ]` -> `- [x]`)
- A progress entry in `progress.md` if meaningful

This creates a git audit trail where `git log -- planning/` tells the full story. Each commit is self-documenting — you can backtrack with git and understand everything that happened.

## File Formats

### task_plan.md

Phases with checkboxes. This is the core tracking file.

```markdown
# Task: <issue title> (#<N>)

<issue body — Problem section if present, otherwise first paragraph>

## Phase 1: [Name]
- [ ] Task description
- [ ] Another task

## Phase 2: [Name]
- [ ] Task description
```

Mark tasks done as they're completed: `- [x] Task description`

### findings.md

Append-only research log. Discoveries, technical analysis, things learned.

```markdown
# Findings

## [Topic]
[What was found, with source/date]

## Errors Encountered

| Error | Resolution |
|-------|------------|
```

### progress.md

Session entries with commit references.

```markdown
# Progress

## Session YYYY-MM-DD
- Completed: [items]
- Commits: [refs]
- Next: [items]
```

<!-- The Reboot Test and the error ledger below are adapted from -->
<!-- OthmanAdi/planning-with-files (MIT). Soul does not install or invoke that -->
<!-- plugin — the useful parts are carried here as text. Adapted 2026-08-26. -->
<!-- Same precedent as the attribution header in karpathy.md. -->

## The Reboot Test

The planning files exist so the work survives an interruption. Whether they
actually do is checkable: at any point mid-task, these five questions must be
answerable from the files alone, without the conversation.

| Question | Answer source |
|----------|---------------|
| Where am I? | Current phase in `task_plan.md` |
| Where am I going? | Remaining phases in `task_plan.md` |
| What's the goal? | The `# Task: <title> (#N)` frame and problem statement at the top of `task_plan.md` |
| What have I learned? | `findings.md` |
| What have I done? | `progress.md` |

If an answer lives only in the session, **write it down and commit it**. Written
is not sufficient: an uncommitted `findings.md` does not move between machines,
and a repo whose `planning/` is gitignored accepts `git add planning/` with exit
0 while tracking nothing — see Directory Structure below.

This is the operational check for the rule that every interruption should be a
resume point: a session death, sleep, or machine swap should cost a re-run at
most, never lost context. That rule states the goal; this tests it.

Run it before any long wait, before compaction, and before switching machines —
the moments that take a session without warning. `/compact-prep` and
`/planning-update` are where it gets run; this section is what it asks.

## Directory Structure

```
planning/
  active/          <- Current work (3 PWF files)
  archive/         <- Completed issues
    YYYY-MM-issue-N-slug/
```

If `planning/` doesn't exist in the repo, run `/planning-init` first.

**`planning/active/` must be tracked, not gitignored.** The atomic-commit rule
above requires each commit to carry its own checkbox flip in `task_plan.md`; an
ignored `active/` drops it silently, so `git log -- planning/` shows archives
appearing fully-formed with no history behind them. In-flight PWF also stops
surviving a move between machines.

The failure is quiet in both directions. `git add planning/` reports nothing and
exits 0 on an ignored path, and files tracked *before* the rule existed keep
being tracked — including through a `git mv` into the ignored directory. So a
repo can look like it is working right up until the first genuinely new PWF file,
which simply never appears in a commit.

Check rather than assume:

```bash
git check-ignore -v planning/active/task_plan.md   # expect no output
```

Found 2026-08-24 in gq, where the rule dated from the scaffold commit and the
#17 files had only survived because they predated their move into that
directory. gq and roli were the only 2 of 32 repos carrying it; roli still does.

## When Something Keeps Failing

Before a second attempt, name the failure class. A **deterministic** failure
returns the same result to the same inputs, so re-running unchanged only spends a
turn — change the inputs or change the approach. A **transient** failure
(network, a provider read, a rate limit, a resource still settling) is the case
where a re-run *is* the attempt: `code-check-infra.md` prescribes exactly that for a
tofu plan that falsely reports a resource deleted. The rule is not "never retry";
it is never retry unchanged while expecting a different answer.

Escalate rather than iterate once the approach itself is in question. Report what
was tried and the exact error, and hand over the commands to run — the user is
assumed to be away, so a question answerable from a phone beats a retry loop they
cannot see. Escalating is not stopping: commit the current state, then move to
the lowest-risk independent part of the plan while the question is outstanding.

Two classes escalate immediately rather than after retries, because further
attempts make them worse:

- **A clamped session.** Once a live credential has been read, later
  system-mutating commands are refused regardless of route — seven consecutive
  refusals across unrelated routes is the documented case (`newgraph.md`,
  "Reading a secret clamps the rest of the session"). Trying more phrasings is
  the failure mode, not the remedy, and `/permissions` does not clear it.
- **Rate limits.** Retrying extends the block (`ci-monitoring.md`).

### Log the errors that cost a retry

An error that took more than one attempt to get past goes in `findings.md`, so
one task does not hit the same wall twice:

```markdown
## Errors Encountered

| Error | Resolution |
|-------|------------|
| `fatal: Unimplemented pathspec magic '_'` | Long-form `:(exclude)path` |
```

That row is also what graduation looks like: it began as one task's blocker and
now lives in `code-check-shell.md` as a general rule about pathspec magic. Most rows
never make that trip and should not — the ledger's job is to stop one task
repeating itself.

When a failure does generalize, it graduates to the convention that owns its
class: the `code-check*.md` family for a bug class in a diff — `code-check.md` for a
mechanism, `-shell`, `-r`, `-spatial` or `-infra` for a tool quirk — `ci-monitoring.md` for CI
behaviour, the domain convention otherwise.

## Skills

| Skill | When to use |
|-------|-------------|
| `/planning-init` | First time in a repo — creates directory structure |
| `/planning-update` | Mid-session — sync checkboxes and progress |
| `/planning-archive` | Issue complete — archive and create fresh active/ |


# R Package Development Conventions

Standards for R package development across New Graph Environment repositories.
Based on [R Packages (2e)](https://r-pkgs.org/) by Hadley Wickham and Jenny Bryan.

**Reference packages:** When starting a new package, study these existing
packages for patterns: `flooded`, `gq`. They demonstrate the conventions below
in practice (DESCRIPTION fields, README layout, NEWS.md style, pkgdown setup,
test structure, hex sticker, etc.).

## Style

- tidyverse style guide: snake_case, pipe operators (`|>` or `%>%`)
- Match existing patterns in each codebase
- Use `pak` for package installation (not `install.packages`)
- Prefer `fs::` helpers over base R for filesystem path operations in build
  scripts and scaffolds: `fs::dir_create()` (creates parents by default, no
  `recursive`/`showWarnings` fiddliness), `fs::path()`, `fs::file_delete()`,
  `fs::file_exists()`, `fs::path_file()`. Avoids cross-platform separator
  issues and silent no-ops on empty paths.
- Prefix column name vectors with `cols_` for discoverability in the
  environment pane: `cols_all`, `cols_carry`, `cols_split`, `cols_writable`.
  Same principle for other grouped vectors (`params_`, `tbl_`, etc.)
- For SQL DDL+INSERT pairs that share a schema, use a single named
  vector as the source of truth. Both `CREATE TABLE` and
  `INSERT (cols) SELECT cols` derive their column lists from the same
  `cols_*` vector. Avoids drift between table shape and write
  projection — when columns change, you edit one place. Example:
  ```r
  cols_streams <- c(
    id_segment           = "integer NOT NULL",
    watershed_group_code = "varchar(4) NOT NULL",
    geom                 = "geometry(MultiLineStringZM, 3005)"
    # …
  )
  # CREATE TABLE consumes both names + types
  ddl_body <- paste(names(cols_streams), unname(cols_streams), sep = " ",
                    collapse = ", ")
  # INSERT consumes names only
  proj <- paste(names(cols_streams), collapse = ", ")
  ```

## Package Structure

Follow R Packages (2e) conventions:
- `R/` for functions, `tests/testthat/` for tests, `man/` for docs
- `DESCRIPTION` with proper fields (Title, Description, Authors@R)
- `DESCRIPTION` URL field: include both the GitHub repo and the pkgdown site
  so pkgdown links correctly (e.g., `URL: https://github.com/OWNER/PKG,
  https://owner.github.io/PKG/`)
- `NAMESPACE` managed by roxygen2 (`#' @export`, `#' @import`, `#' @importFrom`)
- Never edit `NAMESPACE` or `man/` by hand

## One Function, One File

Each exported function gets its own R file and its own test file:
- `R/fl_mask.R` → `tests/testthat/test-fl_mask.R`
- Commit the function and its tests together
- Use `Fixes #N` in the commit message to close the corresponding issue

## GitHub Issues and SRED Tracking

### Issue-per-function workflow

File a GitHub issue for each function before building it. This creates a
traceable record of what was planned, built, and verified.

### Branching for SRED

For new packages or major features, work on a branch and merge via PR:

```
main ← scaffold-branch (PR closes with "Relates to NewGraphEnvironment/sred#N")
```

This gives one PR that contains all commits — a single SRED cross-reference
covers the entire body of work. Individual commits within the branch close
their respective function issues with `Fixes #N`.

### Closing issues

Close function issues via commit messages — see Closing Issues in newgraph conventions.

## Testing

- Use testthat 3e (`Config/testthat/edition: 3` in DESCRIPTION)
- Run `devtools::test()` before committing
- Test files mirror source: `R/utils.R` -> `tests/testthat/test-utils.R`
- Test for edge cases and potential failures, not just happy paths
- Tests must pass before closing the function's issue
- Always grep for errors in the same command as the test run to avoid
  running twice:
  ```bash
  Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5
  ```
  For error context: `grep -E "(ERROR:|FAIL )" -A 10 | head -25`

### Common pitfalls

- **`cli::cli_alert_warning()` is not `warning()`.** It's visual only —
  callers can't catch it with `withCallingHandlers(warning = ...)` and
  testthat's `expect_warning()` won't fire. When a function offers a
  `warn` mode that callers may want to react to programmatically, use
  `warning()`. Reserve `cli_alert_warning()` for FYI messages with no
  programmatic contract.

- **`expect_match(x, ..., all = FALSE)` passes silently on `character(0)`.**
  If the input is empty (e.g. no warnings fired), the assertion succeeds
  vacuously and defeats the test. Always pair with
  `expect_gt(length(x), 0)` first when input may be empty.

- **`skip_on_cran()` does not skip on GitHub Actions.** It skips when
  `NOT_CRAN` is unset — and `devtools`, `usethis`'s check workflow and
  `r-lib/actions` all set `NOT_CRAN=true`, precisely so your tests *do* run in
  CI. So a network test guarded only by `skip_on_cran()` runs on every push,
  and any upstream hiccup reddens the build for a reason unrelated to the
  change under review.
  - Use **`skip_on_ci()`** for a test that is meant for a human's machine — a
    live canary against a third-party service, something slow, anything whose
    failure needs a person to interpret it.
  - `skip_if_offline()` is not a substitute: it tests whether the network is
    reachable, not whether the *service* is behaving, and it calls
    `skip_if_not_installed("curl")`, so add `curl` to Suggests or the guard
    itself is what breaks.
  - Caught 2026-08 in gq#57 by self-review: a comment claiming "skipped off-CI"
    sat directly above code that did not skip off-CI. Read the guard, not the
    comment above it.

- **`testthat::test_file()` does NOT set `NOT_CRAN`, so re-running one file to
  diagnose a failure can execute none of it.** The mirror of the rule above, and
  the more dangerous direction: `devtools::test()` sets `NOT_CRAN=true`, so a
  `skip_on_cran()`-guarded test runs there and fails; re-running that same file
  with `testthat::test_file()` to investigate reports `SKIP` and looks like
  exoneration.

  ```
  devtools::test()                 -> [ FAIL 1 | PASS 4495 ]
  testthat::test_file("that.R")    -> [ FAIL 0 | SKIP 6 ]   Reason: On CRAN
  NOT_CRAN=true testthat::test_file("that.R") -> [ FAIL 0 | PASS 259 ]
  ```

  Only the third line is evidence. Measured twice on 2026-09-01 in rfp, both
  times while confirming whether a Docker-gated failure was a real regression —
  which is exactly when a false "it passes now" is most expensive. Prefix
  `NOT_CRAN=true` on any single-file re-run, or read the SKIP count rather than
  the FAIL count.

- **`local_mocked_bindings(.package = )` needs testthat >= 3.2.0.** A package
  pinned at `testthat (>= 3.0.0)` errors rather than skipping on an older
  install. Bump the pin when you first mock another package's binding.

## Examples and Vignettes

### Runnable examples on every exported function

Examples are how users discover what a function does. They must:
- **Actually run** — no `\dontrun{}` unless external resources are required
- **Use bundled test data** via `system.file()` so they work for anyone
- **Show why the function is useful** — not just that it runs, but what it
  produces and why you'd use it
- **Use qualified names** for non-exported dependencies (`terra::rast()`,
  `sf::st_read()`) since examples run in the user's environment

### Vignettes

At least one vignette showing the full pipeline on real data:
- Demonstrates the package solving an actual problem end-to-end
- Uses bundled test data (committed to `inst/testdata/`)
- Hosted on pkgdown so users can read it without installing

**Output format:** Use `bookdown::html_vignette2` (not
`rmarkdown::html_vignette`) for figure numbering. Requires `bookdown` in
Suggests and chunks must have `fig.cap` / `caption =` for numbered
figures and tables.

**Gotcha — cross-references don't resolve in vignettes.** `Table \@ref(tab:foo)`
and `Figure \@ref(fig:foo)` markers compile to a literal `\@ref(...)` in
the rendered HTML rather than a numbered link. Bookdown's cross-ref
machinery isn't fully wired through `html_vignette2` under pkgdown.
Use natural language instead — "the table below", "the floodplain map",
"the parameter table" — and let the captions speak for themselves. If
you need real numbered cross-refs, use `bookdown::html_document2`
(matches the cd-style report-appendix pattern) and accept that the
output is no longer a true package vignette.

**Vignettes that need external resources (DB, API, STAC):** Do NOT use
the `.Rmd.orig` pre-knit pattern — it breaks `bookdown` figure numbering
because knitr evaluates chunks during pre-knit and emits `![](path)`
markdown that bookdown can't number.

Instead, separate data generation from presentation:
1. `data-raw/vignette_data.R` — runs the queries, saves results as `.rds`
   to `inst/testdata/` (or `inst/vignette-data/`)
2. Vignette loads `.rds` files, all chunks run live during pkgdown build
3. Note at top of vignette: "Data generated by `data-raw/script.R`"
4. bookdown controls all chunks — figure numbers, cross-refs work

This is the same pattern as test data: `data-raw/` documents how the data
was produced, committed artifacts make vignettes reproducible without the
external resource.

### Test data

- Created via a script in `data-raw/` that documents exactly how the data
  was produced (database queries, spatial crops, etc.)
- Committed to `inst/testdata/` — small enough to ship with the package
- Used by tests, examples, and vignettes — one dataset, three purposes

## Documentation

- roxygen2 for all exported functions
- `@import` or `@importFrom` in the package-level doc (`R/<pkg>-package.R`)
  to populate NAMESPACE — don't rely on `::` everywhere in function bodies
- pkgdown site for public packages with `_pkgdown.yml` (bootstrap 5)
- GitHub Action for pkgdown (`usethis::use_github_action("pkgdown")`)

## lintr

Run `lintr::lint_package()` before committing R package code. Fix all warnings — every lint should be worth fixing.

### Recommended .lintr config

```r
linters: linters_with_defaults(
    line_length_linter(120),
    object_name_linter(styles = c("snake_case", "dotted.case")),
    commented_code_linter = NULL
  )
exclusions: list(
    "renv" = list(linters = "all")
  )
```

- 120 char line length (default 80 is too strict for data pipelines)
- Allow dotted.case (common in base R and legacy code)
- Suppress commented code lints (exploratory R scripts often have commented alternatives)
- Exclude renv directory entirely

## Dependencies

- Minimize Imports — use `Suggests` for packages only needed in tests/vignettes
- Pin versions only when breaking changes are known
- Prefer packages already in the tidyverse ecosystem

## Releasing

1. Update `NEWS.md` — keep it concise:
   - First release: one line (e.g., "Initial release. Brief description.")
   - Later releases: describe what changed and why, not function-by-function.
     Link to the pkgdown reference page for details — don't duplicate it.
   - Don't list every function; the pkgdown reference page is the single
     source of truth for what's in the package.
2. Bump version in `DESCRIPTION` (e.g., `0.0.0.9000` → `0.1.0`) — as the **final** commit of the branch, after verification numbers/tests are final. Mid-branch bumps are premature and churn: additional code changes end up bundled inside a "release" that already claimed the version.
3. Commit as "Release vX.Y.Z"
4. Tag: `git tag vX.Y.Z && git push && git push --tags`

## Repository Setup

### Branch protection

Protect main from deletion and force pushes:

```bash
gh api repos/OWNER/REPO/rulesets --method POST --input - <<'EOF'
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ]
}
EOF
```

### Scaffold checklist

- `usethis::create_package(".")`
- `usethis::use_mit_license("New Graph Environment Ltd.")`
- `usethis::use_testthat(edition = 3)`
- `usethis::use_pkgdown()`
- `usethis::use_github_action("pkgdown")`
- `usethis::use_directory("dev")` — reproducible setup script
- `usethis::use_directory("data-raw")` — data generation scripts
- Hex sticker via `hexSticker` (see `data-raw/make_hexsticker.R`)
- Set GitHub Pages to serve from `gh-pages` branch

### dev/dev.R

Keep a `dev/dev.R` file that documents every setup step. Not idempotent —
run interactively. This is the reproducible recipe for the package scaffold.

## README

Keep the README lean:
- Hex sticker, one-line description, install, example showing *why* it's
  useful
- Link to pkgdown vignette and function reference — don't duplicate them
- Don't maintain a function table — it's just another thing to keep updated
  and pkgdown's reference page is the single source of truth

## LLM Workflow

When an LLM assistant modifies R package code:
1. Run `lintr::lint_package()` — fix issues before committing
2. Run `devtools::test()` with error grep — ensure tests pass in one call:
   ```bash
   Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5
   ```
3. Run `devtools::document()` and grep for results:
   ```bash
   Rscript -e 'devtools::document()' 2>&1 | grep -E "(Writing|Updating|warning)" | tail -10
   ```
4. If the repo has a `_pkgdown.yml`, run `Rscript -e 'pkgdown::check_pkgdown()'`
   after adding or removing an export. A new export missing from the reference
   index is an **error**, not a note, so it reddens the pkgdown workflow after
   the PR is already open — the check costs a second locally and saves the round
   trip. (Adding to the index is usually right; `@keywords internal` is the
   alternative it names.)
5. Check `devtools::check()` passes for releases — capture results in one call:
   ```bash
   Rscript -e 'devtools::check()' 2>&1 | grep -E "(ERROR|WARNING|NOTE|errors|warnings|notes)" | tail -10
   ```
