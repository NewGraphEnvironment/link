# Plan review (#290), Plan agent, 2026-09-26

The agent is read-only, so its reply was transcribed here. Triage is in the right-hand column.

| id | finding | triage |
|---|---|---|
| B1 | `obs_ledger.csv` step 3 is province-wide; the DV row goes 8888 → 6138 (Skeena 3228, Fraser 1294, Mackenzie 1044, Columbia 572; 2750 coastal/northern drop) | Adopted as the acceptance: every CSV identical except that ledger row = 6138 (independently predicted here before the review arrived) |
| B2 | `stamp.txt` embeds the date and SHA; PNGs not guaranteed stable | Adopted: stamp excluded, PNGs compared visually |
| B3 | a data.frame passes `is.list()`, so `species_obs` silently maps species to themselves | Fix: branch on `is.data.frame()` first and check the columns |
| G1 | the validator's data-frame semantics: own presence ∩ df; missing (wsg, sp) → self; dedupe | Adopted |
| G2 | resolve over the union of both bundles' WSGs | Already done in the driver |
| G3 | stamp which pooling was applied | Adopted (stamp line); no `summary.csv` column, to keep the byte-identity check |
| G4 | `--pooling` defaulting to the first bundle is a trap | Adopted: default is the first bundle that declares a tracker; stamped |
| G5 | the query script cannot aim at a scratch bundle | Adopted: `--pooling=<config>` |
| G6 | one target per observation | Already asserted in the query script |
| G7 | `wsg_regions.csv` is outside `config_hash` | Adopted: hash it by a fixed name when the bundle declares `species_pooling` |
| G8 | dictionary tests must loop over declaring bundles only | Already done |
| G9 | provenance wording; a checksum bump on every tracker edit | Files live at the bundle root, not `overrides/`; the README row notes the bump |
| G10 | three meanings of "no tracker" | Chosen: the resolver without a tracker = no pooling; the driver falls back to the validator's list default only when no bundle declares one. #290's body gets updated |
| G11 | FISS absence taxa still globally pooled | Out of scope (#284 step 5 plan); covered WSGs are all in pooled regions |
| G12 | the #284 logs README states the method | Adopted |
| O1 | tick Phase 1 | Done in `c76274f` |
| O2 | DB matches the committed stamps; no persist during verification | Noted |
| A1 | DV×BT contact records sit mostly in pooled regions; LFRA, CHWK as `wsg` candidates | Recorded in research |
| A2 | LFRA outlet 100 while its Boundary Bay streams are 900; one sub-region column | Documented |
| A3 | known species = presence columns; bcfishobs `SA`, `C`, `BT/DV` are not poolable | Documented |
| A5 | target-group vs obs-group tie at equal rank; identical duplicates accepted | Documented |
| S1 | `lnk_presence()`'s hard-coded groups are a different concept | Out of scope; a follow-up issue is drafted in the final report |
| S2 | the validator's list default is still a global literal | Noted for later deprecation |
| AC1 | the baseline is 55 + 59 WSGs, not 5 | Adopted: full re-run with knowledge @ 508bf44 if available |
| AC2 | the negative check reaches 9 Skeena WSGs; ledger → 2910 | Adopted |
| AC3 | duplicated Validation line | Fixed |
