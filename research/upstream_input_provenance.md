# Upstream input provenance — what pins fwapg, bcfishobs and bcfishpass

Measured 2026-09-01 while scoping link#262's follow-ups (link#264, link#265).
Neither fact is visible from the code, and both cost real probing.

## fwapg and bcfishobs are **forks** of `smnorris/*`

| repo | fork of | divergence |
|---|---|---|
| `NewGraphEnvironment/fwapg` | `smnorris/fwapg` | 0 ahead, **5 behind** |
| `NewGraphEnvironment/bcfishobs` | `smnorris/bcfishobs` | **identical** |

Both carry **zero local commits**. That is *why* `fwapg_sha` resolves against
upstream at all — an accident of being 0-ahead, not a property of the field.

**The consequence for any "just patch the loader" proposal:** a stamping commit
makes the fork 1-ahead, at which point the SHA stops resolving upstream and every
future sync becomes a merge rather than a fast-forward. So loader-side stamping
has a real cost, and it is not the cost people expect.

`CLAUDE.md`'s *never write into `smnorris/*` without explicit approval* rule
governs the **upstream**, not our forks — but the divergence cost applies either
way.

## The FWA object store is versioned, and asymmetrically readable

`fwapg/load.sh` pulls from
`https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/…` — BC gov ECS
(`Server: ViPR/1.0`), S3-compatible, **versioning on**. An anonymous `HEAD`
returns three identity handles for free:

```
x-amz-version-id: 1776306159523
ETag: "da5ba121842036c6f494a1eef0ac41f4-18"
Last-Modified: Thu, 16 Apr 2026 02:22:39 GMT
```

| capability | result |
|---|---|
| re-fetch an exact version — `?versionId=` | ✅ 200, same ETag |
| list version history — `?versions` | ❌ `AccessDenied` |
| list the prefix — `?list-type=2` | ❌ `AccessDenied` |
| a manifest, like bcfp's `log.json` | ❌ 404 |

**This sets a deadline, not a preference.** We can re-fetch a version we can
name and can never enumerate the ones we did not record, so a version-id not
recorded *at load time* is gone. Same argument as link#262 one layer down:
provenance that cannot be retrofitted. It is also a concrete instance of
`CLAUDE.md`'s "Public bucket ≠ listable: GetObject vs ListBucket".

## The FWA artifacts have no single URL convention

This is what makes a link-side probe insufficient. `load.sh` has **five** loading
blocks with five URL shapes:

| primitive | whole `.parquet` | per-WSG | `.csv.gz` | reality |
|---|---|---|---|---|
| `fwa_stream_networks_sp` | 404 | **200** | — | per-WSG only, ~250 objects |
| `fwa_stream_networks_channel_width` | 404 | 404 | **200** | different format |
| `fwa_stream_networks_order_parent` | 404 | 404 | 404 | **derived in-DB** — `load/fwa_stream_networks_order_parent.sql` |
| `fwa_lakes_poly` | **200** | 404 | — | |
| `fwa_wetlands_poly` | **200** | 404 | — | |
| `fwa_rivers_poly` | **200** | 404 | — | |
| `fwa_obstructions_sp` | **200** | 404 | — | *(listed here as `fwa_obstacles_sp` until 2026-09-02 — see below)* |

Two consequences worth not re-deriving:

- **`order_parent` is derived, not downloaded.** A NULL artifact there is correct
  and permanent; any schema must distinguish *derived* from *unrecorded* or it
  reads as a gap forever.

### Two corrections, 2026-09-02

Both claims below were stated here as measured fact and were wrong. Each had also
propagated into link#265 and into machine-local memory — one source, three
restatements, which is why agreeing copies are not corroboration.

- **"Only the loader knows the URL it built"** — used to argue that probing was
  impossible and the fork-divergence question was therefore on the critical path.
  **False.** `fwapg/load.sh:2` is `set -euxo pipefail`, so the loader already
  traces every fully-expanded URL to stderr, including all ~250 per-WSG
  `fwa_stream_networks_sp/$WSG.parquet` fetches. `./load.sh 2> run.log` is a
  complete, ordered record with **no change to fwapg at all** — no fork commit, no
  upstream PR. That is link#270. The genuine obstacle is narrower and unchanged:
  the watershed-group list comes from an OGR query against the remote parquet
  (`load.sh:40-43`), so a link-side reimplementation would drift from it.
- **"`obstacles_sp` is a stale entry … absent from the bucket"** — the symptom was
  right and the cause was not. It is a **naming error**: no `fwa_obstacles_sp`
  exists anywhere in fwapg (repo-wide grep, zero hits), the real table is
  **`fwa_obstructions_sp`**, it *is* downloaded (`load.sh:20`), and it holds
  **32,541 rows** in our database. So the 39 NULL `log_input` rows were honest
  about a question asked wrongly. Fixed in link#271 / v0.50.0; the doc line at
  `R/lnk_pipeline_break.R:25` still carries the wrong name and is deliberately
  left for reading rather than substitution.

## What pins each input today

| input | pinned by | resolvable? |
|---|---|---|
| bcfishpass | `bcfp_model_version` + `bcfp_pin_source` | yes — link#262 |
| fwapg | `fwapg_sha` | yes, but only *because* the fork is 0-ahead |
| **bcfishobs** | **nothing** | **no** — a row count and the literal string `bcfishobs` |

`bcfishobs` is a *pipeline*, not a dataset: it matches observations onto the
stream network, and `lnk_barrier_overrides()` counts those upstream of each
barrier to decide which barriers are skipped. Different `bcfishobs` code →
different matching → different barriers → different access. Tracked in link#264.

## Related

- link#264 — `fresh_sha` is unread from DESCRIPTION rather than absent;
  `fresh_dirty` never set; `bcfishobs` unpinned
- link#265 — record source-artifact identity (this document is its evidence base)
- link#266 — link and `flooded` select the bcfp reference build by different rules
- link#247 — `snapshot_stamp`, superseded in scope by #265
