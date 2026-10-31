## Outcome

The weekly bcfishpass CSV sync checked 7 files and missed 4 that had drifted. It now covers every copy in the `bcfishpass` and `default` bundles, writes a change only into the bundle that declares the file, and stops when a download fails. A change that moves an output token's spec, or that leaves a bundle failing to load or loading only with a warning, becomes the new `review` kind: a `token-review` PR the workflow does not merge.

Link's own changes to a copy now sit beside it as an overlay: `files: <key>: overlay:`, one row per cell with its reason, applied by `lnk_load_overrides()`. The `bcfishpass` bundle's presence table is bcfishpass's copy again, and link's `ko` column moved into `overrides/wsg_species_presence_overlay.csv`. The move left the loaded tables `identical()` to before and every token unchanged. An added column is inserted in sort order, because column order reaches the readers.

The sync then pulled bcfishpass at `3bd2824`:
- CH in UTRE and ST in QUES, so `acc-bcfp-4` replaces `acc-bcfp-3`;
- the Keogh and Adams passability rows;
- three `wcrp_watersheds` lines;
- `cabd_blkey_xref.csv` without link's added newline (the loader now muffles the warning for a missing final newline instead).

What was learned:
- **The dam rows reach nothing.** Neither id is in `cabd.dams` in either database.
- **The sync's crate schema check had never run** (it read a key no provenance entry has). Turning it on exposed two more defects: the function it called is no longer exported, and a check that catches only errors lets a parse warning through. Code-check rounds 2 and 3 each found the next defect inside the previous fix.

Mid-plan, the operator moved `ko` into an overlay rather than comparing around it, so link's departures from bcfishpass stay legible.

## Measurement

- **Dry run before**, on `main` against the same dump: "No drift detected". On the branch, drift in exactly 4 files: presence in `bcfishpass`; `cabd_blkey_xref`, `cabd_passability_status_updates` and `wcrp_watersheds` in both bundles. Kind `review`, because `bcfishpass`'s `acc` spec moved to `sha256:970ea40b…`.
- **After the write:** every copy in both bundles is byte-identical to the dump, and the dry run reports none.
- **Loaded tables before and after the sync:** `bcfishpass` presence changed only at UTRE `ch` and QUES `st`. Passability went from 12 to 14 rows in `bcfishpass`, `default` and `default_tuned`. `cabd_blkey_xref` loads identically without its newline. `default`'s presence file is byte-unchanged.
- **Dams:** `cabd.dams` holds 2,592 rows in local fwapg and in the reference at `v0.7.15-51-g3bd2824c`, and neither updated id is among them. Keogh Dam (`242fa0e4`) is still `BARRIER` in NIMP in bcfishpass's own build. The CABD API has no `298b0f7e`, and lists `1c16395b` as a decommissioned dam. Parity cannot move, so nothing was re-modelled.
- **Plan review:** 3 blockers, 3 ordering points and 7 gaps, each with its disposition in `review-plan.md`. The overlay first appended `ko` at the end (B1); fixed.
- **`/code-check branch`:** 3 rounds, ended by the enumeration in `review-round3.md` (26 verdict points, each OK after the round-3 fix). Each round found one real defect: round 1 a pre-existing one, rounds 2 and 3 each inside the previous fix.
- **Full suite** before the review: 1,299 tests, 0 failed.

## Evidence

`data-raw/logs/csv_sync_429/` (dry runs before, after and on main; the sync write and its PR summary; the loaded-table diff; `dams*`).

## Owed

- Draft the link issue "`default` presence as copy plus overlay; #402 decisions as overlay rows", for your word.
- Re-model UTRE and QUES in the `fresh` (bcfishpass) schema at the next provincial run (#377's runs row).
- Post the Keogh `cabd_id` note upstream, on your word only.
- Report, unchanged: the older copies in `default_extrabreaks` and `default_rearbreaks`. (The dead `user_modelled_crossing_fixes_20240825.csv` was deleted from `bcfishpass` and `default` instead, Plan review B3.)
- Re-run the pre-run gate (#372) before the next provincial run: `R/` and `inst/extdata/` changed (Plan review G4).

Closed by: PR for #429 (branch `429-weekly-csv-sync-skips-four-copied-bcfish`)
