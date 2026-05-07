# Findings — lnk_pipeline_access: compute dam_dnstr_ind / remediated_dnstr_ind from primitives (#135)

## Issue context

`lnk_pipeline_mapping_code()` reproduces bcfp's `streams_mapping_code` byte-identically for all 8 species on ADMS — **as long as the caller merges in bcfp's pre-computed `dam_dnstr_ind` and `remediated_dnstr_ind` columns from `bcfishpass.streams_access`**.

Without those, `mapping_code_<bt|wct>` (resident-flavor) drift on rows where multiple barrier types stack (e.g. PSCIS-then-dam downstream). The resident flavor's CASE is sequence-aware: `DAM` token only fires when the *next* downstream anthropogenic barrier IS a dam, not just "any dam exists downstream". Presence-only fallback (`has_barriers_dams_dnstr`) over-emits DAM for ~14% of segments where bcfp emits `ASSESSED`.

bcfp's SQL ([load_streams_access.sql:140-147](https://github.com/smnorris/bcfishpass/blob/main/model/01_access/sql/load_streams_access.sql#L140)):

```sql
case
  when array[b.barriers_anthropogenic_dnstr[1]] && b.barriers_dams_dnstr then true
  else false
end as dam_dnstr_ind,
```

i.e. take the FIRST element of `barriers_anthropogenic_dnstr` (the next-downstream anthropogenic barrier), check if it's also in `barriers_dams_dnstr`. If yes → DAM is the most-downstream barrier.

## Triage exploration (during plan-mode)

### Shared ID space across barriers tables

DB query confirmed: every bcfp barriers table primary key is populated from `bcfishpass.crossings.aggregated_crossings_id`. Specifically `barriers_anthropogenic.barriers_anthropogenic_id` is sourced from `c.aggregated_crossings_id` in [`barriers_anthropogenic.sql`](https://github.com/smnorris/bcfishpass/blob/main/model/01_access/sql/barriers_anthropogenic.sql#L20). Same for dams, pscis, remediations.

Consequence: `frs_network_features` calls against these tables return arrays of IDs in a SHARED space. Membership checks (`%in%`) work directly across sources without any column rename or join.

Cross-table overlap check:
```
barriers_anthropogenic ⋈ barriers_dams ON _id columns: 2384/2384 dams matched
```

### `remediated_dnstr_ind` regression — bcfp v070 (smnorris#690, 2025-09-24)

Confirmed via `git log --all --oneline -S "remediated_dnstr_ind"` in the bcfp clone:
- [`f446b49`](https://github.com/smnorris/bcfishpass/commit/f446b49) (2023-04-24): "add remediated dnstr to access model" — original feature add. `remediations_barriers_dnstr` array column added to streams_model_access.
- [`107f65a` PR #690](https://github.com/smnorris/bcfishpass/pull/690) (2025-09-24): "db v070" — refactor that "reduce[s] use of nested views" and "reduce[s] use of fwa functions". Inlined a previously-separate column-update as a single SELECT in `load_streams_access.sql`. The CASE introduced the `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` clause, contradictory and always FALSE.

DB confirmation: `bcfishpass.streams_access.remediated_dnstr_ind` is FALSE for all 4.2M rows.

Pre-regression issues confirm the feature was working: smnorris#275 (2023, "linear remediated streams"), smnorris#326 (2023, "qgis - symbolize remediated streams").

### Reach in BC data

`bcfishpass.crossings WHERE pscis_status = 'REMEDIATED'`: 154 rows province-wide. Small but real effect.

### bcfp fork structure

```
$ git remote -v (in bcfishpass clone)
origin    https://github.com/NewGraphEnvironment/bcfishpass.git
upstream  https://github.com/smnorris/bcfishpass.git
```

We can fix in our fork independently of upstream timing. Once smnorris merges, both diverge back to identical output.

## Decisions

1. Compute `dam_dnstr_ind` correctly from primitives. ID-space membership check.
2. Compute `remediated_dnstr_ind` correctly from primitives (NOT bug-compatible). Optional `crossings_table = NULL` arg gates this on caller-supplied lookup table.
3. File one-line fix to `NewGraphEnvironment/bcfishpass` (Phase 1b). Coordinate with upstream once landed.
4. Document divergence in NEWS — link's REMEDIATED tokens may not match bcfp's current output, but match bcfp's *intent*.
