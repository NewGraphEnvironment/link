# Findings — csv-sync rewrite to read from s3://fresh-bc/bcfishpass/ (#117)

## Issue context

Issue #117 in NewGraphEnvironment/link. Title: "csv-sync: switch to weekly cadence SHA-pinned to tunnel rebuild for comparison stability."

Daily csv-sync produced 1–7 days of drift between bundle CSVs and the tunnel's rebuild SHA. 8 stale daily PRs (#85, #91, #100, #111, #116, #125, #136, #141). Re-scoped 2026-05-07 to consume the s3://fresh-bc/bcfishpass/ artifacts dropped weekly by NewGraphEnvironment/db_newgraph PR #5.

Issue body was edited 2026-05-07 to reflect the new architecture + automation pattern (weekly drift-monitor with crate schema-validate gate, auto-merge clean / halt on shape drift).

## Architecture

```
  Wed 12:00 UTC  NGE/db_newgraph dump-bcfishpass-csvs.yml
                 -> s3://fresh-bc/bcfishpass/log.json
                 -> s3://fresh-bc/bcfishpass/csvs/<17 files>

  Wed 14:00 UTC  NGE/link sync-bcfishpass-csvs.yml
                 -> lnk_bucket_log() / lnk_bucket_get() pull artifacts
                 -> diff vs bundle CSVs
                 -> crt_schema_validate gate (when canonical_schema declared)
                 -> on drift: lnk_baseline_append(log, "csv-sync-<date>")
                              update inst/extdata/configs/ provenance YAML
                              open PR (auto-merge byte; halt + label shape)
```

## Existing primitives (kept)

- `crate::crt_schema_read()` + `crate::crt_schema_validate()` — schema gate.
- `update_provenance_in_yaml()` — internal to sync_bcfishpass_csvs.R, walks YAML lines preserving comments.
- `sha256_text()` + `shape_fingerprint()` — internal byte/shape checksums.
- `is_bcfp_sourced(entry)` — filter against `source: https://github.com/smnorris/bcfishpass`.
- `%||%` — coalesce.
- Existing workflow byte/shape gate (auto-merge byte; halt + `schema-drift` label on shape) — unchanged shell logic in sync-bcfishpass-csvs.yml.

## New `lnk_*` exports — naming rationale

- `lnk_bucket_*` — generalizes to any prefix/build (not bcfp-specific). Format-agnostic via raw-bytes return; future parquet support is caller-side decoding only.
- `lnk_baseline_*` — generalizes to multiple ledger paths as needed. `lnk_baseline_append()` validates ledger column shape on append.

## Cross-refs

- NewGraphEnvironment/db_newgraph#4 + PR #5 — upstream dump that populates s3://fresh-bc/bcfishpass/. Manual workflow_dispatch validated 2026-05-07 (model_version=v0.7.14-125-g6e9cf1c, head_sha=6e9cf1c928ac01aae7e3aa5789ac9c29957e847b).
- link#137, link#138 — companion self-sufficiency issues; same drift-monitor pattern; will follow this rewrite.
- link#64 (closed) — original byte/shape distinction.

## Deferred (out of scope here; revisit later)

- Ledger file rename (`bcfp_baselines.csv` → `baselines.csv` / `runs.csv`).
- `source_type` column in the ledger.
- Format-agnostic `lnk_bucket_read()` sugar that returns a tibble.
- `--strict` mode in csv-sync that halts on shape drift.

## Bucket state at session start

```
$ aws s3 ls s3://fresh-bc/bcfishpass/
                           PRE csvs/
2026-05-07 10:56:14        198 log.json

$ aws s3 cp s3://fresh-bc/bcfishpass/log.json -
{"model_version":"v0.7.14-125-g6e9cf1c","date_completed":"2026-05-06T04:15:41Z","head_sha":"6e9cf1c928ac01aae7e3aa5789ac9c29957e847b","source":"smnorris/bcfishpass:ng-prod.yaml run metadata"}

$ aws s3 ls s3://fresh-bc/bcfishpass/csvs/ | wc -l
17
```

bucket auto-refreshes Wed 12:00 UTC + dispatchable. Path 2 (no DB tunnel; `head_sha` is full 40-char SHA, no `model_run_id`).
