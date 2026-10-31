# Task: Weekly CSV sync skips four copied bcfishpass files; Keogh and Adams dam fixes missing (#429)

## Problem

`data-raw/sync_bcfishpass_csvs.R` checks 7 files against `s3://fresh-bc/bcfishpass/csvs/` (the dump of bcfishpass's ng-prod build, `v0.7.15-51-g3bd2824` at 2026-10-28). It selects files whose provenance `source` is `https://github.com/smnorris/bcfishpass`, so files declared otherwise are never compared. Compared byte for byte on 2026-10-31 against the same dump:

| File | Bundles | Differs by |
|---|---|---|
| `cabd_passability_status_updates.csv` | `bcfishpass`, `default` | 2 rows dated 2026-09-29: the Keogh River and Adams dams set passable (`smnorris/bcfishpass@620dbe4`, `a0c1a36c`) |
| `wsg_species_presence.csv` | `bcfishpass` | 2 cells: UTRE CH and QUES ST present upstream, absent here (the bundle also carries its own `ko` column) |
| `wcrp_watersheds.csv` | `bcfishpass`, `default` | 6 lines (BONP, SHUL, …) |
| `cabd_blkey_xref.csv` | `bcfishpass` | trailing newline only (#347, ours) |

`observation_exclusions.csv` is also outside the sync and matches upstream today. The dry run reports "no drift" while these differ.


## Approach

Link starts from bcfishpass's published files and keeps its own changes separate, each with a reason, so a reader can see exactly what link adds, and a justified change can be offered upstream as a pull request to bcfishpass's own CSVs.

1. **Copies stay verbatim.** Every bcfishpass-derived file in a bundle is a byte-for-byte copy the weekly sync checks. Link never edits a copy; a copy that reads badly is fixed in link's reader.
2. **Link's changes live in overlays:** a link-owned file of cell-level changes on top of a copy (key, column, value, reason, issue), applied by the loader, so every reader sees the table it sees today.
3. **Overlay rows are the upstream candidates.** When upstream adopts one, the sync reports the row as redundant and it is retired; a row that stays is a deliberate departure with its reason written down.
4. **Follow-ups:** `default`'s presence table as the copy plus an overlay, so #402's decisions land as overlay rows with reasons; then a census of every bundle input by its relation to bcfishpass (verbatim copy / overlay / link's own / frozen derived copy), the parameters being the next overlay candidates.

## Context for #429 (measured 2026-10-31 against the dump, `v0.7.15-51-g3bd2824`)

| File | Bundles | Differs by |
|---|---|---|
| `cabd_passability_status_updates.csv` | both | 2 rows (Keogh, Adams), dated 2026-09-29 |
| `wcrp_watersheds.csv` | both | 3 lines (BONP, SHUL, USHU) |
| `cabd_blkey_xref.csv` | both | link's trailing newline (#347) |
| `wsg_species_presence.csv` | bcfishpass | UTRE CH and QUES ST, plus link's `ko` column |

`cabd_additions`, `cabd_exclusions`, `dfo_known_sockeye_lakes` and `observation_exclusions` match the dump but are outside the sync. Every package reader takes the presence table from `loaded$wsg_species_presence`. Only three `data-raw/` scripts read the file by path.

**The dam rows change nothing.** Neither updated id is in `cabd.dams`, either in local fwapg or in bcfishpass's own reference at `v0.7.15-51-g3bd2824c`. Keogh Dam is `242fa0e4…` and is still `BARRIER` in `bcfishpass.crossings` (NIMP). The CABD API does not know `298b0f7e`, and it lists `1c16395b` as decommissioned. Parity cannot move, so the check is a query and there is no re-model.

## Decided at the gate

- **`observation_exclusions.csv` is a synced copy** (operator, 2026-10-31). Link-only exclusions, if #402 makes any, go in an overlay.
- **Presence: `ko` moves into an overlay** (operator, 2026-10-31, revised at the gate from comparing past it). The copy stays verbatim.
- **`cabd_blkey_xref.csv` returns to upstream's bytes.** The 'incomplete final line' warning is fixed in the loader's local read path (`readLines(warn = FALSE)`).
- **A token input never auto-merges.** The sync computes the vocabulary specs on each bundle path before and after writing; a changed spec, or a bundle that no longer loads (an overlay row whose key upstream dropped), is the `review` kind: labelled PR, red run, the new spec in the body (revised after the Plan review, which replaced a hand-set `token_input` flag).
- **Mechanism, decided without asking:**
  - per-bundle sync (each bundle syncs only what its own provenance declares);
  - a fetch failure stops the run;
  - the sync helpers are internal functions in `R/`;
  - the overlay is generic over any wide table with a declared key column, so the parameters can use it later.
- **`default`'s presence table stays as it is in #429.** Its conversion is sequence step 2.

## Phase 1: Overlay mechanism, token-neutral

- [x] Write tests first (`test-lnk_overlay.R`):
  - an overlay sets a cell and adds a column;
  - a key missing from the base refuses;
  - a duplicate (key, column) refuses;
  - every row must carry a reason.
- [x] Add `R/lnk_overlay.R` (internal `.lnk_overlay_apply()`).
- [x] Make `lnk_load_overrides()` apply a `files:` entry's `overlay:` path.
- [x] Fix the local read path's final-line warning.
- [x] Write `overrides/wsg_species_presence_overlay.csv` for the bcfishpass bundle (its `ko` cells, with reason and issue), and drop `ko` from the copy.
- [x] Repoint the `data-raw/` path readers at the loader. Only `audit_configs.R` read the table by path; `wsg_species_presence_check.R` already loads it and only prints the path, and `regen_provenance.R` hashes the file as a provenance entry, which is right for the copy.
- [x] Prove it changed nothing: the loaded presence table is `identical()` before and after, and `lnk_vocabulary_resolve(lnk_config("bcfishpass"))` still gives `acc-bcfp-3`.

## Phase 2: Sync script

- [ ] Write tests first:
  - a static guard: every CSV under each bundle's `overrides/` has a provenance entry, and every `source: bcfp` entry points at the bcfishpass repo (the old selector must turn it red);
  - drift kinds `none`, `byte`, `shape` and `review`;
  - the overlay-redundant report.
- [ ] Change `data-raw/sync_bcfishpass_csvs.R`:
  - iterate per bundle and write only into the declaring bundle;
  - stop on a fetch failure;
  - add the `review` kind, with the `acc` row to add named in the PR body;
  - report overlay rows that upstream now equals.
- [ ] Teach `.github/workflows/sync-bcfishpass-csvs.yml` the `review` kind.
- [x] Map `R/lnk_overlay.R` `any` and the overlay CSV with the presence row in `data-raw/pretest_inputs.csv` (Plan review B2, G4); sync-only helpers, if any, `none`.

## Phase 3: Provenance entries

- [ ] Both bundles get bcfishpass-sourced entries for `cabd_additions`, `cabd_exclusions`, `cabd_blkey_xref`, `cabd_passability_status_updates`, `dfo_known_sockeye_lakes`, `wcrp_watersheds` and `observation_exclusions`.
- [ ] The bcfishpass bundle's presence entry points at bcfishpass; its overlay stays link-owned.
- [ ] Dry run: drift on exactly passability, wcrp, blkey_xref (both bundles) and presence (bcfishpass, `review`). That meets acceptance 1. Record it in `data-raw/logs/csv_sync_429/`.

## Phase 4: Pull the drift

- [ ] Run the sync for real, in the same commit as Phase 5 (Plan review O2).
- [ ] Check: the loaded presence table differs from before at exactly UTRE/ch and QUES/st (Plan review O3); the dry run then reports no drift, `lnk_config_verify()` is clean on both bundles, `default`'s presence is byte-unchanged, and no group logs the final-line warning.

## Phase 5: Token

- [ ] Add a row `acc-bcfp-4` ("As acc-bcfp-3, but the presence table follows bcfishpass at `3bd2824`: UTRE CH and QUES ST present"), introduced at 0.74.0, and retire `acc-bcfp-3`.
- [ ] Update `test-lnk_vocabulary.R`, and run the append-only test locally.

## Phase 6: Dam rows, parity by query

- [ ] Add `data-raw/logs/csv_sync_429/dams.sql` and its output, for both databases (acceptance 2).
- [ ] Draft (not post) the Keogh `cabd_id` note for upstream, in `findings.md`.

## Phase 7: Docs and version

- [ ] Add a RUNBOOK section: copies, overlays, the sync and its `review` kind, in neutral public wording.
- [ ] Update the CLAUDE.md status and NEWS.
- [ ] Add a Working Conventions entry to CLAUDE.md: a bcfishpass-derived input is a verbatim synced copy, and link's changes go in an overlay with a reason (neutral wording).
- [ ] Bump `DESCRIPTION` to 0.74.0 as the final commit.

## Owed at the end (reported, done after merge)

- [ ] Draft the link issue "`default` presence as copy plus overlay; #402 decisions as overlay rows", for your word.
- [ ] Re-model UTRE and QUES in the `fresh` (bcfishpass) schema at the next provincial run (#377's runs row).
- [ ] Post the Keogh `cabd_id` note upstream, on your word only.
- [ ] Report, unchanged: the older copies in `default_extrabreaks` and `default_rearbreaks`. (The dead `user_modelled_crossing_fixes_20240825.csv` was deleted from `bcfishpass` and `default` instead, Plan review B3.)
- [ ] Re-run the pre-run gate (#372) before the next provincial run: `R/` and `inst/extdata/` changed (Plan review G4).

## Validation

- [ ] Tests pass (`devtools::test()`; the vocabulary test locally)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:
- **The overlay is token-neutral:** `identical()` on the loaded table, and `acc-bcfp-3` still resolves.
- **The sync's reach:** the dry run before and after.
- **The guard fires:** the old selector turns the test red.
- **Bundle state:** `lnk_config_verify()` is clean.
- **The token:** `acc-bcfp-4` resolves.
- **Parity:** the dams query.
