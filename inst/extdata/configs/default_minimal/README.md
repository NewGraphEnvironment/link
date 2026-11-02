# default_minimal config

The `default` bundle on a minimal network. It is a **thin** bundle: `config.yaml` declares `extends: default` and overrides only two `pipeline:` keys.

| Key | Value | Role |
|---|---|---|
| `schema` | `fresh_default_minimal` | Persist schema, beside `fresh_default` |
| `break_order` | `gradient_minimal`, `falls`, `barriers_definite` | Replaces `default`'s list: no observation, habitat end point or crossing cuts |

Every file and every other pipeline key resolves to `configs/default/`, so `lnk_config("default_minimal")$chain` lists both. Its tokens are `default`'s except for the cut, `cut-min`. `subsurfaceflow` stays off, as `default` leaves it.

## Why

A segment's gradient is the elevation drop over its own length, so each cut moves the gradient a habitat rule reads. Observation cuts make that gradient depend on where fish were caught, and crossing and habitat end point cuts fall at places unrelated to the stream's form. This network keeps only the cuts where a species' access changes, so thresholds can be tuned on segments that know nothing about the records scored against them.

## What reads differently on longer segments

- **The user habitat overlay reaches fewer km.** `frs_habitat_overlay()` and `lnk_habitat_gate()` keep a flag only where a segment lies wholly inside an overlay range, and no cut falls at a range's ends.
- **Access code 2 reads from each segment's start,** so the segment holding a species' top record reads 2 up to the next cut. Species access codes 0 and 1 stay at cuts, because each species' minimal reduction cuts every access frontier.
- **Crossing-based fields read what lies below a segment's start,** so a crossing counts only from the next cut above it, and nothing is measured at a crossing. `dam_dnstr_ind` and `remediated_dnstr_ind` read the next feature downstream, which that can change, so they can move either way.

`streams_access` and `barriers` persist as they do for `default`.

## Running it

```bash
bash data-raw/study_area_run.sh --config=default_minimal --schema=fresh_default_minimal ...
LNK_SCHEMA=fresh_default_minimal Rscript data-raw/wsg_run_one.R ADMS default_minimal
```

`study_area_run.sh` needs `--schema=` for this bundle, as for every bundle but `bcfishpass`. Mechanics of the token: RUNBOOK §6b, "Output vocabulary".
