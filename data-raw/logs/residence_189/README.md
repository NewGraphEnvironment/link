# Residence from `dimensions.csv` moves no mapping code (#189)

`digest.R` builds ADMS's and PARS's mapping codes from `fresh_default`'s persisted
access and habitat twice, into scratch tables: with the residence sets coded before
#189, and with `.lnk_species_residence(lnk_config("default"))`, which reads the new
`residence` column and `rear_no_fw`. PARS holds GR, the one species `default`
classifies that bcfishpass does not.

`digest.txt`, run on m1 on 2026-11-23 (fresh 0.55.1), from the working tree on top of
`be99cac5` that became the Phase 3 commit: both groups give the same sets and the same
row digest (ADMS 15,716 rows, PARS 45,974). The scratch schema was dropped after.
