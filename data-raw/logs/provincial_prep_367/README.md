# provincial_prep_367 — verification for link#367

Builds of 2026-10-22/23 on the local fwapg (docker), branch `0d531e2a`, main `67a410e2`, fresh 0.42.0, primitives loaded 2026-10-17 00:46 UTC (`stamp.txt`). Config `default`; scratch schemas `fresh_367a` (branch), `fresh_367b` (branch, second build), `fresh_367c` (branch, `bundle_knob_off_config.yaml`: `default` with `cabd_additions_barriers: false`), `fresh_367m` (main, frozen worktree). Driver `run.sh` (two lanes, a lock per group); comparisons `compare.R`.

The run's first LARL build into `fresh_367a` failed on a harness race (both lanes ran `CREATE SCHEMA IF NOT EXISTS fresh_367a` at once; `run_status.txt`), so LARL was rebuilt and recomputed after the run, and KETL and SKGT recomputed again after it, so that each recompute saw the same groups in both schemas. Before that re-run one KETL segment, on a line draining through LARL, differed in access between `fresh_367a` and `fresh_367c` only because LARL was missing from `fresh_367a`.

| file | what it shows |
|---|---|
| `reproducibility.csv` | ADMS and ELKR built twice at the branch: every persisted table identical, barriers included (link#277) |
| `knob_tables.csv` | LARL, KETL, SKGT with the placeholders as barriers or not: `streams` and every `streams_habitat_<sp>` identical; `barriers`, `streams_access` (dam flags only) and `streams_mapping_code` differ |
| `knob_barrier_rows.csv` | the only barrier rows that differ: the five placeholders, 1200000001-5 |
| `knob_mapping_code_changes.csv` | 19,065 segments change mapping code, every one only in the second token, `NONE` to `DAM` (BT, RB, WCT; no anadromous species is present in the three groups) |
| `main_vs_branch_km.csv` | ADMS, ELKR, NATR at main and branch: +1, +1, +2 segments; accessible km identical; spawning and rearing move by at most 0.094 km per species (ADMS CH spawning +0.088, NATR GR rearing +0.094) |
