# streams_parent_444 — each full segment's minimal parent, province-wide (#444)

Built 2026-11-03 on m4's local fwapg, from link `a97044e2` (clean tree, `load_all`), fresh 0.52.0 installed:

```
Rscript data-raw/streams_parent_build.R --schema=fresh_default --schema-minimal=fresh_default_minimal
```

`--out` defaulted to this directory then. It has no default since, and it refuses a directory that already holds the files a run writes, so a later run goes to a directory of its own.

| file | what it holds |
|---|---|
| `pair.tsv` | the judged pair, one row per side: schema, groups, config, `config_hash`, `link_sha`, `fresh_sha`, the four tokens, `run_uid`, the commit that judged it, and the verdict |
| `build.tsv` | one row per group, in build order (largest first): minutes, full and minimal segments, km, segments straddling a minimal cut by 1 cm or more, their km, the largest straddle |
| `verify.tsv` | `--verify` right after the build: per group, the newest builds against the rows' provenance, segments without a row, rows without a segment, rows off the segment's length, and why a group is stale (empty for all 241) |
| `prototype_check.R`, `prototype_check.csv` | acceptance 2: the table against #415's `minimal_breaks_415/parent_<wsg>.csv.gz` on BULK, SETN, MORK and COTR |

## Result

- **The pair passed.** `fresh_default` (run `20261103_163715-269b585a`, link `4dfbfa49`, `cut-full-top`) on `fresh_default_minimal` (run `20261102_203300-60ab009d`, link `193cb8aa`, `cut-min`), both fresh `245c8d8d`, `acc-v5 grad-seg q-fwapg`, the same species in every group. Between the two commits only `DESCRIPTION` changed on the modelling paths, and it maps `none`.
- **All 241 groups built, in 3.9 min summed** (the longest, TESR, 0.05 min). `fresh_default.streams_parent` holds 5,546,370 rows, one for each segment of `fresh_default.streams`, on 4,987,761 minimal segments and 1,887,603 km.
- **Every minimal cut has a full cut within 1.01 m in every group.** 96 full segments straddle a minimal cut by 1 cm or more, 0.096 km in all, and none by more than 1.000 m: the full build skips a cut within 1 m of an existing end (RUNBOOK §2), and those are the cuts it skipped.
- **`--verify` found all 241 groups current** right after the build.
- **The table equals the prototype** on the four proof groups: the same rows (42,458, 80,538, 51,930 and 28,473), the same parent id for every segment, gradients identical, lengths within 5.5e-12 m. The length guards hold for every CSV row, so the proof's ids name the same segments in today's builds.
