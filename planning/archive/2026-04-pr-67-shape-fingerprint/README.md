# PR #67 — v0.13.0 shape fingerprint + halt auto-merge on shape drift

**Outcome:** the daily bcfishpass CSV sync workflow now distinguishes
byte drift (rows added/edited/removed, header preserved) from shape
drift (column rename / add / remove / reshape). Byte-only drift
auto-merges as before; shape drift opens a labelled PR and halts on
red without auto-merging, surfacing the change for coordinated review
across link / fresh / crate.

**Mechanism:** new `shape_checksum` field in `provenance:` blocks
(sha256 of normalized header line). `lnk_config_verify()` returns an
8-col tibble (byte + shape × expected/observed/drift, plus file +
missing). `data-raw/sync_bcfishpass_csvs.R` writes overall drift kind
(none/byte/shape) to `/tmp/sync_drift_kind`; workflow branches.

**Closes:** #64. Coordinates with crate#2 + link#65 (canonicalize-at-
ingest pattern) — when shape drift fires, the right next move is
crate's normalize handler absorbing the change before link's pipeline
sees it.

**Closing commit:** `46b60f0` (merge of PR #67)
**Tag:** `v0.13.0`
