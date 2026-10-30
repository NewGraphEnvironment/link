# Groups outside a partial run that read it (link#274)

**Question.** A run rebuilds its groups' barrier rows, and a group's recompute walks downstream
through every group's rows. After a **partial** run into a schema that holds more groups, how many
groups outside the run read a group it rebuilt, and can they be recomputed safely?

**Answer.** Many, wherever a run holds a main-stem group: a six-group North Thompson run has 65
readers by `recompute_deps.R`'s line rule, every Fraser group that reads LFRA. Recomputing them is
safe only where their last build matches what the recompute runs now. Since link 0.71.0 a run
recomputes those and names the rest. Today none qualifies in any local schema, so on these
schemas the change names them; after the next provincial run, a partial run at that run's commit
recomputes them.

Measured 2026-10-30 UTC on the local docker fwapg, link at this branch (`9ae7be27` and after),
fresh 0.47.0.

## Measurement

`readers.R` → `summary.tsv` (one row per run and schema), `readers.tsv` (one row per reader).
The line rule regenerated from FWA (`deps_line.tsv`, 73.5 s) equals #374's
(`recompute_early_374/deps.tsv`) row for row.

| run | groups | schema | outside readers | held by the schema | compatible today |
|---|---|---|---|---|---|
| field scope 2026-08-31 | 34 | `fresh` | 78 | 35 | 0 |
| North Thompson 2026-09-03 | 6 | `fresh` | 65 | 32 | 0 |
| parity closure 2026-10-23 | 17 | `fresh_parity361` (scratch) | 85 | 0 | 0 |
| DUNC 2026-10-12 | 1 | `fresh_default` | 1 (KOTL) | 1 | 0 |
| each of the above | | `fresh_default` (all 241) | 78 / 65 / 85 / 1 | all | 0 |

- **Why none is compatible:** `fresh_default`'s readers were all built at `1d00c04c` (0.68.0),
  and `R/` has changed since, as have the config hash, the fresh pin and the fwapg checkout.
  In `fresh`, 30 of the field scope's 35 held readers and 13 of North Thompson's 32 predate the log
  tables (no `log` row at all).
- **The parity closure's scratch schema holds only the run**, so nothing outside it is held.
- **A full run has none:** 2026-10-23's `run_wsgs.tsv` names 241 groups, no SKIPs, and
  `fresh_default` holds no group outside them.
- **The check script reproduces the counts:** `recompute_readers_check.R` over North Thompson,
  the parity closure and DUNC gives 32, 0 and 1 readers, all refused (`check_*.tsv`).

## A reader the owner rule misses (acceptance 3)

`coheld.sql` → `coheld.csv`: 1,864 rows in `fresh_default.barriers` sit on no segment their
holder owns; 1,216 lie downstream of a segment of the group that owns the one they sit on, so
that group's recompute reads them. For nine pairs that row is the only link: the owner rule has
no pair and the line rule does (CLRH→REVL 5 rows, UNRS→LNRS 4, PCEA and FINA→UPCE 3, KOTR→KOTL
3, BULL→KOTL 3, ZYMO→BULK, SALR→LSAL, CARR→QUES 1). KOTL reading KOTR is the classifier test's
fixture; the test also shows the owner rule would miss it.

The line rule errs wide by design: ADMS reads BBAR under it, but BBAR's 23 rows on the Fraser
(`100`) all lie upstream of ADMS.

## Live: a scratch schema, dispatcher only (`live/`)

From a worktree at `27e8089c`, `study_area_run.sh --buckets-exact --config=default
--schema=fresh_274` (dropped afterwards):

| run | what | outside readers | exit |
|---|---|---|---|
| `20261030_050409-473440fc` (`run1_kisk.out`) | KISK modelled | none | 0 |
| `20261030_050720-41d61c31` (`run2_lpce.out`) | LPCE modelled | KISK `recompute`; recomputed under this uid; compare over LPCE only; audit ok | 0 |
| `--recompute-only` of run 2 (`run3_recompute_only_refused.out`) | KISK's `link_sha` set unresolvable first | KISK `refused` (`sha_unresolvable`), named with the re-model, not recomputed | 0 |

`study_area_verify.sql` passes run 2 and labels KISK an outside reader (`verify_run2.out`).
`study_area_verify_negative.sh` is right on every case it can run (`verify_negative_run2.out`;
6c is skipped for a one-host run, which the script counts as a failure by design); on
`fresh_default`'s 2026-10-23 run all 19 cases are right, and against the verifier before this
change the new case 6i fails.

Dead ends: UPET and LPET model only GR and RB, which bcfishpass does not, so the compare fails a
one-group run of either. CARP sits above the Peace dams, whose rows a scratch schema lacks, so
its error-mode downstream check would fail.

Found on the way: `--pretest-note` cannot record into a schema that does not exist yet
(`pretest_override.sql`: `schema "fresh_274" does not exist`); creating the schema first works.
Pre-existing, not changed here.

## Files

- `deps_line.tsv`, `deps_line.log`: the line rule from FWA
- `readers.R`, `readers.tsv`, `summary.tsv`: the measurement
- `check_*.tsv`: the check script over three of the runs
- `coheld.sql`, `coheld.csv`: rows held off their holder's segments
- `live/`: the three scratch runs, their driver output and the verifiers
