## Problem

We load the FWA primitives from a **versioned** object store, and we record
nothing that identifies which version we got. The store **will not let us ask
later** — so every version-id we fail to record at load time is gone, not merely
inconvenient to find.

`fwapg_sha` pins the *loader's commit*, not the data. `fwa_stream_networks_sp`
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

### Scope, in the order it should be done

1. **`snapshot_bcfp.sh` records `loader` rows for the 4 primitives it loads**
   (`bcfishobs.observations`, `cabd.dams`, `whse_fish.pscis_assessment_svw`,
   `fresh.modelled_stream_crossings`). That script is **ours** — no fork
   divergence, no upstream involvement.
2. **The same script probes the FWA whole-table artifacts** and records them
   `probe`. Closes the FWA hole immediately at honest strength.
3. **Leave the per-WSG split for its own step.** `fwapg/load.sh:64,82` fetch
   `fwa_stream_networks_sp/$WSG.parquet` — ~250 objects for streams alone, so
   probing everything is ~250 `HEAD`s. Whole-table artifacts first.

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

### What this deliberately does not do

Patch `fwapg/load.sh` or `bcfishobs` to write `loader` rows. Both are **forks of
`smnorris/*`** carrying zero local commits (fwapg 0 ahead / 5 behind, bcfishobs
identical). A stamping commit makes the fork 1-ahead, at which point `fwapg_sha`
stops resolving against upstream and every future sync becomes a merge rather
than a fast-forward. That trade is real and is not needed to close the hole — it
upgrades `probe` to `loader`, and belongs in its own issue once this one is
proving its worth.

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
- [ ] `fwa_obstacles_sp` keeps reporting honestly: it does not exist in this
      database, and 39 of 429 `log_input` rows already carry NULL for it

## Why now

The 217-WSG provincial run is next. Version-ids not recorded during it are
unrecoverable, because the bucket cannot be asked retrospectively. Everything
here is link-side and needs no fork or upstream change.

Relates to link#247 (superseded — see above), link#262 (`bcfp_pin_source`, the
same evidence-strength pattern), link#246 (the vintage gate this strengthens).
Version pin: link@v0.49.0, `NewGraphEnvironment/fwapg@e6e1eb0` (fork of
`smnorris/fwapg`, 0 ahead / 5 behind).
