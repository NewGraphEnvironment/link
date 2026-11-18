# default's presence table as bcfishpass's copy plus an overlay (link#472, backlog move 4)

Run on m1's local docker fwapg (PostgreSQL 17.5), 2026-11-18 UTC, fresh 0.52.0. Covers #431, #436
and #292; #402's review decisions are what the overlay carries.

| file | what it is |
|---|---|
| `build_overlay.R` | Run once: copied bcfishpass's presence table over `default`'s and wrote the 126-row overlay (110 added, 10 removed, 2 kept absent, 4 `ko`) from the tracker's decided rows; stops unless copy + overlay gives the old species cells. Re-run from a worktree at `0f36e750` (the commit before the conversion) to add the review's rule to each reason. |
| `presence_check/` | `data-raw/wsg_species_presence_check.R` at `ab5020e9`, tracker not seeded (`stamp.txt`) |
| `model_diff.R`, `model_diff.csv` | Every persisted table (log tables aside) of ADMS, BULK and GUIC built at `main` against the branch head, as a row-text digest per table and group |
| `guic_access.R`, `guic_access.out` | What moved in GUIC's `streams_access` |

## The conversion changes no species cell

The loaded `default` and `default_tuned` presence tables digest identical before and after in
their key and species columns (order and types included; computed in a worktree at the commit
before the conversion and pinned in `test-lnk_csv_sync.R`). All five live bundles resolve to the
same tokens. Only `notes` takes the copy's text: each of the 80 notes that moved was a pointer to
the tracker ("added PK (#402 review …)").

## The presence check after the overlay

233 cells flagged, from 351 at #402's first run. The 111 added and 9 of the 10 removed cells drop
out, and MESI SK with them: its one counting record is now excluded. KOTL ST keeps 2 counting
records after its exclusion and stays flagged (decided keep). Four cells read differently since
#470 counted the alias codes: VICT DV (removed; now absent with 1 counting record), and FINA ST,
MFRA BT and UFRT ST, flagged for the first time with 1 record each and given no tracker row,
because the tracker was not seeded. `recall.csv` holds bcfishpass's 67 known errors (link's 3 were found with the same measures, so they stay out of it).

## ADMS, BULK and GUIC built before and after

`wsg_run_one.R <WSG> default` from two worktrees, `db4a7710` (main, 0.85.0) and `ab5020e9` (the
branch with all three changes), into scratch schemas `zz472_main` and `zz472_head` (dropped
after), `LNK_GUARD_DOWNSTREAM=warn`, a 20 min statement bound. Every log row is clean
(`link_dirty` false) and carries `cut-full-top-2 acc-v6`; `config_hash` differs, as it should.

| | result |
|---|---|
| ADMS, BULK | every persisted table identical (`streams`, `streams_access`, `streams_mapping_code`, `barriers`, `barrier_overrides`, `barrier_override_evidence`, each `streams_habitat_<sp>`): #292's acceptance, with #431 and #436 beside it |
| GUIC | identical except `streams_access`: `access_ch` 2 to 1 on 227 segments, 52.3 km. That is the excluded CH record (`091612fd01`, misplaced in the headwaters): code 2 GUIC CH segments fall from 310 to 83. Lifts, habitat and mapping codes do not move (a salmon lift needs 2 records). |

53 of 54 table and group pairs identical (`model_diff.csv`).

The first try of the `main` arm stalled in ADMS's `frs_near_river_walk` with no statement bound
(17:58:46Z to 18:32:28Z, cancelled by hand); its sampler rows are #487's first real stall,
`data-raw/logs/stall_sample_487/20261118_wsg_run_one_stall_ADMS.tsv`. Re-run under the bound,
ADMS finished in 2.5 min.
