# Task: Break streams only where a present species' access changes (both configs); bcfishpass config takes the order-1 exception (#326)

## Context

link breaks streams at every 15 / 20 / 25 / 30 % gradient position of every configured species, whatever is present (`.lnk_pipeline_prep_minimal()`, `R/lnk_pipeline_prepare.R:607`, since #223). bcfishpass breaks each model's barriers only in groups where that model's species are present, **after** its observation and habitat lifts, reduced to the downstream-most position per flow path (`01_model_access_natural.sh`: build per model → delete non-minimal → `break_streams()`). In BT-only groups (PCEA, FINA, PARS) link therefore carries 2–3× the segments bcfishpass does and its finer segments flip BT spawn/rear gradient tests both ways: 71–85 km of two-way BT rearing disagreement per group under a 0.5–1.9 % net (#324, `research/bcfp_segmentation_parity.md`). #223's failure was reducing the *pre-lift* set (a lifted mainstem barrier pruned real tributary frontiers), not reducing as such.

Outcome: both configs break at the per-present-species post-lift set reduced to the downstream-most per flow path; segment counts fall toward bcfishpass's; the `bcfishpass` bundle takes bcfishpass's order-1 rearing width exception.

**What exploration and the plan review established (do not re-derive):**
- The reduction fits inside `lnk_pipeline_prepare()` with no phase moved: `barrier_overrides` (per `species_code`, **uppercase** from `parameters_fresh`, rounded measures) is written by `.lnk_pipeline_prep_overrides()` at line 125, *before* `.lnk_pipeline_prep_minimal()` at 126; `barriers_definite`, `falls`, `gradient_barriers_raw` (with ltrees) and `barriers_subsurfaceflow` are all in the working schema by then. The persist-backed `barriers_<sp>_access` views (`R/lnk_barriers_views.R:197-221`) are only built after break and are the *same recipe* — natural (gradient at class ≥ `access_gradient_max` ∪ falls ∪ subsurface) MINUS overrides (anti-join on `species_code` + `blue_line_key` + `abs(drm) < 1`) ∪ `USER_DEFINITE` (never lifted). Nothing the view reads is missing at prepare time; only scope differs (next point).
- **Scope of the per-group reduction.** `gradient_barriers_raw` is sampled along the whole of every line the group touches (`streams_blk` is a BLK list, `prepare.R:394-399`; `frs_break_find` has no group filter), so a gradient barrier on a shared main stem below the group's outlet *does* prune this group's frontier. The residual against bcfishpass's province-wide delete is where the blocking barrier sits on a different blue line joining below the outlet, or is a falls / subsurface / definite barrier outside the AOI (those three are AOI-filtered: `:178-179`, `:536`, `:186`). Out-of-AOI positions survive into `barriers_<sp>_min` — harmless to `frs_break_apply` (streams are AOI-filtered) but any break census must be restricted to the group's streams and label them, not count them as link-only.
- `fresh::frs_barriers_minimal(conn, from, to, tolerance = 1)` exists on fresh 0.42.0 (exported, measure-aware 10-arg `fwa_upstream`, requires `blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree`). It has **no species partition** — call it once per species table, never on the union (reducing the union would let one species' barrier prune another's frontier and move access).
- `barriers_definite` belongs **inside** the per-species table before the reduction: bcfishpass inserts `barriers_filtered UNION ALL barriers_user_definite` into `barriers_<model>` and then runs the non-minimal delete on that whole table. The research doc's "appended after" refers to the lift, not the reduction. A definite barrier pruned there still breaks through the independent `barriers_definite` source.
- Rounding: raw measures are `ROUND(…, 2)`, overrides `round(drm)`; the `abs(…) < 1` anti-join already covers the gap and the view anti-joins on the raw measure, so **do not round** before the reduction (it can only change which of two near-coincident positions survives). `frs_break_apply` DISTINCTs after `round(…, 0)` and skips breaks within 1 m of a segment end, as bcfishpass `break_streams` does — no double count. Raw rows whose FWA join found no segment carry NULL ltrees and neither prune nor are pruned: filter `wscode_ltree IS NOT NULL` as classify's subsurface branch does.
- The classify-time access gate is unaffected: `.lnk_pipeline_classify_build_breaks` (`R/lnk_pipeline_classify.R:213`) reads the full `gradient_barriers_raw`, not the break table. Shipped access is `streams_access` from the views. Only segmentation changes.
- `fresh::frs_order_child()` (`fresh/R/frs_order_child.R:137`) tests only `accessible`, order and parent order. bcfishpass's exception sits inside `s.gradient <= t.rear_gradient_max` **and** `channel_width <= rear_channel_width_max` (`load_habitat_linear_bt.sql:88-96`), so a NULL width never qualifies and a steep order-1 line never rears. fwapg models no order-1 width, so in practice the exception admits only field-measured / river-polygon widths. The YAML key is `channel_width_min_bypass` on a rear rule (validated at `fresh/R/frs_params.R:457`), emitted by `lnk_rules_build.R:446-485` onto **both** the stream and river rear rules, consumed at `R/lnk_pipeline_classify.R:165-198` (first rule carrying the key; skipped for `mad` groups). Every bundle currently sets `rear_stream_order_bypass = no`. The bcfishpass BT rear rule is `- []`, so the width minimum comes from thresholds (`params[[sp]]$rear_channel_width_min`); a rule carrying its own `channel_width` range should win.
- Habitat lifts are computed from the whole `user_habitat_classification` CSV with no AOI filter (`prepare.R:235-240`; `lnk_barrier_overrides.R:237-255`) where bcfishpass filters to `:'wsg'`. Pre-existing for access; now it also decides which positions prune. Not changed here; named.
- fresh's local checkout is **142 commits behind** origin/main (0.33.0 vs 0.42.0); link pins `fresh (>= 0.42.0)` / `Remotes: NewGraphEnvironment/fresh@v0.42.0`; `.lnk_fresh_required()` must regain `frs_barriers_minimal` (the callsite drift guard fails otherwise) and `.lnk_fresh_required_formals()` must learn the new `frs_order_child` formal.
- `break_order` keeps `falls`, `barriers_definite`, `subsurfaceflow` as independent sources (#96). After the reduction each adds breaks at **every non-minimal position of its kind**, not only lifted ones; `falls` is redundant for parity (HORS #96's case survives post-lift reduction). Left as-is; the residual is measured and named.
- Presence: `lnk_presence()` (salmon / ct_dv_rb expansion) differs from `lnk_pipeline_species()` (literal `"t"`) only by expansion in the shipped CSVs. LKEL has `sk` empty with CH/CM/CO/PK present, so SK breaks and never classifies — harmless, its `parameters_fresh` row is identical to CH's. Under `default`, RB (present in PCEA/FINA/PARS, 0.25, lifted by RB observations only) builds a set whose frontiers differ from BT's, so `default` breaks at RB-only frontiers as well as GR / KO 15 % — expect `default` to fall less than `bcfishpass`; report the ratio, do not promise it.
- This m4 docker `fwapg` is stale (no `fresh.log`, PCEA at 33,765 segments = pre-#223). `fresh.streams_vw_bcfp` is present (4.27 M rows).

## Decided at the gate (2026-10-26, airvine)

- **Verification runs on m4 locally** after `data-raw/snapshot_bcfp.sh` refreshes the primitives; re-model the measurement groups here.
- **Scope item 3 (strict `>` spawning minimum) is deferred** to its own fresh + link follow-up issue, filed with the km it moves (PCEA 1.78, FINA 4.54, PARS 5.27).
- **Per-config segmentation is accepted.** `default` (GR, KO at 0.15; RB frontiers) will break BT-only groups where `bcfishpass` will not. The PARS vignette's `id_segment` join (`data-raw/wsg_vignette_data.R:84-104`) is owed a separate fix; the guard there stays and will refuse until it is done.
- **Presence rule for which species' sets break:** `lnk_presence()` with its group expansion, applied as `tolower(sp) %in% pres$present` while iterating `cfg$species` — so the species code that reaches the SQL stays the `parameters_fresh` code (`'BT'`), matching `barrier_overrides.species_code`. A lowercase literal would match no override and reduce the pre-lift set, #223's failure (review B1).
- **`gradient_barriers_minimal` keeps its name.** It is minimal again; #225 (rename) closes as moot in the PR. The raw per-species `barriers_<sp>` table becomes the **post-lift** table and `barriers_<sp>_min` its reduction (RUNBOOK §2b's name); the diagnostics note at `lnk_barriers_views.R:165-167` is updated to say so.
- **Names, proposed (decide at resume):** fresh `frs_order_child()` gains two formals — the width bound (review prefers `channel_width_lt` over `channel_width_max`, since the value is the species' *minimum*) and `gradient_max`; both NULL by default, both applied when given. YAML sub-key `channel_width_min_bypass.width_known_below_min: true` (logical scalar, validated). link passes the width from the rule carrying the key, else `params[[sp]]$rear_channel_width_min`, and errors when neither exists; `gradient_max` from `params[[sp]]$rear_gradient_max`.
- **Phase order (review O1, O2):** the m4 snapshot refresh precedes the first pre-flight; the fresh pin bump moves to Phase 3 so Phases 1–2 do not wait on a fresh release.

## Phase 0: fresh — `frs_order_child()` width and gradient tests (sibling repo: branch + PR + release, never push main)

- [ ] `git -C ~/Projects/repo/fresh pull --ff-only` (142 behind); draft the fresh issue body, show it, file only on approval; branch `<N>-order-child-width`
- [ ] `frs_order_child()`: new formals (width bound, `gradient_max`), SQL gains `AND s.channel_width IS NOT NULL AND s.channel_width < %s` and `AND s.gradient <= %s` when set; roxygen cites `load_habitat_linear_bt.sql:88-96`
- [ ] `frs_params` validator: `bypass_keys` gains `width_known_below_min` with a logical-scalar check (`R/frs_params.R:457-460`)
- [ ] Tests: mocked SQL-shape (formals absent → no clauses; present → both clauses with the values), plus a live `skip_if_no_db` case on one order-1 / parent ≥ 5 reach proving a NULL-width line and a steep (> `rear_gradient_max`) measured-width line are never admitted and a gentle measured-width line is
- [ ] NEWS entry; `devtools::test()`, `check()`, `lint_package()`; PR; release v0.43.0 + tag

## Phase 1: link — tests first (mocked via `.lnk_db_execute` capture; `tests/testthat/test-lnk_pipeline_prepare.R:278-516` rewritten — every existing `prep_minimal` fixture lacks `wsg_species_presence` and will error in `lnk_presence()`)

- [x] Fixtures where configured ⊋ present: cfg BT/CH/SK/ST/WCT with a presence row `bt = t` only → exactly one `barriers_bt_min`; a salmon-expansion row (`ch = t`, `sk` empty) → `barriers_ch_min` and `barriers_sk_min`; a row with no present species → the empty-table shape
- [x] Each per-species CREATE anti-joins `barrier_overrides` with the **uppercase** literal (`o.species_code = 'BT'`) and `abs(…) < 1`, unions `barriers_definite` inside the same table, filters `wscode_ltree IS NOT NULL`, includes `barriers_subsurfaceflow` only when `subsurfaceflow` is in `break_order`, and does not round measures
- [x] Ordering in the captured calls: the per-species CREATE precedes the `frs_barriers_minimal` call whose `from` is that table and `to` is `barriers_<sp>_min`; `expect_length(minimal_calls, n_present)`; the `gradient_barriers_minimal` union names `_min` tables only (`expect_no_match(union_sql, "barriers_bt\\b")`, the inverse of today's `:324`)
- [x] Orphan-class path (`barriers_orphan`, extrabreaks / rearbreaks bundles) unchanged and still not reduced
- [x] *(moved to Phase 3 with its code; the formal names are the open decision)* `test-lnk_pipeline_classify.R`: with `width_known_below_min` on the bypass, `frs_order_child` receives the width from the carrying rule, else from `params[[sp]]$rear_channel_width_min`, and `gradient_max = params[[sp]]$rear_gradient_max`; neither available → error, not a silent NULL (the existing `frs_params` mock at `:208-214` has no width); without the sub-key the formals are absent
- [x] *(moved to Phase 3)* `test-lnk_rules_build.R`: `rear_stream_order_bypass = yes` puts the sub-key on both the stream and river rear rules; `no` emits no bypass block
- [x] Restore-the-bug check: with the reduction patched out, the per-species-count and ordering assertions go red (the FINA-frontier check is live-DB and belongs to Phase 2)

## Phase 2: break where a present species' access changes

- [x] `.lnk_pipeline_prep_minimal()` (`R/lnk_pipeline_prepare.R:607-742`): `pres <- lnk_presence(loaded$wsg_species_presence, aoi)`; iterate `cfg$species`, skip unless `tolower(sp) %in% pres$present`; per species write `barriers_<sp>` = `gradient_barriers_raw WHERE gradient_class IN (classes ≥ amax) AND wscode_ltree IS NOT NULL` ∪ `falls` ∪ `barriers_subsurfaceflow` (if present), raw measures, ltrees carried, `WHERE NOT EXISTS (barrier_overrides o WHERE o.species_code = '<SP>' AND same blk AND abs(drm) < 1)`, `UNION ALL barriers_definite` (joined to FWA for ltrees); then `fresh::frs_barriers_minimal(from = barriers_<sp>, to = barriers_<sp>_min)`; union the `_min` tables (+ orphans) into `gradient_barriers_minimal`
- [x] `.lnk_fresh_required()` regains `frs_barriers_minimal` (`R/lnk_preflight_fresh.R:113-119`)
- [x] Rewrite the stale comments (lines 614-621, 664-673, the "matches bcfishpass … every gradient barrier" claim), the roxygen at `R/lnk_pipeline_prepare.R:18-21,70` and `R/lnk_pipeline_break.R:24`, the diagnostics note at `lnk_barriers_views.R:165-167`; RUNBOOK §2b row for `barriers_<sp>_min` (line 164) and §1's phase diagram (line 55 puts unify before break — it runs after connect, `lnk_pipeline_run.R:226`)
- [x] `data-raw/snapshot_bcfp.sh` on m4 (not re-pulled: loaded 2026-10-25, 1.9 d old); `lnk_preflight_vintage()` passes at its default (needed by every live check from here on)
- [x] Single-group pre-flight on FINA (bcfishpass config): `parity_crosssection.R`'s structural check — blk 359209845 BT frontier stays at 3,834.78 m (#223's case) — and FINA segment count lands near bcfishpass's (link today 70 k, bcfp ~20.4 k breaks); report as departures from bcfishpass, not raw numbers
- [ ] `/code-check`; commit with checkbox flip

## Phase 3: order-1 width exception in the `bcfishpass` config

- [ ] *(formals guard done; floor + `Remotes` pin wait for the fresh v0.43.0 tag: `load_all()` refuses an installed fresh below the floor)* link: `DESCRIPTION` Imports floor `fresh (>= 0.43.0)` + `Remotes` pin `@v0.43.0`; `.lnk_fresh_required_formals()` adds the two `frs_order_child` formals; `pak::local_install()` here
- [x] `lnk_rules_build.R:446-485` (derived: every bypass carries the key; dictionary row updated, no new column): the bypass block carries `width_known_below_min: true` (from a new dictionary-declared `dimensions.csv` column, or derived — decide at implementation; add the `configs/dictionary_dimensions.csv` row either way so `test-dictionaries.R` and `audit_configs.R` stay green)
- [x] `R/lnk_pipeline_classify.R:165-198`: when the sub-key is set, resolve the width (carrying rule → thresholds → error) and `gradient_max`, pass both; `mad` groups still skip
- [x] `inst/extdata/configs/bcfishpass/dimensions.csv`: `rear_stream_order_bypass = yes` for BT, CH, CO, ST, WCT (bcfishpass's five; not CM, PK, SK); `Rscript data-raw/build_rules.R`; `git diff inst/extdata/configs/bcfishpass/rules.yaml` shows the block on the stream and river rear rules of exactly those five species (nine rule objects — some species carry one) and nothing else; `default*` bundles untouched (#327 decides theirs)
- [ ] Pre-flight on PARS (bcfishpass config): BT rearing moves by about −24.8 km on the 54 lines #324 named, 0 km on NULL-width lines, and **0 link-only km on order-1 / parent ≥ 5 lines** (the steep-line case `mechanism.R`'s `bypass` class cannot see, since it is `bcfp_only` only)
- [ ] `/code-check`; commit

## Phase 4: measure (m4, local docker; evidence under `data-raw/logs/segmentation_326/` with a README)

- [x] **Write the run decision into the README before the first `wsg_run_one.R` call:** every persisted group re-segments (both schemas, all 241), then the post-consolidate recompute — the next provincial run at this release; a partial run cannot do it
- [ ] Re-model PCEA, FINA, PARS, LKEL × {`bcfishpass`, `default`} with `data-raw/wsg_run_one.R` (DS-first order per `lnk_wsg_downstream_check()`), then `wsg_recompute_one.R` with `merge = TRUE`; stamp link + fresh SHAs, snapshot vintage and `fresh.streams_vw_bcfp` row counts in the README
- [ ] Break-position diff against `fresh.streams_vw_bcfp` (promote `data-raw/logs/rearing_diff_324/breaks.R` to `data-raw/breaks_diff.R`), **restricted to the group's streams, out-of-AOI positions labelled not counted**: bcfp breaks still held within 1 m (PCEA 24,392 / 24,393 before); link-only breaks named by source — expected residuals: non-minimal positions from the independent `falls` / `barriers_definite` / `subsurfaceflow` sources, cross-group frontiers (a blocking barrier on another blue line below the outlet, or a non-gradient barrier outside the AOI), `default`'s GR / KO 15 % and RB frontiers; anything else is a defect
- [ ] Classify-scope residual (link review round 1): per re-modelled group, count in-AOI `barriers_<sp>` positions pruned only by an out-of-AOI barrier (classify's AOI-filtered gate sees the frontier but not its pruner, so the straddling segment is classify-accessible above it until `lnk_habitat_gate()` settles it). FINA: 0. Count a Fraser or Peace main-stem group before calling it negligible
- [ ] Segment counts per group per config beside bcfishpass's (PCEA 37,957; LKEL 3,360); report the measured ratio for each config
- [ ] `data-raw/parity_crosssection.R` on the issue's 11 WSGs × 8 species (bcfishpass config; the remaining 7 groups re-modelled here too — hours; state the wall clock): `accessible_km` within 0.05 % as before; BULK SK stays the parked fresh#190 exception
- [ ] `data-raw/habitat_diff_segments.R <WSG> bt fresh rearing` and `spawning` on PCEA / FINA / PARS / LKEL: the `rear gradient` and `connectivity, split stream` columns collapse toward 0; PARS's `width exception` column goes to ~0 with no new link-only km on order-1 lines; the width-rule spawning km (1.78 / 4.54 / 5.27 at exactly 2.0 m) remains and is the deferred strict-`>` residual
- [ ] `research/bcfp_segmentation_parity.md`: "How link breaks them today" rewritten to the new rule, measured table added; `research/bcfp_divergence_taxonomy.yml`: retire `hors-class-stream-order-bypass`, resolve `bt-gradient-segmentation-over/under`, `pars-bt-rearing-width-exception`, `pcea-bt-connection-width-exception`, rewrite the SEGMENTATION header; `lnk_parity_annotate()` tests still pass
- [ ] `CLAUDE.md` status block (what moved, facts not worth re-deriving, the run decision); commit

## Phase 5: close out

- [ ] NEWS.md entry (#326; closes #225 as moot; names the owed provincial re-model and the two follow-ups)
- [ ] `devtools::document()` (read what it prints), `devtools::test()`, `devtools::check()`, `lintr::lint_package()` against the HEAD baseline
- [ ] File the two follow-up issues (bodies shown first): strict `>` spawning minimum (fresh + link); PARS vignette join off `id_segment` across configs
- [ ] `/planning-archive`, `/gh-pr-push`

## Owed at the end (reported, done after merge)

- [ ] **The provincial re-model:** every persisted group re-segments (both `fresh` and `fresh_default`, all 241), then the post-consolidate recompute — the next provincial run (#377's runs row) at the release this lands in. Stated in Phase 4's README before any re-model; done after merge.
- [ ] Vignette join fix (follow-up issue): `wsg_vignette_data.R` stops joining `fresh_default` tokens to `fresh` geometry on `id_segment`
- [ ] Strict `>` spawning minimum (follow-up issue, fresh + link)
- [ ] `default`'s own order-1 position stays with #327

## Validation

- [ ] Tests pass (link and fresh)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

**How each change is proved:**
- *Reduction correct:* FINA blk 359209845 BT frontier at 3,834.78 m survives (the exact case #223's pre-lift reduction lost); `accessible_km` 44/44 within 0.05 % — the reduction changes segmentation only, which holds per species because fresh's gate reads the full raw set and a pruned position always has a same-species barrier below it (never reduce the union); link still holds ≥ 99.9 % of bcfishpass's break positions within 1 m on the group's own streams.
- *Reduction does what it claims:* link-only breaks drop from 68,118 (PCEA) to the named residuals; segment counts near bcfishpass's on the `bcfishpass` config; `habitat_diff_segments.R` segmentation columns collapse.
- *Width exception correct:* PARS BT rearing −24.8 km on the 54 lines, 0 km on NULL-width order-1 lines, 0 link-only km on order-1 / parent ≥ 5 lines; PCEA connection lines −8.4 km (#319's row).
- *Nothing else moved:* `default` config re-modelled on the same four groups, diffed against its own pre-change persist on spawning/rearing km — only segmentation-attributable rows change.
- *Guards can fire:* restore the old `prep_minimal` body and watch the per-species-count and ordering tests go red before trusting them; the two fresh live cases (NULL width, steep line) must fail with the clauses removed.

Review: `planning/active/review-plan.md` (2026-10-26, Plan agent; both blockers verified against the code before folding).
