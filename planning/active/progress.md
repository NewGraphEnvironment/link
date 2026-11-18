# Progress — Backlog move 4: default's presence table as bcfishpass's copy plus an overlay (#472)

## Session 2026-11-18

- Plan-mode exploration — phases approved by user
- Created branch `472-backlog-move-4-default-s-presence-table` off origin/main
- Claimed move #472 (in-flight label)
- Scaffolded PWF baseline from issue #472 with approved phases
- Next: start Phase 1
- Phase 1 (#292): `presence_groups.csv` in `default` and `bcfishpass`, `.lnk_presence_groups()`, every `lnk_presence()` caller passes it; all five live bundles still resolve to their tokens (acc-v6, acc-bcfp-5); tests in test-lnk_presence.R and test-dictionaries.R; the caller guard fails when one call drops `groups =` (mutation checked)
- Phase 2 (#431): `default`'s presence table is bcfishpass's copy byte for byte; `wsg_species_presence_overlay.csv` holds 126 rows (110 added, 10 removed, 2 kept absent, 4 ko), built by `data-raw/logs/presence_overlay_431/build_overlay.R`, which stops unless the species cells come back; loaded `default` and `default_tuned` species cells digest identical before and after (computed in a worktree at the pre-conversion commit, pinned in test-lnk_csv_sync.R); both still `acc-v6`; sync dry run clean in both bundles (upstream v0.7.15-51-g3bd2824)
- Phase 3 (#436): `observation_exclusions_link.csv` (the three #402 records) unioned by `.lnk_observation_exclusion_keys()`; default excludes 214 keys, bcfishpass 211; tokens unchanged. Plan review landed (review-plan.md): B1 already fixed, B2 pretest map rows added, G1-G6 and AC2 folded (overlay regenerated with the rule in each reason, from the pre-conversion commit in a worktree)
- Presence check re-run at ab5020e9 (`data-raw/logs/presence_overlay_431/presence_check/`, tracker not seeded): 233 flags from 351; 111 adds and 9 removes dropped out, MESI SK too (its record excluded); KOTL ST 3 -> 2 records; VICT DV, FINA ST, MFRA BT, UFRT ST read differently since #470's alias codes
- #497 filed (rainbow trout's return) on the operator's word; CRYL, LPRO, UPET RB tracker rows point at it; #402's body edited with what is left
- Models at main vs head (ADMS, BULK, GUIC; zz472_* scratch, dropped after): 53 of 54 table x group pairs identical; GUIC access_ch 2 -> 1 on 227 segments, 52.3 km (the excluded CH record). First main try stalled in ADMS frs_near_river_walk 34 min (no bound): recorded for #487 (TSV, README, body reading)
