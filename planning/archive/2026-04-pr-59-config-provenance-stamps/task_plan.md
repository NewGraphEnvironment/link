# Task: Config provenance + run stamps (link#40, supersedes #24)

Pipeline outputs drift silently when underlying inputs change — CSV
syncs, fwapg refreshes, bcfishobs updates. Without a stamp of all inputs
at run time, "what changed?" is unanswerable. On 2026-04-22 a 0.4 pp
shift in BT rearing diff vs bcfishpass looked like a refactor regression
but turned out to be entirely from env state changes between runs. This
PR closes the loop: every config CSV carries provenance; every pipeline
run emits a stamp; drift between any two runs is diffable from their
stamps alone.

## Goal

Two layers, one PR:

1. **Config-bundle provenance (at rest)** — `provenance:` block in each
   `config.yaml` per tracked file. `lnk_config()` exposes
   `cfg$provenance`. New `lnk_config_verify()` recomputes checksums and
   reports drift.

2. **Run stamps (at run)** — new `lnk_stamp()` returns a structured list
   merging `cfg$provenance` with software versions, git SHAs, DB
   snapshot hashes, AOI + schema + start/end timestamps. Markdown
   rendering is one of multiple output formats (covers #24's appendix
   scope).

## Phases

- [x] Phase 1 — PWF baseline (task_plan, findings, progress)
- [x] Phase 2 — `provenance:` block in both bundle configs (12 files each, sha256 checksums)
- [x] Phase 3 — `lnk_config()` parses provenance, exposes `cfg$provenance`, print shows count
- [x] Phase 4 — `lnk_config_verify(cfg, strict)` returns drift tibble (5 columns), warns/errors on drift
- [x] Phase 5 — `lnk_stamp(cfg, conn, aoi, db_snapshot)` + `lnk_stamp_finish()` + `format.lnk_stamp()` markdown/text + `print.lnk_stamp()`. 3-tier git-sha fallback (env → .git → NA). DB snapshot scoped to bcfishobs + fwa_streams row counts.
- [x] Phase 6 — 93 new tests covering provenance parsing, drift detection, stamp shape, markdown render, finalization. Bundled configs assert drift = 0 in shipped state.
- [x] Phase 7 — Wired `lnk_stamp()` into `compare_bcfishpass_wsg.R` head — markdown dump precedes pipeline phases
- [x] Phase 8 — `/code-check` round 1: 1 fragile finding (`.lnk_read_git_head` could crash on empty `.git/HEAD`); fixed
- [x] Phase 9 — Full suite: 453 PASS, 0 FAIL, 1 pre-existing WARN
- [x] Phase 10 — NEWS 0.11.0 entry + DESCRIPTION 0.10.0 → 0.11.0
- [ ] Phase 11 — PR

## Critical files

- `inst/extdata/configs/bcfishpass/config.yaml` — add `provenance:` block
- `inst/extdata/configs/default/config.yaml` — add `provenance:` block
- `R/lnk_config.R` — parse provenance, expose, doc
- `R/lnk_config_verify.R` — new file
- `R/lnk_stamp.R` — new file
- `data-raw/compare_bcfishpass_wsg.R` — emit stamp at top of each WSG run log
- `tests/testthat/test-lnk_config.R` — extend
- `tests/testthat/test-lnk_stamp.R` — new file
- `NEWS.md` — 0.11.0 entry
- `DESCRIPTION` — version bump

## Acceptance

- `cfg <- lnk_config("bcfishpass"); cfg$provenance` is a named list with one entry per tracked file
- `lnk_config_verify(cfg)` returns a tibble of file checksums; current state has no drift
- `stamp <- lnk_stamp(cfg)` returns an `lnk_stamp` S3 list with provenance + software versions + (optional) DB snapshots
- `as.character(as.markdown(stamp))` returns a markdown string suitable for report appendix (covers #24)
- `data-raw/compare_bcfishpass_wsg.R` log output starts with a stamp dump
- Two runs of `targets::tar_make()` on the same DB state produce stamps with identical provenance + DB snapshot hashes (different timestamps + elapsed only)

## Risks

- **DB snapshot scope creep** — bcfishobs/fwapg row counts are cheap; per-table relfilenode lookups are deeper. Keep snapshot to a small fixed list (`bcfishobs.observations`, `fwa_stream_networks_sp`, `bcfishpass.streams_habitat_linear` if reachable). Add more later if drift attribution requires it.
- **git SHA discovery in package context** — `system("git rev-parse HEAD")` doesn't work when link is installed via `R CMD INSTALL` (no .git in install dir). Fall back to `packageVersion()` or env var `LINK_GIT_SHA`. Document in lnk_stamp() doc.
- **Provenance backfill quality** — bcfishpass `ea3c5d8` SHA + 2026-04-13 sync date are best estimates from research doc; checksums computed at write time, so subsequent edits to a tracked CSV will show as drift. That's the feature.

## Not in this PR

- CSV auto-sync from upstream (cron/maintenance, not library work)
- Full diff-viewer tool — capturing the data is the immediate goal; diffing two stamps is a later concern
- Wiring stamp into `_targets.R` rollup target (`(diff_tibble, stamp)` return from `compare_bcfishpass_wsg()`) — feeds PR 2 of #38, but not strictly required for the stamp itself; can be a follow-up PR

## Cross-refs

- Closes #40
- Supersedes narrow scope of #24 (report-appendix → one rendering of the broader stamp)
- Feeds future PR 2 of #38 (`tar_read(rollup)` carries lineage)
