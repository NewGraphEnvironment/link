# The presence review's second pass (link#501, #402, #497)

`data-raw/wsg_species_presence_check.R --seed-tracker
--out=data-raw/logs/presence_check_501
--evidence=data-raw/logs/presence_check_402/evidence`, run on m1 on 2026-11-23
at `4a3df5ed` (rainbow trout modelled again, and steelhead records counting as
rainbow trout under the record rule). The zones are the ones fetched for #402.
Files as in `presence_check_402/` (its README describes each).

**Before:** the tracker held 351 rows, 154 pending (138 KO on #432, 3 RB on #497,
13 others on #402); RB had 3 rows. **The re-run** flagged 235 cells and seeded 5
new rows: FINA ST, MFRA BT, UFRT ST (one record each under an alias code), TUTR
RB (two Steelhead Database records counting as RB) and UFRT RB (one `WST` record
counting as RB). VICT DV, removed at the first review, read `absent_recorded`
again on one `ADV` record.

**Decided** (owner, 2026-11-23; `wsg_species_presence_review.csv`, and overlay
rows where a cell leaves bcfishpass's copy):

- added: BT in CHIL, CLWR, EUCH, LKEC, LSAL, MUSK, SALR, STUL (DV records pooled
  into BT), MFRA (one `ABT` record); DV in VICT (the overlay row that removed it
  is gone, so the cell reads as the copy);
- kept absent: CT in FINL and LOMI, ST in FINA and UFRT (Mackenzie basin);
- removed: RB in LPRO and UPET (stocked fish only);
- to the literature, #515: CRYL RB, UFRT RB, TUTR RB, TURN ST, CLRH CT, DUNC CT.

**After:** 356 rows, 144 pending: 138 KO, moved from #432 (closed) to #516 (kokanee's return), and 6 on #515. `after/` is the
check re-run on the decided tables.
