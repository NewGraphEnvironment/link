# Findings — Record source-artifact identity for the DB primitives (#265)

## Issue context

## Problem

We load the FWA primitives from a **versioned** object store, and we record
nothing that identifies which version we got. The store **will not let us ask
later** — so every version-id we fail to record at load time is gone, not merely
inconvenient to find.

`fwapg_sha` pins neither the data nor, it turns out, the loader's commit (see
"Measured 2026-10-12" below). `fwa_stream_networks_sp`
is, by `R/lnk_log.R`'s own comment, "the most load-bearing input the pipeline
has", and nothing records the bytes it was built from.

## Measured 2026-09-01

`fwapg/load.sh:37` pulls from
`https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_$table.parquet`. A plain
anonymous `HEAD` on `fwa_lakes_poly.parquet`:

```
HTTP/1.1 200 OK
Server: ViPR/1.0
x-amz-version-id: 1776306159523
ETag: "da5ba121842036c6f494a1eef0ac41f4-18"
Last-Modified: Thu, 16 Apr 2026 02:22:39 GMT
x-emc-mtime: 1776306159523
Content-Length: 149526772
```

BC gov's ECS store, S3-compatible, **versioning on**. Three independent identity
handles for free on every object.

| capability | result |
|---|---|
| per-object version id | ✅ `x-amz-version-id` |
| content hash | ✅ `ETag` (md5, or `<hash>-<nparts>` when multipart) |
| vintage | ✅ `Last-Modified` — the real load-source date |
| **re-fetch an exact version** | ✅ `?versionId=1776306159523` → 200, same ETag |
| list version history (`?versions`) | ❌ `AccessDenied` |
| list the prefix (`?list-type=2`) | ❌ `AccessDenied` |
| a manifest, like bcfp's `log.json` | ❌ 404 |

### The asymmetry that sets the deadline

**`?versionId=` works. `?versions` does not.** We can re-fetch a version we can
name, and we can never enumerate the ones we did not record. So the bucket will
not tell us, in six months, which version was current on 2026-04-16.

This is link#262's argument one layer down — provenance that cannot be
retrofitted — and it is why this is time-sensitive rather than tidy-up. It is
also a concrete instance of the GetObject-vs-ListBucket split already recorded in
`CLAUDE.md` under "Public bucket ≠ listable".

## Measured 2026-10-12: `fwapg_sha` does not pin the loader's commit either

`.lnk_fwapg_sha()` reads the HEAD of the local fwapg checkout **when the model
runs**, not the commit that ran `load.sh`. So it moves on any fwapg commit, even
when nothing was reloaded. From `fresh_default.log`:

