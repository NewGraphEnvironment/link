# Code-check round 1 — #364 (branch 364-through-wetland-stretches-use-the-stream)

## Checklist read

Every FULL TEXT file is over 40,000 bytes, so none was read in full.

- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with the `|` table rows and evidence blocks skipped. Of `## Rules that stand alone`, `## Security` and `## Spreadsheets and PDFs` I read none (about 25 headings), because none names a tool or shape this diff uses.
- `code-check-r.md`: read 15 sections: Read-back shape; A `data-raw/` script must load the source tree; `$` partial-matches; A database driver's value; `::text` spelling; `nzchar(NA)`; `identical()` on two reader results; CSV whitespace; `sort()`/`order()` collate by LC_COLLATE; R's `yaml` mixed int/float; Postgres row order; `sprintf("%g")` Inf/NA; `information_schema` literal lookup; `system2(stdout = TRUE)`; `ifelse()` all-NA. About 110 others were not read.
- `code-check-spatial.md`: read 2 sections: FWA `upstream_route_measure`; FWA main flow is not edge type 1000 alone. About 95 others were not read.
- `code-check-shell.md`: none read (about 85 headings). The diff changes no shell, git or psql code.

## Findings

- **[fragile]** `R/lnk_discharge.R:421`, `.lnk_near_river_text()`. The log value is built with `sort(unique(x))`, which collates by `LC_COLLATE`. The text is stored in `<schema>.log.near_river` on the build host and string-compared in `.lnk_hv_check_log()` against a value computed on the validating host. For two pairs of one measure, the order depends on the locale:
  - C locale gives `channel_width:15:1000 channel_width:1:1000`.
  - `en_US.UTF-8` gives `channel_width:1:1000 channel_width:15:1000`. Measured in this session; macOS and glibc en_US both ignore punctuation at the first collation level.
  - The result is that a group built on a host in one locale (a cypher in C.UTF-8) and validated on m1 (en_US) is refused as "log records near_river pairs other than cfg reads", even though it was built correctly.
  - It is latent today, because every shipped bundle resolves at most one pair per group (CH only). It fires as soon as #346 gives a second species a pair, or a group carries both `channel_width` and `stream_order` pairs.
  - This is the stored-canonical-string case in code-check-r.md, "`sort()` and `order()` collate by `LC_COLLATE`". testthat forces `LC_COLLATE=C`, so the suite cannot see it.
  - Fix: `sort(unique(x), method = "radix")`.
  - A related point: `format(..., digits = 15)` formats the whole vector jointly, so a pair's text depends on its companions (`15` becomes `15.0` beside a `0.5`). This is harmless only while both sides compare the same set.

- **[fragile]** `R/lnk_pipeline_persist.R:221-238`. `streams_near_river` has no species key, but persist deletes **all** of a WSG's rows on every call and refills them from the working table. The working table holds only the pairs of the species that classify walked.
  - The trigger is the exported path `lnk_pipeline_classify(species = <subset>)` + `lnk_pipeline_persist(species = <subset>)` into a schema that already holds other species for that WSG. It removes the other species' walked distances while their `streams_habitat_<sp>` flags and the WSG's log row stay as they were.
  - The validator then passes the log check (unchanged row) and the table check (the table exists). It re-tests those species' near-river predicates against no rows, which silently reads `(size OR FALSE)`.
  - Shipped drivers are not hit: `lnk_pipeline_run` classifies every active species, and the variants harness persists into per-variant schemas.
  - Possible fixes: delete only the pairs the current classify resolves, or key the table by species.

- **[fragile]** `R/lnk_rules_build.R:450-489`. `rear_near_river = stream` does not keep the pair off 1050/1150 lines in two cases. The "dead combination" checks also miss inert combinations.
  - **`edge_types = "categories"`:** fresh's `stream` category contains 1050/1150. So the stamped carve rule is bypassed by the stream rule, which carries the pair. Compiled under categories: `s.edge_type IN (1000, 1050, 1100, 1150, 2000, 2100, 2300) AND … (s.channel_width … OR EXISTS (… near_river …))`. Explicit mode keeps the pair off these lines, so the two modes disagree.
  - **`rear_all_edges = yes`:** the unfiltered all-edges rule takes the pair (it is stamped only for `wetland_flow` scope), so 1050/1150 lines get it anyway.
  - **Inert choices that do not stop:** `rear_wetland_flow != free` or `rear_near_river = stream` together with `rear_no_fw = yes` / `rear_lake_only = yes` emits nothing and does not stop. The checks at :355-368 test only `rear_wetland` and `rear_stream`, not the branch that actually emits.
  - No shipped bundle hits any of these: all ship explicit mode, bcfishpass's rear_all_edges species BT is scope `both`, and SK/KO are `free` / `both`. They are config traps, not live bugs.

- **[fragile]** `data-raw/habitat_variants_build.R:419` (`own_rules <- length(dc) > 0L`). A variant gets its own `rules.yaml` only when its `dims` move a cell. But `rear_wetland_flow = gradient` bakes the bundle's `rear_gradient_max` into the 1050/1150 rule at build time (`R/lnk_rules_build.R:477-484`).
  - So a ladder variant whose `column` is `rear_gradient_max`, on a base with a gradient door (the bcfishpass bundle's CO), classifies the stream rules at the variant's gradient and the through-wetland rule at the base's.
  - That band is mis-scored with no error, and `built.csv`'s `rules_sha256` records the base's rules as correct.
  - This is the same class as the known `rear_lake_ha_min` needing a rules rebuild. It is a new instance, and nothing guards it.

- **[fragile]** `data-raw/habitat_score/variants_364.csv` no longer builds at HEAD. `default` now ships what the structure rows changed: CO and CH `rear_wetland_flow = stream`, and CH's model/15/3/1000 pair.
  - So `write_bundle()` drops the equal dims and set cells, and stops at `habitat_variants_build.R:394` ("ch_door_stream equals default: its dims and set change nothing").
  - `data-raw/habitat_score/README.md` names it as "the inputs for #364", but they reproduce only at the pre-move commit. The archive README should name that commit.
  - This is the same class as #302's ladders reproducing only at v0.58.0.

- **[fragile, pre-existing shape extended]** `R/lnk_habitat_validate.R:468`. `.lnk_hv_check_log()` takes each WSG's newest log row by `date_start` with no filter on outcome.
  - A run that opens its log row (logging the new `near_river` text) and then fails before persist leaves the old build's `streams_near_river` rows under a log value that matches `cfg`.
  - The validator then passes, and every `EXISTS` compares the old numbers against the predicate's new ones and never matches.
  - `discharge_fill` / `discharge_source` already have this shape. The pair numbers make it bite harder, because a mismatch is silent rather than approximate.

The remaining areas were checked and hold up, with no finding:

- **Validator log and schema checks against what classify walked.** The validator reads the same cfg species and the same per-group model as classify. fresh's walk and predicate join on `(id_segment, watershed_group_code)` plus the pair. A model change since the build shows as a text mismatch.
- **Consolidate.** The intersection copy keeps `streams_near_river` per bucket, and a `log.near_river` column is added by `ADD COLUMN IF NOT EXISTS`.
- **All five shipped bundles, in both edge modes,** build and pass `frs_params()`. Explicit-mode output matches the committed `rules.yaml` for bcfishpass, default and default_tuned. The frozen bundles differ only by stamps, which `audit_configs.R` strips.
- **The harness's build-side and score-side structure and sha checks** agree.

/Users/airvine/Projects/repo/link/planning/active/review-round1.md
