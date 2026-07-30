# Progress — Rename dimensions_columns.csv → dictionary_dimensions.csv; add dictionary_parameters_fresh.csv (#233)

## Session 2026-07-29

- Filed #233 after tracing the `observation_control_apply` question back to the fresh↔link column-ownership boundary
- Plan-mode exploration — phases approved by user
- Recovered stale local `main` (38 commits behind): backed up 96 colliding untracked `data-raw/logs/` files to `data-raw/logs/_local_pre_pull_20260729/` (byte-identity verified) before fast-forwarding to `b9f6285` / v0.44.2
- Re-verified all plan targets against the 38 upstream commits — `dimensions_columns.csv`, `audit_configs.R`, `RUNBOOK.md` untouched. Adjusted `CLAUDE.md:238` → `:256` and bump target `0.43.1` → `0.44.3`
- Created branch `233-rename-dimensions-columns-csv-dictionary` off updated main
- Scaffolded PWF baseline from issue #233 with approved phases
- Next: Phase 1 — `git mv` the dictionary + repair `CLAUDE.md:256`

## Session 2026-07-30

- **Phase 1 complete** — `git mv` to `dictionary_dimensions.csv`, `CLAUDE.md:256` repaired
- Sweep verified: only `NEWS.md:421` + archived findings retain the old name (both historical by design). No indirect/glob reference — `audit_configs.R:205` globs only `overrides/`, never the configs root
- Installed `fresh` v0.32.0 from local repo (was 0.31.0, below link's `fresh (>= 0.32.0)` pin) — cleared a spurious `frs_wsg_drainage` export error
- Test suite: 1294 PASS, 1 FAIL. The failure (`test-lnk_wsg_resolve.R:138`) is missing DB table `public.wsg_outlet`, whose builder is open follow-up #227 — pre-existing, unrelated to the rename
- Next: Phase 2 — write the failing dictionary/schema contract test
- **Phase 2 complete** — `tests/testthat/test-dictionaries.R` written as the failing contract: 6 FAIL / 9 PASS. All 6 failures are `dictionary_parameters_fresh.csv` assertions (file lands in Phase 3); the dimensions side already passes
- Discovered bundles carry different column subsets — bcfishpass `dimensions.csv` has 30 columns, the three `default*` bundles have 32. Coverage is therefore asserted against the union across bundles, with a per-bundle subset check. Existing `dictionary_dimensions.csv` (32 rows) already covers the union exactly, no orphans
- Confirmed the ownership partition is exact: fresh canonical = 14 columns, link bundles = those 14 + exactly the 5 `observation_*`, zero fresh-not-link gap
- Self-review caught two precision defects in the new test before commit: `nzchar(NA)` is `TRUE` so bare non-empty checks would wave through an NA cell (added `filled()`), and the owner assertion used `expect_setequal` where a domain check was meant (conflated two failure modes)
- `lintr::lint()` clean on the new file
- Next: Phase 3 — author `dictionary_parameters_fresh.csv` (19 rows) and turn the 6 red assertions green
- **Phase 3 complete** — `inst/extdata/configs/dictionary_parameters_fresh.csv` authored, 19 rows. Contract tests 23 PASS / 0 FAIL; full suite 1317 PASS (up 23), same lone pre-existing #227 failure
- Every `consumed_by` reference machine-verified against the actual source line via a throwaway resolver script — 24/24 resolve. Two were off by 1-2 lines in the first draft (`frs_habitat.R:1159` was blank; `frs_habitat_classify.R:168` pointed at `species_code` not `access_gradient_max`) and were corrected rather than left approximate
- Ownership recorded as fact, not inference: 14 fresh-owned, 5 link-owned (`observation_*`)
- Notable content captured: `cluster_spawn_bridge_distance` is overridden by `connected_distance_max` in rules.yaml when present (the YAML wins, the column is only a fallback); `rear_gradient_min` is the sole orphan of the 19
- Next: Phase 4 — rewire `audit_configs.R` section 3b to read `owner` from the dictionary
- **Phase 4 complete** — `audit_configs.R` section 3b now reads ownership from `dictionary_parameters_fresh.csv` instead of prefix-matching `^observation_`. Adding a link-owned column is now a dictionary edit, not a regex edit
- Three guards where there was one: undocumented-column coverage, a reverse check (dictionary claims link-owned but fresh ships it = stale dictionary), and a missing/malformed-dictionary guard that flags instead of erroring mid-run
- Negative-tested: dropping one dictionary row makes the audit exit 1 and fire both flags; restored byte-identical to HEAD. A guard that has never failed is not a verified guard
- Lint parity held (13 before, 13 after) after restructuring an alignment check that had added one `indentation_linter`
- Next: Phase 5 — RUNBOOK section 7 ownership row, NEWS, version bump
- **Phase 5 complete** — `RUNBOOK.md` section 7 gains a dictionary row plus a "Who owns which parameters_fresh column" subsection: the 14/5 split, fresh#129 as the deciding issue, both enforcement points, and the opposite directions of travel (`rules.yaml` link->fresh, column schema fresh->link). `rear_gradient_min` added to the "gaps worth knowing" list (now three)
- `NEWS.md` entry written; version bumped 0.44.2 -> 0.44.3 as the final commit
- Final validation: 1317 PASS / 1 pre-existing FAIL (#227), audit exits 0 with no findings, both touched files lint-clean, old-name sweep clean
- Next: `/planning-archive`, then `/gh-pr-push`
