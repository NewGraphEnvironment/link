# `fresh.streams_vw_bcfp` column coding — the parity predicates

Migrated from machine-local memory 2026-08-31 (soul#47). Durable: this is the
bcfishpass view's schema, not a run state. Found 2026-07-03 during #223
validation.

## The predicate that matters

`spawning_<sp>`, `rearing_<sp>` and `access_<sp>` are **integer-coded 0/1/2/3**,
not boolean. The presence predicate is:

```sql
WHERE spawning_<sp> IN (1, 2)     -- 1 = modelled, 2 = observed
```

Both of the obvious alternatives are wrong, in opposite directions:

| predicate | effect | what it manufactured |
|---|---|---|
| `= 1` | **under-counts** — drops 2s and 3s | a false "+42% ST spawning / +24% CO spawning divergence" |
| `> 0` | **over-counts** — includes 3, a category link does not credit | made link look 2.6-8.7% *under* |
| **`IN (1,2)`** | reconciles link ↔ bcfp exactly | — |

The +42% scare was pure measurement error. It was caught because the user
pushed back on the magnitude — *"we never had gaps that big"* — which is worth
remembering as a technique: a divergence far outside the plausible range is
more likely to be the measurement than the model.

## Accessibility

`barriers_<group>_dnstr = ''` — an **empty string**, `character varying`, not a
`text[]`. Verified byte-identical to `access_<sp> IN (1,2)`.

Group columns, because salmon share one:

| species | column |
|---|---|
| CH, CM, CO, PK, SK | `barriers_ch_cm_co_pk_sk_dnstr` |
| BT | `barriers_bt_dnstr` |
| ST | `barriers_st_dnstr` |
| WCT | `barriers_wct_dnstr` |

## Shape gotchas

- **No `rearing_cm` / `rearing_pk`** — chum and pink do not rear in freshwater.
  Spawning and access exist for all 8 species.
- **Link side is different:** `streams_habitat_<sp>` uses BOOLEAN
  `spawning` / `rearing`; `streams_access.access_<sp>` is the integer.
- **Length lives on `streams`**, not on `streams_access` or
  `streams_habitat_<sp>`. Sum `streams.length_metre`.
- **Join on the full PK `(id_segment, watershed_group_code)`** — `id_segment` is
  not globally unique in the consolidated persist, so a bare join fans out
  cartesian (#203).

## Harness

`data-raw/parity_crosssection.R` (link `lnk_rollup_wsg()` vs the bcfp view,
using `IN (1,2)`), and `lnk_compare_rollup()`.

Known parked departure: BULK SK spawning/rearing (fresh#190, dual-rearing-lake
topology). Species link does not model but bcfp does (residence, #189) —
exclude them, do not assert on them.
