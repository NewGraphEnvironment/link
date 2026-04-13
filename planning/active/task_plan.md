# Task Plan: bcfishpass comparison — wire remaining CSVs + lnk_habitat (#16)

## Goal
Close the remaining +1-3% gap, wire all bcfishpass CSVs, establish `lnk_habitat(config = "bcfishpass")` as province-wide reproducible pipeline.

## Status
ADMS: all within 5% (best: CH +0.5%). BULK: most within 5%, SK spawning -39.9% (fresh#147).

## Phase 1: Wire remaining CSVs (compare_bcfishpass.R)
- [x] user_barriers_definite — break source + access barrier
- [x] observation_exclusions — filter obs before breaking
- [x] user_crossings_misc — extra crossings
- [ ] user_barriers_definite_control — reverted, apply at barrier table build step not override step
- [ ] CABD CSVs (cabd_blkey_xref, cabd_exclusions, cabd_passability_status_updates, cabd_additions) — dam/falls corrections
- [ ] pscis_modelledcrossings_streams_xref — GPS corrections via lnk_match

## Phase 2: Performance + correctness
- [x] WSG filter on breaks table (61k → 27k)
- [x] .frs_index_working on input tables (35x classification speedup, fresh#150)
- [ ] Test on 3+ WSGs (ADMS, BULK, BABL) and log results
- [ ] Investigate BT rearing +5.4% on BULK
- [ ] Document user_barriers_definite_control correct application point

## Phase 3: lnk_habitat function
- [ ] Design config system (named bundles in inst/extdata/configs/)
- [ ] lnk_habitat(conn, wsg, config) wrapping full DAG
- [ ] lnk_stamp() provenance recording
- [ ] GitHub Action for bcfishpass CSV sync

## Phase 4: Fresh issues (parallel terminal)
- [ ] fresh#150 — frs_habitat_classify index input tables
- [ ] fresh#147 — SK spawning BULK regression
- [ ] frs_break_minimal — extract non-minimal removal to function
- [ ] GENERATED id_segment in frs_col_generate
- [ ] .frs_index_working IF NOT EXISTS

## Versions
- fresh: 0.13.3, bcfishpass: v0.5.0 (CSVs synced 2026-04-13 @ e485fe4), link: 0.1.0
- fwapg: Docker (FWA 20240830, channel_width synced from tunnel 2026-04-13)
