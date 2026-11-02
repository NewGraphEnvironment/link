# default_minimal config

The `default` bundle on a minimal network. It is a **thin** bundle: `config.yaml` declares `extends: default` and overrides only two `pipeline:` keys.

| Key | Value | Role |
|---|---|---|
| `schema` | `fresh_default_minimal` | Persist schema, beside `fresh_default` |
| `break_order` | `gradient_minimal`, `falls`, `barriers_definite` | Replaces `default`'s list: no observation, habitat end point or crossing cuts |

Every file and every other pipeline key resolves to `configs/default/`, so `lnk_config("default_minimal")$chain` lists both. Its tokens are `default`'s except for the cut, `cut-min`. `subsurfaceflow` stays off, as `default` leaves it.

## Why

A segment's gradient is the elevation drop over its own length, so each cut moves the gradient a habitat rule reads. Observation cuts put a segment boundary at a fish record, and crossing and habitat end point cuts fall at places unrelated to the stream's form. This network keeps the gradient barriers where a species' access changes, falls and user-definite barriers, so thresholds can be tuned with no record cutting the segment it is scored on.

**It is not independent of the records.** Gradient positions are reduced after observation lifts (`.lnk_pipeline_prep_minimal()`): a barrier lifted for a species is no longer that species' cut, though another species' barrier or a falls may still cut there, and positions above it can become cuts. So a record far upstream can still move a cut below it. A check that leaves a record out needs this in mind.

## What reads differently on longer segments

- **The user habitat overlay reaches fewer km.** `frs_habitat_overlay()` and `lnk_habitat_gate()` keep a flag only where a segment lies wholly inside an overlay range, and no cut falls at a range's ends.
- **Access code 2 reads from each segment's start,** so the segment holding a species' top record reads 2 up to the next cut. Species access codes 0 and 1 stay at cuts, because each species' minimal reduction cuts its access frontiers, with one named exception: a barrier another group lifts and this group does not still prunes the frontier above it here (`.lnk_pipeline_prep_minimal()`).
- **Crossing-based fields read what lies below a segment's start,** so a crossing counts only from the next cut above it, and nothing is measured at a crossing. `dam_dnstr_ind` and `remediated_dnstr_ind` read the next feature downstream, which that can change, so they can move either way.

`streams_access` and `barriers` persist as they do for `default`.

## Running it

```bash
bash data-raw/study_area_run.sh --config=default_minimal --schema=fresh_default_minimal ...
LNK_SCHEMA=fresh_default_minimal Rscript data-raw/wsg_run_one.R ADMS default_minimal
```

`study_area_run.sh` needs `--schema=` for this bundle, as for every bundle but `bcfishpass`. Its pre-flight refuses a schema with no passing gate record, and the gate cannot yet pick groups for a bundle with no build history: `pretest_pick.R` refuses a schema with no `log`, and `--minutes-schema` reads minutes under the run's own config only. A first provincial run therefore goes through `--pretest-note="<why>"`, which records an override and needs the schema to exist first, unless the gate learns to borrow `default`'s history. Mechanics of the token: RUNBOOK §6b, "Output vocabulary".
