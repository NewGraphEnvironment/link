# presence_check_402

`default`'s `wsg_species_presence.csv` judged against bcfishobs, cell by cell (#402). Produced by `Rscript data-raw/wsg_species_presence_check.R --seed-tracker` on local fwapg at link `feaa408c`, 2026-10-31 02:42 UTC; the rule, counts and cross-check are in `stamp.txt`. A second run reproduced every file byte for byte and left the tracker unchanged.

| File | Holds |
|---|---|
| `disagreements.csv` | The 351 flagged cells (24 `present_unsupported`, 327 `absent_recorded`): counts kept, own and pooled, since 1990; oldest and newest year; sources; releases, excluded, undated and pre-1950 records; presence as written and promoted; which species' lifts read the cell; the group's note; the drafted story |
| `cells.csv` | All 3,198 group and species cells, the same columns without the story |
| `groups.csv` | Per group: region, the flagged species each way, the group's note, and records under codes the table has no column for |
| `summary.csv` | Flags by species |
| `alias_sensitivity.csv` | The 4 cells whose flag would change if SST, WST, ADV, ABT, BT/DV, DV/BT, RB/CT and ` RB` counted toward the species they name; diagnostic, not used for any flag |
| `stamp.txt` | Environment, rule, totals, the SQL cross-check (PARS, ADMS, ALBN: 39 cells, 5,423 records, all counts agree) |

The flags were merged into `inst/extdata/configs/default/wsg_species_presence_review.csv`, every row `pending`. Write-up: `research/species_presence.md`.
