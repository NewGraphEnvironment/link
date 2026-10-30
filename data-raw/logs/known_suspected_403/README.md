# Observed and unobserved accessible km (#403)

`lnk_rollup_wsg()`'s default `accessible_observed_km` (`access_<sp> = 2`) and
`accessible_unobserved_km` (`access_<sp> = 1`), measured on #396's five groups, and the
same split against bcfishpass for BULK and PARS. Write-up: `research/known_suspected_km.md`.

## Environment

- **Code that ran:** link `735349e0` (the commit adding the two metrics), from a git
  worktree, `pkgload::load_all()`. `stamp.txt` holds the SHA and the run time
  (2026-10-30 15:05 UTC).
- **Database:** m4's fwapg, the persistent worker where #396's builds live. The host came
  from `LNK_DB_HOST`, never from a file.
- **Builds read** (newest `log` row per group, all closed, `link_dirty` FALSE, fresh 0.43.0;
  full rows in `stamp.txt`):

| schema | config | link | config hash (prefix) | built (UTC) |
|---|---|---|---|---|
| `zz396_default_pre` | `default`, observation breaks `all` | `43e34096` (0.69.1) | `b652bca0` | 2026-10-28 06:56 to 08:58 |
| `zz396_default_post` | `default`, `top_per_species` | `71ccc2ce` (0.69.1) | `780afc0f` | 2026-10-28 07:01 to 08:54 |
| `fresh` (BULK, PARS) | `bcfishpass` | `71ccc2ce` (0.69.1) | `192ddf69` | 2026-10-28 08:29, 08:32 |

- **bcfishpass reference:** `fresh.streams_vw_bcfp` on m4. The `bcfishpass` builds record
  the reference as `smnorris/bcfishpass@v0.7.14-113-ga7373af` (`bcfp_pin_source` ledger).
  The view carries no version of its own.

## Files

| file | what it is |
|---|---|
| `rollup.R` | Runs the default rollup on both `default` schemas for every modelled species (an `access_<sp>` column and habitat table, not -9 everywhere in the group), asserts the identity on every row, then reads the split against the reference view for BULK and PARS |
| `rollup.csv` | 50 rows: schema, group, species, the six default metrics, `share_observed` |
| `parity_bcfp.csv` | BULK (BT, CH, CO, PK, SK, ST) and PARS (BT): link's `bcfishpass` build against the view, accessible, observed and unobserved km |
| `parity_pieces.sql` | Classifies the km where the two disagree on code 2: measure overlaps per `blue_line_key`, pieces under 1 cm dropped, and whether link's segment starts within 1 m of a record of the species on the same line |
| `parity_pieces.csv` | Its output for the seven pairs above less ST |
| `stamp.txt` | Commit run, run time, the builds' log rows |

## How it was run

```bash
git worktree add <wt> 735349e0
cd <wt> && LNK_DB_HOST=<host> Rscript <link>/data-raw/logs/known_suspected_403/rollup.R
# per group and species:
psql -h <host> -U postgres -d fwapg -At -F, -v wsg=BULK -v sp=co -f parity_pieces.sql
```

The identity held on all 50 rows (largest gap 0.010 km, the two-column rounding bound);
no row had an empty accessible set.
