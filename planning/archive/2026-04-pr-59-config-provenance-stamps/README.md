# PR #59 — v0.11.0 config provenance + run stamps

**Outcome:** every bundled config (`bcfishpass`, `default`) now carries
sha256 checksums + source/upstream-sha/synced metadata for 12 tracked
files. `lnk_config()` exposes parsed provenance as `cfg$provenance`.
New `lnk_config_verify(cfg, strict)` reports drift; new `lnk_stamp()`
captures provenance + software versions + git SHAs + DB snapshot row
counts + AOI + timestamps; new `lnk_stamp_finish()` finalizes;
`format(stamp, "markdown")` renders. `data-raw/compare_bcfishpass_wsg.R`
emits stamp markdown at the head of every WSG run log.

**Closes:** #40 (drift attribution loop). Supersedes the narrow
report-appendix scope of #24 — markdown rendering covers that consumer.

**Verification:** 453 tests pass (121 new). Code-check round 1 found 1
fragile edge case (empty `.git/HEAD` could crash `.lnk_read_git_head`),
fixed before merge. Bundled configs verify clean (drift = 0) in shipped
state.

**Closing commit:** `9354f99` (merge of PR #59)
**Tag:** `v0.11.0`
