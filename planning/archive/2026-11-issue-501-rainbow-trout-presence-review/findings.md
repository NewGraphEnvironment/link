# Findings — Backlog move 16: Rainbow trout back in default, and the presence review's last rows (#501)

## Issue context

**If we do it:** `default` models rainbow trout again on records told apart from steelhead, and the presence review's remaining rows are decided. NewGraphEnvironment/knowledge#148 can then bring rainbow trout rearing back. **If we never do:** rainbow trout stays paused in `default`, with no access, habitat or mapping code anywhere, and the review's pending rows stay pending.

Move 16 of link's backlog, `planning/backlog.md`. Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge. When the plan finds that a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue naming move 16, and leaves it out of the backlog file.

### Batch 24: Rainbow trout back in `default`, and the presence review's remaining rows

**Why here:** one record rule, one presence overlay and one `acc` row; it lands before the next provincial runs (move 17) so they are not made stale by it.

**Touches:** `inst/extdata/configs/default/species_modelled.csv`, `inst/extdata/configs/default/species_pooling.csv`, `inst/extdata/configs/default/overrides/wsg_species_presence_overlay.csv`, `inst/extdata/configs/default/wsg_species_presence_review.csv`, `inst/extdata/vocabulary.csv`, `research/species_presence.md`.

**Decided at the gate:** how a rainbow trout record is told from a steelhead one (codes, sources, places); the three pending RB rows; whether KO's 138 rows wait for KO's own return; the four cells the check reads differently since #470 (VICT DV, FINA ST, MFRA BT, UFRT ST).

| issue | title |
|---|---|
| #497 | Bring rainbow trout back to default: tell its records from steelhead, decide its three presence rows |
| #402 | Check each group's species presence against its fish records |

## Exploration (2026-11-22, at origin/main be06e2b4, link 0.86.0)

- **Tracker pending rows:** 154: 138 KO (`issue` #432), 3 RB (#497: CRYL `absent_recorded`, LPRO and UPET `present_unsupported`, releases only), 13 others (#402: 8 BT on DV records, CT FINL, LOMI, CLRH, DUNC, TURN ST).
- **The first review's stocked-fish precedent:** THOM CT, LNTH CT, VICT DV, BULL GR removed for resting only on releases; KTSU, TAYR, BBAR, DRIR and UEUT cells kept.
- **Record rule mechanics** (`R/lnk_observation_records.R`): a pooling row whose `species_obs` is a species column pools that species' records (DV into BT); one whose `species_obs` is no species column is an alias. `.lnk_record_aliases()` stops when one alias code counts as two species in one group (`duplicated(watershed_group_code, obs_species)`), so `SST`/`WST` counting as both ST and RB is refused today. A species column counted as two targets (ST as ST and as RB) is the DV/BT case the table builder already writes twice.
- **Lift parameters** (`configs/default/parameters_fresh.csv`): RB threshold 1, no date floor, lift list `RB`; ST threshold 2, floor 1990-01-01, lift list `CH;CM;CO;PK;SK;ST`. Under `lift_floor`, a species with no floor counts every record.
- **Pause pins in tests:** `test-lnk_config.R:620-638` (default and default_tuned pause KO and RB; `paused: +KO, RB`), `test-lnk_pipeline_species.R:126-128`, `test-lnk_pipeline_run.R:336-359`, `test-lnk_vocabulary.R:377`.
- **Live tokens:** `cut-full-top-2`, `acc-v6` (default), `cut-min` (0.77.0, default_minimal), `grad-parent`, `grad-seg`, `grad-fwa`, `q-fwapg`, `q-wet-fill`. Bundles extending `default`: `default_tuned`, `default_minimal`, `default_parent`. The cut spec carries the record-rule digest (`R/lnk_vocabulary.R:152`); the acc spec carries `cfg$species`, presence columns and the record rule.
- **`presence_groups.csv`:** `ct_dv_rb` = CT, DV, RB. Once RB is modelled, a CT or DV cell promotes RB's breaks.
- **Presence measures** (`R/lnk_presence_measures.R`): finds the nearest blocking natural barrier for CH, CM, CO, PK, SK, ST, KO records only; RB-coded records would need ST's barrier set.
- **knowledge#148** (open): waits for link's fix to read which visits count as RB and ST against its `0310` outcomes.
- **Move 17 (#502)** waits on this move (and 3, 13, 14) and the operator's word.

## Errors Encountered

| Error | Resolution |
|-------|------------|