| WSG | run | `fwapg_sha` | that commit |
|---|---|---|---|
| PINE, LARL, KOTL, SLOC | 2026-08-06 / 08-27 | `e6e1eb0` | 2026-04-17, "wrap all sql files in begin, commit…" |
| DUNC | 2026-10-12 (link#328) | `f9718cb` | 2026-10-11, "CLAUDE.md: no workflow runs on a newgraph merge" |

70 fwapg commits apart, and the only `load.sh` change between them is the
watershed-groups read moving from `/vsis3/` to `/vsicurl/`. The data did not
change: the six FWA tables that both KOTL's and DUNC's `log_input` rows record
(`fwa_stream_networks_sp`, `_channel_width`, `_order_parent`, lakes, rivers,
wetlands) have identical row counts and `size_bytes`.

So the fwapg commit belongs in the load-time record this issue proposes, captured
when `load.sh` runs, beside each artifact's version id.
The `.lnk_fwapg_sha()` roxygen (`R/lnk_log.R:1181`) and `lnk_stamp()`'s
`fwapg_sha` line say "the checkout that loaded the FWA primitives"; correct both
in the same change. Leave the values already logged alone; they are what the
column has always recorded.

Until then, compare `<schema>.log_input` fingerprints, not `fwapg_sha`, to tell
whether two runs read the same FWA data.

## Proposal

A table recording the artifact behind each primitive, with the **strength of the
evidence recorded alongside it** rather than inferred:

```sql
CREATE TABLE IF NOT EXISTS fresh.log_source_artifact (
  host            text        NOT NULL,
  table_name      text        NOT NULL,
  url             text        NOT NULL,
  version_id      text,
  etag            text,
  last_modified   timestamptz,
  n_rows          bigint,
  loaded_at       timestamptz,
  recorded_at     timestamptz NOT NULL,
  recorded_by     text        NOT NULL,   -- 'loader' | 'probe'
  PRIMARY KEY (host, table_name, url)
);
```

`recorded_by` is the load-bearing column and the reason this can ship before the
loaders change:

- **`loader`** — written by the thing that did the load. A record.
- **`probe`** — written by a `HEAD` after the fact. Says "this version is current
  now", **not** "this is what was loaded". Weaker, and labelled weaker.

Omitting the weaker case would leave the hole; recording it unlabelled would
overstate it. Same pattern as `bcfp_pin_source`, which landed in link#262 for
exactly this reason.

### Scope — REVISED 2026-09-01, the first version was wrong

The original plan said: probe the FWA **whole-table** artifacts, leave the
per-WSG split for later. Measured against the bucket, that covers **3 of 7** and
misses the most important table.

| primitive | whole `.parquet` | per-WSG | `.csv.gz` | reality |
|---|---|---|---|---|
| `fwa_stream_networks_sp` | 404 | **200** | — | per-WSG only, ~250 objects |
| `fwa_stream_networks_channel_width` | 404 | 404 | **200** | different format |
| `fwa_stream_networks_order_parent` | 404 | 404 | 404 | **derived in-DB** — `load/fwa_stream_networks_order_parent.sql` |
| `fwa_lakes_poly` | **200** | 404 | — | |
| `fwa_wetlands_poly` | **200** | 404 | — | |
| `fwa_rivers_poly` | **200** | 404 | — | |
| `fwa_obstacles_sp` | 404 | 404 | 404 | **not loaded by fwapg at all** |

`fwapg/load.sh` has **five URL templates across seven fetch sites** (measured
2026-09-01 — the two extra sites are the watershed-group discovery calls at
`load.sh:41` and `load.sh:132`). So there is no convention link can follow: to
probe, link would have to reimplement load.sh's dispatch — a second list that
silently drifts from the first, which is the failure mode this repo has a rule
about.

**CORRECTION 2026-09-01 — this section previously concluded the fork decision
was on the critical path. It is not.** The claim was *"only the loader knows the
URL it constructed"*. Measured: `load.sh:2` is `set -euxo pipefail`, so the
loader **already traces every fully-expanded URL to stderr** — including all
~250 per-WSG `fwa_stream_networks_sp/$WSG.parquet` fetches. `./load.sh 2>
run.log` is therefore a complete, ordered, **zero-code-change** record of every
object fetched.

That moves the fork trade off the critical path and back to being a later
refinement: a capture wrapper needs no patch to `load.sh`, no fork divergence,
and no upstream PR. Tracked as the capture-the-loader's-stderr issue.

Two supporting facts, so the reasoning is not re-derived:

- **The watershed-group list is not a repo file.** `load.sh:40-43` obtains it by
  running an OGR SQL query *against the remote parquet* (`select distinct
  watershed_group_code from fwa_watershed_groups_poly`). The object store is the
  authority, so any link-side reimplementation drifts from it by construction —
  which is the real reason probing cannot substitute for the loader, independent
  of the conclusion corrected above.
- **`load.sh` has no provenance hook to reuse.** `fwapg.db_version`
  (`db/migrate.sh:33-42`) records schema-migration tags only, and `load.sh`
  never touches it.

Two further findings the schema must accommodate:

- **`order_parent` is derived, not downloaded.** A NULL artifact there is correct
  and permanent. The schema needs to distinguish *derived* from *unrecorded*, or
  it reads as a gap forever. Suggest a `kind` column (`downloaded` | `derived`).
- **`obstacles_sp` is a NAMING ERROR, not a stale entry.** Corrected 2026-09-01.
  There is no `fwa_obstacles_sp` anywhere in fwapg — a repo-wide grep returns
  zero hits. The analogous table is **`fwa_obstructions_sp`**, it *is* downloaded
  (`load.sh:20`, template A), and it is **present in our database with 32,541
  rows**. So link has been fingerprinting a table that never existed, which is
  why 39 of 429 `log_input` rows carry NULL for it — the NULL is honest about a
  question we were asking wrongly. `R/lnk_log.R:147` and the doc line at
  `R/lnk_pipeline_break.R:25` both name it. Tracked separately; it is a live
  link-side bug rather than #265 scope.

### Revised order

1. **`snapshot_bcfp.sh` records `loader` rows for the 4 primitives it loads**
   (`bcfishobs.observations`, `cabd.dams`, `whse_fish.pscis_assessment_svw`,
   `fresh.modelled_stream_crossings`). Ours — no fork divergence. Still valid,
   still the right first step.
2. **Decide the fork question** — patch `NewGraphEnvironment/fwapg`'s `load.sh`
   (fork goes 1-ahead of `smnorris/fwapg`, sync becomes a merge), or PR it
   upstream (needs explicit approval per `CLAUDE.md`). No probe-only path
   reaches `fwa_stream_networks_sp`.
3. **Then the 7 FWA primitives**, `loader` rows, honest `kind` for the derived one.

### Absorbs #247

link#247 proposes `fresh.snapshot_stamp (host, table_name, loaded_at, n_rows,
bcfp_head_sha)` so primitive vintage is a recorded fact rather than a
`last_analyze` inference. That is the same row as the one above, minus the
artifact identity — and `Last-Modified` from the object store is strictly better
than the inference #247's own body calls "an upper bound … it can read too-new,
never too-old".

Running both would mean two tables answering "where did this table come from".
**#247 should close as superseded by this, and its acceptance criteria carried
over verbatim** — in particular *absence is FATAL*, which is the property that
fixes staleness by construction rather than by threshold tuning.

### The fork trade, which is now step 2 rather than deferred

`NewGraphEnvironment/fwapg` and `NewGraphEnvironment/bcfishobs` are **forks of
`smnorris/*`** carrying zero local commits (fwapg 0 ahead / 5 behind, bcfishobs
identical). That is *why* `fwapg_sha` resolves against upstream at all — an
accident of being 0-ahead, not a property. A stamping commit makes the fork
1-ahead, the SHA stops resolving upstream, and every future sync becomes a merge
rather than a fast-forward.

**Superseded by the correction above.** The `set -x` stderr trace reaches
`fwa_stream_networks_sp` without touching the fork at all, so the trade is
deferrable again. Step 1 remains worth doing regardless and does not depend on
the answer.

## Acceptance

- [ ] `fresh.log_source_artifact` populated for all 11 primitives in
      `.lnk_input_primitives()`, with `recorded_by` set on every row
- [ ] A recorded `version_id` round-trips: `?versionId=` returns 200 and the
      same `ETag` recorded at the time
- [ ] `last_modified` present for every probed FWA artifact
- [ ] Negative-tested: an unreachable URL records an honest NULL and does **not**
      fail the run, and a missing row is reported as missing rather than skipped
- [ ] #247's "absent stamp is FATAL" criterion carried over and exercised in both
      directions — a host with a stamp, and one without
- [ ] `fwa_obstructions_sp` (the real name) is fingerprinted and non-NULL —
      32,541 rows in this database. The old `fwa_obstacles_sp` entry is gone
- [ ] The fwapg commit that ran `load.sh` is recorded at load time, and the
      `.lnk_fwapg_sha()` / `lnk_stamp()` docs no longer say `fwapg_sha` is the
      checkout that loaded the data

## Why now

The 217-WSG provincial run is next. Version-ids not recorded during it are
unrecoverable, because the bucket cannot be asked retrospectively. Everything
here is link-side and needs no fork or upstream change.

Relates to link#247 (superseded — see above), link#262 (`bcfp_pin_source`, the
same evidence-strength pattern), link#246 (the vintage gate this strengthens).
Version pin: link@v0.49.0, `NewGraphEnvironment/fwapg@e6e1eb0` (fork of
`smnorris/fwapg`, 0 ahead / 5 behind).






## Errors Encountered

| Error | Resolution |
|-------|------------|
