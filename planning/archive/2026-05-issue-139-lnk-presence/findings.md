# Findings — lnk_presence (#139)

## Issue context

Filed as #139 after surfacing during the link#135 multi-WSG parity sweep:

- ELKR's `wsg_species_presence` has all 5 salmon species (CH/CM/CO/PK/SK) as NULL — east-of-divide WSG, no salmon habitat.
- bcfp's `mapping_code_<sp>` for ELKR salmon emits `""` everywhere (correct silence).
- link's parity sweep emitted `ACCESS;<src>` strings for ~38004 ELKR segments (wrong) because:
  - The salmon-group-shared barriers table (`barriers_ch_cm_co_pk_sk`) has 7 entries in ELKR
  - Most ELKR segments have no salmon barriers downstream → our boolean `has_barriers_<sp>_dnstr = FALSE`
  - mapping_code's CASE: `accessible & spawning_zero & rearing_zero → "ACCESS"` fires
  - bcfp's check is `barriers_<sp>_dnstr = ARRAY[]::text[]` against a NULL value (no row in streams_dnstr_barriers) → NULL = NULL = NULL → ACCESS doesn't fire → `""`

The user-facing intent across all callers: "if species is absent in this WSG, don't emit a mapping_code for it." The cleaner abstraction is presence-driven, not bcfp's NULL-array mechanism.

## Existing pattern in link

`R/lnk_pipeline_species.R` returns `intersect(cfg$species, present_species_in_aoi)` as a character vector. Used by `lnk_pipeline_classify()` and `lnk_pipeline_connect()`.

No group-expansion. No predicate. Plain vector return.

## bcfp species groups (from `model/01_access/sql/load_streams_access.sql`)

```sql
left outer join bcfishpass.wsg_species_presence wsg_salmon
  on s.watershed_group_code = wsg_salmon.watershed_group_code
 and (wsg_salmon.ch is true or wsg_salmon.cm is true
      or wsg_salmon.co is true or wsg_salmon.pk is true
      or wsg_salmon.sk is true)

left outer join bcfishpass.wsg_species_presence wsg_ct_dv_rb
  on s.watershed_group_code = wsg_ct_dv_rb.watershed_group_code
 and (wsg_ct_dv_rb.ct is true or wsg_ct_dv_rb.dv is true
      or wsg_ct_dv_rb.rb is true)
```

Two groups:
- `salmon` = CH, CM, CO, PK, SK
- `ct_dv_rb` = CT, DV, RB

Within each group: presence is "any TRUE" not "this species TRUE." This is bcfp's modelling convention because the per-group barriers tables apply to all members uniformly.

## Bundled CSV shape

`inst/extdata/configs/<bundle>/overrides/wsg_species_presence.csv`:

```
watershed_group_code,bt,ch,cm,co,ct,dv,gr,ko,pk,rb,sk,st,wct,notes
ADMS,t,t,,t,t,t,,,,t,t,,,
```

`"t"` for TRUE, blank for NULL. Loaded by `lnk_load_overrides()` into `loaded$wsg_species_presence` tibble.

## Decisions

1. Helper takes the tibble (not full `loaded` list, not conn). Cleaner; caller does `lnk_presence(loaded$wsg_species_presence, "ADMS")`.
2. Default `groups` arg ships bcfp's two groupings. Caller can override or pass `list()` to disable expansion.
3. Return a named list (not S3 class) — keep simple, debuggable in the REPL.
4. `is_present(sp)` is a closure over `present` — vectorised so callers can do `pres$is_present(c("bt","ch"))`.
5. Coexists with `lnk_pipeline_species` (which is config-aware + intersection-flavored). No deprecation.
