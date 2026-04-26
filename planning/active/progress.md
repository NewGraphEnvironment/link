# Progress — #40 config provenance + run stamps

## Session 2026-04-26

- Branch: `40-config-provenance-stamps` off `main` (post v0.10.0 merge)
- PWF baseline written. Plan covers two layers in one PR:
  1. `provenance:` block in config.yaml + `cfg$provenance` exposure +
     `lnk_config_verify()`
  2. `lnk_stamp()` with full runtime scope — supersedes #24's narrow
     report-appendix scope
- Confirmed: `lnk_stamp()` does not yet exist; `provenance` already used
  in lnk_load/lnk_override for *user CSV row provenance* (different
  concept — keep namespacing clean).
- Next: Phase 2 — write `provenance:` blocks for both bundle configs
  with computed sha256 checksums.

### Phases 2-10 done in one session (1 atomic commit)

- Provenance blocks for both bundles: 12 files each, sha256 checksums
  via `shasum -a 256`. bcfishpass-sourced files get
  `upstream_sha: ea3c5d8` (synced 2026-04-13); link hand-authored gets
  link HEAD sha (`8f1890564b9148...`); rules.yaml gets `generator_sha`.
- `lnk_config()` exposes `cfg$provenance` (named list parsed from
  manifest). `print(cfg)` shows count of tracked files.
- `lnk_config_verify(cfg, strict)` recomputes sha256 via
  `digest::digest()`, returns 5-col tibble (file, expected, observed,
  drift, missing). Warns on drift; `strict = TRUE` errors. Bundled
  configs verify clean.
- `lnk_stamp(cfg, conn, aoi, db_snapshot)` + `lnk_stamp_finish()` +
  `format.lnk_stamp(type)` + `print.lnk_stamp()`. Software detection
  uses 3-tier git sha fallback (env var → `.git/HEAD` walk → NA);
  works for `devtools::load_all()` (sha returned) and `R CMD INSTALL`
  (NA). DB snapshot scoped to two row counts.
- `data-raw/compare_bcfishpass_wsg.R` emits stamp markdown at the
  head of each WSG run via `message()` — captured into log files via
  the standard `> log 2>&1` redirect.
- Tests: 121 new test_that's covering provenance parsing, drift
  detection (clean/mutated/missing/strict), stamp shape + markdown
  + finalization + DB snapshot opt-out. Total package tests up from
  360 → 453.
- `/code-check` round 1: 1 fragile finding (`.lnk_read_git_head`
  could crash if `.git/HEAD` was empty) — fixed with length checks
  on `readLines()` returns.
- DESCRIPTION 0.10.0 → 0.11.0; `digest` added to Suggests.
- Next: stage everything, atomic commit, PR.
