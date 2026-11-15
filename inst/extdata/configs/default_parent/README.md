# default_parent config

The `default` bundle classified on each full segment's minimal parent's gradient (`grad-parent`). It is a **thin** bundle: `config.yaml` declares `extends: default` and overrides two `pipeline:` keys.

| Key | Value | Role |
|---|---|---|
| `schema` | `fresh_default_parent` | Persist schema, beside `fresh_default` and `fresh_default_minimal` |
| `gradient` | `source: parent`, `minimal_config: default_minimal`, `schema_full: fresh_default` | Classify on the gradient of the `default_minimal` segment each segment lies in, read from `fresh_default.streams_parent` |

Its tokens are `default`'s except for the gradient: `cut-full-top acc-v5 grad-parent q-fwapg`.

## Why

A habitat rule tuned on the minimal network reads, there, the gradient of a long segment cut only where access changes. On the full network the same place is cut at fish records and crossings, so each piece has a gradient of its own and the tuned rule reads a different number. This bundle keeps the full network's segments (so access, mapping codes and the habitat overlay read as `default`'s) and gives each one its parent's gradient, so the tuned rule reads what it was tuned on.

## What it needs, and what it refuses

It reads `fresh_default.streams_parent`, which `data-raw/streams_parent_build.R` writes after both `fresh_default` and `fresh_default_minimal` are built, so it runs only on the host holding all three (the dispatcher). For each group it refuses, before its log row opens, unless the group's newest builds in both schemas are closed and clean, on one fresh, with the same species and the tokens a parent reading needs, and unless the parent rows were joined from exactly those builds. After break it refuses unless it cut exactly the segments `fresh_default` holds (same line, start and end within 1 mm, one to one). A re-model of either network voids the table until it is rebuilt (RUNBOOK §6b, "Parent attributes").

The persisted `gradient` is the parent's, the value classify read; the segment's own is at the same position in `fresh_default.streams`. The log row's `notes` name the two runs the parents came from.

## Running it

```bash
LNK_SCHEMA=fresh_default_parent Rscript data-raw/wsg_run_one.R BULK default_parent
```
