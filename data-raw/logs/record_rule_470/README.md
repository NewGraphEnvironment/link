# Which fish records count, and what each lift rests on (#470)

Backlog move 2: one rule for which bcfishobs records make code 2, cut streams and lift
barriers (#400, #398, #425), and each lift published with the records behind it (#434), with
the lift date test (#426) and `default`'s salmon threshold (#427). Mechanics: RUNBOOK §7,
"The record rule"; §5, the lift floors and the evidence table; §2c, which records cut.

## Run decision (2026-11-16)

- **Host:** m1's local docker fwapg; bcfishobs 375,962 records (`bcfishobs.txt`, unchanged across
  both legs). Scratch schemas only: `zz470_default_{pre,post,head}`, `zz470_bcfishpass_{pre,post}`,
  `zz470_lifts`, `zz470_verify_ev`. Never `fresh` or `fresh_default`.
- **Code:** BEFORE at `2da2db35` (origin/main, link 0.83.0), AFTER at `09e8339d` (Phase 2: the record
  rule alone, provisional `acc-v6` / `acc-bcfp-5` specs), HEAD at `c67fc991` (Phases 2 and 4: the
  evidence table and `default`'s 2-record salmon lifts), each from its own git worktree under `load_all`.
- **Groups:** `default` LSKE, KLUM (drains into LSKE), SQAM, HOMA, VICT, MFRA, UFRT, FINA (the alias
  groups of #425, and coastal and lower-Skeena groups where DV lifted BT); `bcfishpass` BULK, PARS
  (parity) and SQAM (CT aliases). HEAD: `default` LSKE and SQAM.
- **Flags:** `wsg_run_one.R` with `LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn`, the habitat gate at
  model time, no recompute. Each leg after five minutes with no other client (`run.sh`).
- **The numbers below are at the AFTER build's spec** (the record rule only). #426 and #427 came after,
  and the released `acc-v6` / `acc-bcfp-5` specs include them; their effect is measured by the lift
  harness and the HEAD builds.

## What bcfishpass does with alias records (Phase 1)

bcfishpass's `load_observations.sql` tests a record's own code against the presence table's codes
(`smnorris/bcfishpass@620dbe4`, unchanged at `3bd2824`), so its `species_code_remap` of `CCT`, `ACT`
and `CT/RB` renames only records already coded `CT`. On its output (the local copy of
`streams_vw_bcfp`, unversioned; the current build is `v0.7.15-51-g3bd2824`), the keys in its
`observation_key_upstr` arrays in SQAM, LFRA and VICT hold 2,921 of 2,963 CT records, 5,480 of 5,518
CO, and 0 of 2,004 alias records (`CCT` 1,276, `ACT` 727, `CT/RB` 1). Its species arrays hold no
alias code. So the `bcfishpass` bundle now drops them.

## What the record rule moved (`pre_post_diff.R`)

Records counted under one rule and not the other, province-wide (`records_diff.csv`), each as the
species it counts as: `default` adds BT 4,959 (DV records where the tracker pools DV into BT, which
before counted only as DV and through BT's lift list; `BT/DV`, `DV/BT` and `ABT`), ST 631 (`SST`,
`WST`) and DV 78 (`ADV`), and drops pre-1990 records of CH 2,346,
CM 2,215, CO 5,380, PK 2,000, SK 1,862, ST 8,407, GR 762 and KO 213. `bcfishpass` drops CT 4,484 (the
aliases).

Access that moved, km (`transitions.csv`, pieces of at least 0.5 km summed per group and species):

| group | BT 1→0 | salmon and ST 2→1 | GR 2→1 | 1→2 |
|---|---|---|---|---|
| LSKE | 216.2 | 1,172.4 (CH 201, CM 259, CO 172, PK 225, SK 136, ST 181) | | |
| KLUM | 168.0 | 423.8 | | |
| SQAM | 253.5 | 216.5 | | |
| HOMA | 7.9 | 366.2 | | ST 10.4 |
| VICT | | 21.9 | | |
| UFRT | | | 167.9 | |
| FINA | | | 37.4 | BT 17.9 |
| MFRA | | | | |

- **BT 1→0** is decision 2: DV records no longer lift BT barriers where the tracker does not pool DV
  into BT. The groups' BT lifts (`lifts.csv`): LSKE 61 → 0, KLUM 123 → 4, SQAM 160 → 13, HOMA 57 → 5.
- **2→1** is decision 1: salmon, steelhead, GR and KO records dated before 1990 no longer make code 2.
- **1→2** is the aliases: FINA BT under `ABT` and the two-way char codes (the Mackenzie pools DV into
  BT), HOMA ST under `WST`.
- **`bcfishpass`:** no access moved. Segments fall where the CT alias cuts go (SQAM 33,203 → 33,137;
  BULK 42,989 → 42,988; PARS unchanged).
- **`default` segments** fall 0 to 1.5 % (`segments.csv`): fewer tops where pre-1990 salmon records and
  aliases that now merge into their species' top stop cutting.

Every changed piece is traced to a record one rule counts and the other does not (upstream of it, for
a 1↔2 change), to a lift that changed (0↔1/2), or to a cut that moved at such a record (a piece under
2 m). Six pieces were left by the script, all one 1 m strip in HOMA, traced by hand: on line
360809896 CT's own top record sat at 104 m and cut there before; its `CCT` records reach 468 m, so
under the record rule CT's top is 468 m and the cut at 104 m goes, and the salmon gradient barrier at
104.56 m then cuts at 105 m (it was within 1 m of the old cut, so it was skipped). The strip
104 to 105 m changes segment, and the salmon read 1 there instead of 0. Both rules count the `CCT`
records as CT, so the script's record sets cannot see a merged top; the trace is the evidence.

## #426 and #427 (`lifts_426_427.R`)

The lift harness runs `lnk_barrier_overrides()` at HEAD's code over each group's persisted natural
barriers and the province's records under the record rule, with the group's
`barriers_definite_control` rows as the control table, as prepare passes them (observation lifts
only). Its first run left control out, which lifted the HARR control falls at 356354346 @ 8,876 m
at threshold 2 and read HARR as +9 (≤ 282 km); the operator chose 2 on that table, and the
corrected HARR row is +8 (≤ 36 km). Code-check round 3 found it.

- **#426** (`lifts_426.csv`): the `bcfishpass` bundle's lifts with salmon and steelhead floors at
  `>= 1990-01-01` and `> 1990-01-01` are identical in BULK, PARS, ADMS, BABL, ELKR, CHWK, HARR, LFRA,
  LSKE and KLUM. The change is parity with bcfishpass's SQL; it moves no observation lift there.
- **#427** (`lifts_427.csv`): `default` with CH, CM, CO, PK, SK, ST, GR and KO at 5, 2 and 1 records.
  Lifts added per salmon species over 5, with an upper bound on blocked km above them
  (`fresh_default` 0.78.2's `access_<sp>` = 0):

  | group | at 2 | at 1 (on a single record) |
  |---|---|---|
  | SQAM | +22 (≤ 468 km) | +75 (53) (≤ 1,483 km) |
  | LSKE | +7 (≤ 579 km) | +15 (8) (≤ 625 km) |
  | HARR | +8 (≤ 36 km) | +41 (33) (≤ 359 km) |
  | MORR | +0 (ST +8) | +7 (7) |
  | BULK | +0 | +2 (2) |

  The operator chose 2 (2026-11-16).

## What each lift rests on (`verify_evidence.sh`)

HEAD builds of LSKE and SQAM write `barrier_override_evidence`. The evidence block of
`study_area_verify.sql`, cut out by its own comment lines, passes on them, fails with a lift's evidence
deleted, fails with an evidence row beside no lift, passes restored, and fails with a lift below its
threshold (`verify_evidence.log`). The full negative script (`study_area_verify_negative.sh`, cases
6j to 6l) needs a recomputed, pinned run and waits for the next provincial run.

## Files

- `run.sh`: the BEFORE and AFTER builds; `status_{pre,post}.tsv`, `{pre,post}_<config>_<WSG>.log`,
  `driver_{pre,post}.log`, `bcfishobs.txt`.
- `pre_post_diff.R` → `segments.csv`, `lifts.csv`, `transitions.csv`, `records_diff.csv`,
  `unexplained.csv`, `pre_post_diff.log`.
- `lifts_426_427.R` → `lifts_426.csv`, `lifts_427.csv`, `lifts_stamp.txt`, `lifts_426_427.log`.
- `verify_evidence.sh` → `verify_evidence.log`; HEAD builds `head_default_<WSG>.log`, `status_head.txt`.
