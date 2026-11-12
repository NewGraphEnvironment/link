# #465 evidence: export persisted barriers per group, so a one-group run reads downstream

All on m1's local fwapg, against `fresh_default` (the 2026-11-03 provincial `default` build,
run `20261103_163715-269b585a`, link `4dfbfa49`, fresh 0.52.0).

| file | what |
|---|---|
| `line_rule_identity.md` | the line rule moved into `R/lnk_wsg_deps.R`: `recompute_deps.R` output byte-identical before and after (`line` and `all`) |
| `superset.sql`, `superset_fresh_default.log` | every persisted barrier (7,749,648) and override (44,069) row sits on a blue line its own group touches in FWA: 0 off, so the line rule covers what a walk reads |
| `e2e.R`, `e2e/` | the round trip on one host, below |

## The round trip (`e2e/`, 2026-11-12, link `27cd92c5`, clean tree)

Export (`habitat_publish.R` BUILD) of BULL and its 11 line-rule dependencies (CANO, CLRH,
COLR, ELKR, KHOR, KOTL, KOTR, LARL, REVL, SMAR, UARL; its outlet closure is KOTL and LARL
only): 62 s (`e2e/export.log`). Then BULL modelled with `wsg_run_one.R BULL default` into
four scratch schemas (dropped afterwards, with `working_bull`):

| arm | downstream rows | guard | minutes | `streams` | `streams_access` | `streams_mapping_code` |
|---|---|---|---|---|---|---|
| a | loaded from the export (`lnk_downstream_load()`) | error, passed | 2.09 | `ff498ed2…` | `9f853e84…` | `79fb08a4…` |
| b | copied by SQL from `fresh_default` (control) | error, passed | 2.04 | `ff498ed2…` | `9f853e84…` | `79fb08a4…` |
| c | none | ignore | 1.89 | `ff498ed2…` | `3dca9f51…` | `868bcc0b…` |
| d | barriers only, no overrides | error, passed | 1.85 | `ff498ed2…` | `9f853e84…` | `79fb08a4…` |
| `fresh_default` | the provincial build | | | `ff498ed2…` | `9f853e84…` | `79fb08a4…` |

md5 over all 20,791 BULL rows of each table (`e2e/digests.csv`). **a equals b and the
provincial build exactly.** c differs: without the downstream rows, 341 segments lose
`has_barriers_dams_dnstr`, 52 lose `dam_dnstr_ind` and `has_barriers_anthropogenic_dnstr`,
and 49 BT and 45 WCT mapping codes change (`e2e/diffs.csv`); no `access_*` column moves,
because the natural barriers below BULL lie on lines BULL touches and its own build writes
them. The provincial build itself opened with the guard in `warn` naming 7 unmodelled
dams below BULL (KOTL 6, LARL 1); in arms a, b and d the guard ran in `error` and passed.

**d does not differ, so this target cannot fail for a missing override.** BULL writes
its own copies of the overrides on the lines it touches (268 rows); 60 of the
dependencies' override rows lie within 1 m of one of them. The overrides round trip is
covered by the unit tests (`test-lnk_downstream.R`), not by this run.

What this does not show: m1 holds province FWA, CABD, PSCIS and observations, so a database
holding only some groups is not exercised (follow-up). `e2e_try1_failed.log` stopped in the
loader's report on arm d (fixed in `ecfc847d`); `e2e_try2_failed.log` in the driver (an
unquoted env value, fixed in `27cd92c5`).
