# Code-check round 1 — #246 driver fixes (cc_round1.diff)

Reviewer: subagent, 2026-10-16. Scope: data-raw/study_area_run.sh, data-raw/cypher_prep.sh,
data-raw/study_area_buckets.R, data-raw/parity_crosssection.R, and what they call.

## Verdict: Clean (no blocking defects)

There are no bugs or security issues. One low-severity fragility is noted below. It is not
blocking.

## What was checked, and how

- **bash >= 4 guard (study_area_run.sh:99-102).** I copied lines 1-104 to scratch and ran them.
  `/bin/bash` (3.2.57) gives the FATAL line and rc=1. `sh` (bash 3.2 in posix mode) also gives
  FATAL and rc=1. `/opt/homebrew/bin/bash` gets past the guard with rc=0. Nothing above the guard
  is bash-4 syntax: it is comments plus `set -euo pipefail`. `BASH_VERSINFO` is always set in bash,
  so `set -u` cannot trip on it. `bash -n` passes on both shell scripts. Side effect: under 3.2,
  `--preflight-only` used to run, because it exits before the first `declare -A` (line 927). It is
  now refused. That is a behaviour change, not a defect, and no caller depends on it: grep found
  no script or test that invokes the driver.
- **Bucket resolve with `LNK_LOAD=loadall ... "$CONFIG"` (lines 924, 930).** I ran
  `LNK_LOAD=loadall Rscript data-raw/study_area_wsgs.R ADMS default`. Stdout is the comma line
  alone, `LFRA,HARR,FRCN,THOM,STHM,ADMS \n`. The only stderr output is a read.table
  incomplete-final-line warning, which `$(...)` does not capture, so `tr -d '[:space:]'` gets a
  clean bucket. A failing resolve still aborts: the script `stop()`s, and the plain assignment
  fails under `set -e`. The local run leg also uses `LNK_LOAD=loadall` (line 1053), so the bucket
  and the dispatcher's runs come from the same code.
- **cypher_prep.sh R block (single-quoted `Rscript -e '...'`).** I extracted the block (21 lines).
  It contains zero `'` characters, so the shell quoting is intact, and `parse()` succeeds. With
  `CYPHER_PREP_CONFIG=default CYPHER_PREP_SCHEMA=zz_review_probe`, the override resolves
  `.lnk_table_names(cfg)$schema` to `zz_review_probe` and `cfg$species` to the 11 species of
  `default`. `lnk_pipeline_run` calls `lnk_persist_init(conn, cfg, species = cfg$species)`
  (R/lnk_pipeline_run.R:211), so the column sets match across hosts. An unset
  `CYPHER_PREP_CONFIG` falls back to bcfishpass. That is what the two other callers get, because
  neither passes it: wsgs_run_pipeline.sh:287 and the --auto-install re-prep at
  study_area_run.sh:846. The re-prep also stops before persist_init, so the fallback cannot reach
  it. An empty `CYPHER_PREP_SCHEMA` keeps the config's schema, because of the `nzchar` test.
- **force_recreate on a non-default schema.** `.lnk_validate_persist_table()` drops a table only
  when it carries `GENERATED ALWAYS` columns. It never drops a table that is merely populated.
  cypher_prep runs only on cyphers, and the dispatcher is never touched. The cypher's stale
  `fresh.*` tables are now left alone when the run writes `fresh_default`. That is harmless,
  because nothing in a `--schema=` run writes the `fresh` persist tables: wsg_run_one.R honours
  `LNK_SCHEMA`.
- **ssh keepalives (line 1079).** The `-o` options come before the host, which is correct. With
  ServerAliveInterval=60 and CountMax=10, ssh gives up after about 10 minutes without a response,
  which is close to Linux's own TCP retransmit give-up of about 15 minutes. A dropped host still
  shows up as `WARN` and narrows the consolidate bucket, as before.
- **parity_crosssection.R.** `lnk_rollup_wsg()` is an aggregate with `GROUP BY` over an inner join,
  so a group missing from the schema returns 0 rows and the `!nrow(lk)` guard can fire. Exit
  semantics:
  - Every group absent now gives exit 1 ("no parity rows at all"). Before this change it crashed
    in `tab[...]` on a NULL `tab`, which was also exit 1.
  - Some groups absent now adds to `n_fail` and gives exit 1. Before, it could PASS with the
    missing groups listed as "link-absent".

  The `lnk_parity_annotate()` input carries every required column (`wsg`, `species`,
  `habitat_type`, `link_value`, `ref_value`, `diff_pct`). Species are uppercase and the metric
  names are the taxonomy's vocabulary. Both persist schemas hold all 8 `streams_habitat_<sp>`
  tables the sweep joins (checked read-only on :5432). The FINA structural SQL takes the schema
  twice per query, and the argument order matches its `%s` / `%d` / `%f` placeholders.
- **study_area_buckets.R.** `fresh::frs_wsg_outlets()` is a data.frame with 246 rows, a
  `watershed_group_code` column and no duplicates, so `setequal()` is well defined.
  `length(flat)` is the modelable count. The launch-command line
  `--config=%s --schema=<persist schema>` is read by nothing: grep found no parser of
  study_areas.md. If it is pasted verbatim, `<persist` is parsed as a redirection, so it fails as
  a shell syntax error and runs nothing.

## Findings

- **[severity: fragile, low, pre-existing pattern extended]** data-raw/study_area_run.sh:1012 and
  1079 interpolate `$SCHEMA` and `$CONFIG` inside `'...'` in the ssh command string. Only
  `--run-label=` has a charset check (lines 183-198), and that check exists for exactly this
  reason. `--schema=` and `--config=` have none. A value containing `'` would end the quote and
  the remote shell would re-parse the rest. The diff adds two more such sites:
  `CYPHER_PREP_CONFIG` and `CYPHER_PREP_SCHEMA` in the prep ssh. This is operator input, not a
  trust boundary, and the run leg at 1079 already had the same exposure. A one-line `case` like
  RUN_LABEL's, for example `[a-z0-9_]` for the schema (lnk_rollup_wsg already requires
  `^[a-z_][a-z0-9_]*$`), would close it. Not blocking.
- **[severity: fragile, low]** data-raw/parity_crosssection.R:47 uses
  `Sys.getenv("LNK_SCHEMA", "fresh")`, which treats a set-but-empty `LNK_SCHEMA` as `""`, not as
  unset. wsg_run_one.R and wsg_recompute_one.R test it with `nzchar()` instead. With an empty
  value, `lnk_rollup_wsg()`'s `stopifnot(grepl(...))` errors with a loud, unhelpful message, not
  a silent wrong answer. study_area_run.sh always exports a non-empty value. Not blocking.

No bugs. No security issues.
