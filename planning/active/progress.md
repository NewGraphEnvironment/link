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
