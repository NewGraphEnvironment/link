# Code-check round 6 (#246) — diff cc6.diff

Reviewer: subagent, 2026-10-17. Read-only against the DB (`fwapg` on localhost:5432); tests and a mutation
run in a copy of the repo under the session scratchpad. No repo file other than this one was written.

## Mechanism behind round 5 (and still present)

Round 5's three findings had one cause: a number or mechanism written into prose from a printed value or from
memory, not re-derived from its producer (the driver's printed "median 0.68" was its default; the bcfp precedence
was an assumption about SQL that does not express one; #348's scope was summarised beyond what the gate tests).
The same mechanism produces findings 2, 3 and 4 below: a size from a query that double-counts, a timing
attributed to the wrong run from memory, and a provenance statement taken from `log` alone when a second log
table records the code that wrote the shipped output. Finding 1 is the code-side version: a convention
(zero rows = "no data") assumed to mean "species absent", which UPET RB disproves.

## Findings

- **[bug] R/lnk_pipeline_access.R:241-249 (unchanged lines the fix relies on), CLAUDE.md "Status (2026-10-17)"
  fifth bullet.** When a *present* species has zero downstream-barrier rows, `has_barriers_<sp>_dnstr` is set NA
  for every segment, and `lnk_pipeline_mapping_code()` reads NA as "no data" and emits `""`
  (R/lnk_pipeline_mapping_code.R:234, :282). The fix at :369 makes `access_<sp>` correct, but the shipped mapping
  code then drops the species from the group entirely. Measured in `fresh_default`, UPET RB: 5,103 / 5,103
  segments `access_rb` 1 or 2, 325 spawning and 3,352 rearing segments in `streams_habitat_rb`, and
  `mapping_code_rb <> ''` on **0** of 5,103. The run's own compare shows the effect:
  `UPET ERROR: no shared mapping_code_<sp> columns ... (link: GR; ...)` (`provincial_246/run.log`) — RB is
  invisible because `.lnk_mc_active_species()` counts non-empty codes (R/lnk_compare_mapping_code.R:208). The
  comment at :241-247 states the convention's assumption ("the species has *no data* in this WSG ... e.g.
  `barriers_st` is empty in WSGs without ST"); UPET RB is a present species with no barrier, which the
  convention conflates with absence. CLAUDE.md records the NA as a fact "not worth re-deriving", which reads as
  intended behaviour. It is the only case in `fresh_default` (checked every `access_<sp>` /
  `has_barriers_<sp>_dnstr` pair across all 241 groups: only RB/UPET, 5,103 rows). Likely fix: set NA only when
  the species is absent (presence / `wsg_presence`), FALSE when present with zero rows; then the `:369` line is
  redundant but harmless. Operator's call whether to fix before merge or file; either way the CLAUDE.md bullet
  should say UPET RB's mapping code is blank, not present it as settled.

- **[bug, prose] CLAUDE.md "Status (2026-10-17)" last bullet ("`fresh_default` is 48 GB"); research/study_area_run.md
  table row "database growth" ("`fresh_default` 11 → 48 GB").** 48 GB is `sum(pg_total_relation_size())` over
  *every* `pg_class` row in the schema, indexes included, so every index is counted twice (once inside its
  table's total, once as itself). Measured now: tables + matviews `pg_total_relation_size` = **31 GB** (heap
  14 GB + indexes 17 GB); the all-relkinds sum reproduces 48 GB exactly (31 + 17). No `VACUUM FULL` has run
  (`pg_stat_user_tables.last_vacuum` NULL), so it was never 48 GB. The "11" before is very likely the same
  double count: planning measured `fresh_default` at 7.3 GB (findings.md "Disk"), and 7.3 × 48/31 ≈ 11.3. So
  the persist grew ~7 → 31 GB (+~24 GB), close to the plan's ~21 GB persist estimate, not +37. Same fix needed
  in findings.md "Size". (`fresh` is 22 GB by the correct measure, for comparison.) The 11.39 M segments and
  the 253 G free are right (df now: 590G size, 324G used, 241G avail after the parity run's +12 G).

- **[bug, prose] research/study_area_run.md:62-63 ("the ~10 s/WSG this step once quoted was a 34-group
  figure").** It was not. The figure is FINA's single-group measurement from #205 (May 2026): the same file at
  :87-88 says "~10s/WSG (FINA: 11.86s wall vs ~90s full pipeline)", and it entered this step's text in
  `0a332cc0` (#175/#205, 2026-05-26). The 34-group run (2026-08-31) measured "recompute + compare 55 min"
  (CLAUDE.md 2026-08-31 status), ~97 s per group, nowhere near 10 s. Same misattribution in findings.md
  "Recompute" ("August's ~10 s per group, serial"). Correct to "a one-group figure (FINA, #205)".

- **[fragile, prose/provenance] CLAUDE.md "One run_uid, two link SHAs" bullet; research/study_area_run.md
  "What went wrong" ("So the run carries two link SHAs: 239 groups `ee21eb13`, 2 groups `a17e9177`").**
  True of `fresh_default.log` (239 / 2, verified), but the recompute that rewrote `streams_access` and
  `streams_mapping_code` — the shipped access and mapping-code output — for **all 241** groups ran at
  `a17e9177`: `fresh_default.log_recompute` has 241 rows for the run_uid, every one `link_sha a17e9177`,
  `link_dirty f`. A reader told "239 groups stamp ee21eb13" will attribute those groups' access codes to
  ee21eb13. The difference is behaviourally nil outside UPET (the access fix only touches the all-NA case),
  but the provenance sentence should name both tables: modelling 239 `ee21eb13` + 2 `a17e9177`; recompute 241
  `a17e9177`.

- **[data-loss risk, prose] CLAUDE.md "Status (2026-10-12)" lead paragraph (left unchanged) vs the run.** That
  status records an operator decision not to rebuild KOTL, LARL and SLOC "because those three groups' published
  floodplains items come from the August build". The 241-group run replaced them: `fresh_default.log` now holds
  exactly one row per group, all from run_uid `20261017_004619-3f4c713b` (link 0.66.0), so the August rows and
  their data are gone from the schema, and so is DUNC's 2026-10-12 build. The only surviving copy I can find is
  `/tmp/fresh_default_pre_consolidate_202610162242.dump` (1.86 GB; `pg_restore -a -t log` shows the August
  LARL/KOTL/SLOC rows at link 0.45.1 and DUNC at 0.63.1). macOS clears `/tmp` on reboot and prunes it
  periodically. Nothing in planning/active or the research section mentions KOTL/LARL/SLOC or floodplains, so
  this looks unconsidered rather than decided (the "no stale rows can survive" note treats overwriting as a
  goal). Ask the operator; at minimum move the dump out of `/tmp` now, and mark the 2026-10-12 lead paragraph
  superseded too (it still says the neighbours "are August builds", which the DB contradicts) — only its first
  bullet was marked.

- **[minor, prose] CLAUDE.md "Status (2026-10-17)" lead ("`bcfishpass` parity ... passes 48/50 on the closure of
  ADMS, BULK, BABL and ELKR").** The closure (17 groups) was modelled, recomputed and compared; the 48/50 is
  `parity_crosssection.R ADMS BULK BABL ELKR`, which scores the four focal groups only ("17 pairs / 4 WSGs"
  for accessible, `parity_crosssection.log`). Say "on ADMS, BULK, BABL and ELKR (closure of 17 modelled)". The
  research section's wording has the same ambiguity, less strongly.

- **[minor, prose] CLAUDE.md #347 bullet, "it lost 18 finished groups that way".** They were not lost; they were
  counted as missing and recovered (`_consolidate_recover18.log`). The rest of the sentence says so; "missed"
  (as research step 5 has it) is the accurate verb.

## Code: verified clean

- `R/lnk_pipeline_pscis_build.R` xref insert: `DISTINCT ON (u.stream_crossing_id) ... ORDER BY
  u.stream_crossing_id, u.branch_rank` is valid and deterministic: `whse_fish.pscis_assessment_svw` is unique on
  `stream_crossing_id` (19,905 / 19,905) and the xref CSV has no duplicate ids (3,657 rows), so each branch
  yields at most one row per id and `branch_rank` breaks the only tie. Exactly two xref rows set both ids
  (203324 ATNA, 203838 KITR) — "both such rows" holds. KITR: modelled crossing 8501815 lies on lfid 84042066 in
  `fresh.modelled_stream_crossings`, so A and B are identical rows. ATNA: 1000400002 is absent, A drops it, B
  emits (lfid 3016659 is in ATNA, PSCIS 203324 exists, PASSABLE so no barrier row). `fresh_default.barriers` has
  exactly one 203838 row. The round-5 fix is right: bcfp 04_pscis.sql (`bcfishpass@f8db4b9`) is one INSERT over
  `referenced_combined` (UNION ALL), `ORDER BY linear_feature_id, downstream_route_measure, distance_to_stream
  ON CONFLICT DO NOTHING`, no branch precedence. Where A and B would disagree (crossing not on the xref lfid)
  link keeps A and bcfp keeps the lower lfid; the comment scopes the agreement claim to today's two rows, which
  is accurate.
- `R/lnk_pipeline_access.R:369`: correct for its case (the only way `blocked` is NA for a present species is the
  zero-row branch at :245). Both changed test files pass in a copy (15 / 38 expectations, 0 fail, 0 error,
  `NOT_CRAN=true`); deleting line 369 fails 2 expectations in the new test (mutation verified). The pscis test is
  string-matching only, which pins the SQL text, not behaviour; acceptable for this shape.

## Claims checked

| claim (where) | source | verdict |
|---|---|---|
| run_uid built 241 groups on m1 + 3 cloud hosts (CLAUDE.md) | `fresh_default.log` | ✓ 241 rows, hosts m1/job1/job2/job3 |
| verifiers pass at expected_n=241 | run_verify*.log | ✓ both PASS |
| one config_hash, fwapg, bcfishobs, bcfp pin | log | ✓ 1/1/1/1 |
| every group's newest log row from this run | log | ✓ 0 exceptions; 241 groups in log |
| `fresh` unchanged | fresh.log max date 2026-09-26, 0 rows for 20261017* | ✓ |
| 239 ee21eb13 / 2 a17e9177 (KITR, UPET, m1) | log | ✓ for `log`; ✗ incomplete, recompute 241 at a17e9177 (finding 4) |
| link_dirty FALSE on all 241 rows | log, log_recompute | ✓ |
| 18 groups missed, `done` mid-line after an R warning | run_job*.log | ✓ 18 mid-line markers; 2/12/4 split matches 47/50, 43/55, 55/60 |
| driver consolidates only what it counted, burns right after | study_area_run.sh:1287-1374 | ✓ `burn_cyphers \|\| true` directly after consolidate |
| #348: coverage gate exits before the recompute; stale earlier rows pass it | study_area_run.sh:1392-1407 | ✓ (rows-exist test, `exit 1`) |
| recompute 154 min, -j4, median 2.0, quartiles 1.1/3.2, longest 16, 597 summed | _recompute.log, log_recompute | ✓ 153.7 min; 2.00, 1.13/3.18, 16.24 (SETN), 596.96 |
| ~10 s/WSG was a 34-group figure (research) | research :87-88, 0a332cc0 | ✗ FINA one-group, #205 (finding 3) |
| present species, no barrier → access 1/2, has_barriers NA, mapping reads no data | DB, code | ✓ as stated; consequence is a blank mapping code (finding 1) |
| `fresh_default` 48 GB; 11 → 48 GB | pg_class sizes | ✗ 31 GB; 48 is an index double count (finding 2) |
| 11.39 M segments | streams | ✓ 11,388,157 |
| volume 600 GiB, 253 G free after run | df in fresh-db | ✓ 590G fs; 241G avail now after +12 G parity |
| DB 221 → 275 GB | not reproducible now (287 GB after parity) | plausible, unverified |
| modelling job1 171, job2 207, job3 277, m1 ~225 min | log date_start/date_end per host | ✓ 170.8 / 207.3 / 277.0 / 224.8 |
| slowest cloud host finished 52 min after m1 | log | ✓ 05:42:44 vs 04:50:26 |
| KITR/UPET re-run on m1, 8.4 min | log | ✓ 06:40–06:49 UTC |
| consolidate 46 min (3 hosts) | _consolidate.log | ≈ 45 min (22:42:46–23:27:26 PDT); within a minute |
| wall clock 8 h 48 m incl. ~30 min pause | run.started, run.log, timestamps | ✓ 00:46→09:34 UTC; pause ≈ 23–29 min |
| 3 × ~6 h ≈ $4.50 at $0.25/h | up logs (s-8vcpu-32gb-amd), research :307 | ✓ arithmetic; hours approximate |
| planned ~4.7 h, ~1 h, ~6 h, ~$3, ~+65 GB | findings.md "Planning", "Disk" | ✓ |
| parity run 17 groups, 48/50, BULK SK parked | parity_crosssection.log, fresh_parity246.log | ✓ 17 log rows at a17e9177; 48/50 is over the 4 focal groups (finding 6) |
| "parity at the same code" | fresh_parity246.log | ≈ a17e9177 = the run's recompute SHA; modelling differs only by the two fixes |
| #257 closed; #347, #348 open; #250 closed; fresh#190 parked | gh | ✓ |
| KITR xref sets both ids; ATNA modelled crossing absent, only B emits | CSV, fresh.modelled_stream_crossings, FWA | ✓ |
| bcfp: one INSERT, ON CONFLICT DO NOTHING, no precedence | bcfishpass 04_pscis.sql @f8db4b9 | ✓ |
| equal packing "was right" (research) vs "right in direction" (findings) | findings | judgement; research drops the qualifier (makespan 4.6 h exceeded the pilot's 3.5–4.4 h range) |
| record at planning/archive/2026-10-issue-246-…/ | filesystem | not yet created; `/planning-archive` box unchecked — make sure the archive name matches |

/Users/airvine/Projects/repo/link/planning/active/review-round6.md
