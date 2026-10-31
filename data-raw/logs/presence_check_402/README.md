# presence_check_402

`default`'s `wsg_species_presence.csv` judged against bcfishobs, cell by cell (#402). Produced by `Rscript data-raw/wsg_species_presence_check.R --seed-tracker` on local fwapg at link `83e45a71` (`stamp.txt` has the run, the rule, the counts and the cross-check; its `date:` and `link:` lines differ between runs, and its tracker line between a first and a later seeding). The first run, at `feaa408c`, flagged the same 351 cells. The code-check rounds after it rewrote the stories and added the `year_newest_before` and `modelled` columns; the flags, the counts and `groups.csv`, `summary.csv` and `alias_sensitivity.csv` did not move.

| File | Holds |
|---|---|
| `disagreements.csv` | The 351 flagged cells (24 `present_unsupported`, 327 `absent_recorded`): counts kept, own and pooled, since 1990; oldest and newest year; sources; releases, excluded, undated and pre-1950 records and the newest of those; presence as written and promoted; whether the bundle models the species; which species' lifts read the cell; the group's note; the drafted story |
| `cells.csv` | All 3,198 group and species cells, the same columns without the story |
| `groups.csv` | Per group: region, the flagged species each way, the group's note, and records under codes the table has no column for |
| `summary.csv` | Flags by species |
| `alias_sensitivity.csv` | The 4 cells whose flag would change if SST, WST, ADV, ABT, BT/DV, DV/BT, RB/CT and ` RB` counted toward the species they name; diagnostic, not used for any flag |
| `measures.csv` | Per group and species with a counting record (6,111 cells): `.lnk_presence_cell_measures()` of the record measures (part 2): distinct sites, waterbodies and years; records filed under another group's 50k code; records above a blocking natural barrier and the fewest and most counting records of the species' lift pool above one; kokanee above a barrier with no lake above it; lake and known-sockeye-lake records; main-stem records; records on a stream with a historical distribution zone; elevation range; major drainages; the cell's flag. No record is judged |
| `recall.csv` | The 67 `data_error` records of `observation_exclusions.csv` with their measures: what each measure sees of known errors |
| `evidence/` | `hist_zones.csv` ("BC Historical Fish Distribution - Zones (50,000)", from `data-raw/presence_evidence_load.R`) and its `stamp.txt` |
| `stamp.txt` | Environment, rule, totals, the SQL cross-check (PARS, ADMS, ALBN: 39 cells, 5,423 records, all counts agree) and the SQL recount of seven measures for the same groups (counting records, sites, waterbodies, years, own code in another group, barrier below, historical zone; read from bcfishobs, FWA and the zones CSV, not from the measures' tables). Lakes, known sockeye lakes, main stem, kokanee lakes, class above and elevation are not recounted |

Part 2 (the record measures, operator's choice of measures before verdicts) added `measures.csv`, `recall.csv`, `evidence/`, the measure columns of `disagreements.csv` and a measure sentence in each story; the flags and counts did not move.

The flags were merged into `inst/extdata/configs/default/wsg_species_presence_review.csv`, every row `pending`. Write-up: `research/species_presence.md`.
