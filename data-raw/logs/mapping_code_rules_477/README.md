# Mapping codes unchanged by #477 (backlog move 9)

**Verified:** 2026-11-27, m1, local fwapg · **Issues:** #477 (#197, #153, #191, #351, #512, #177, #176, #159, #204)

**Result: 36 of 36 mapping-code digests identical** before (`82cf1d08`, main at the branch point) and after (`e0ebb024`), and **no persisted `access_<sp>` is `-9`** in `fresh_default` or `fresh` (19 columns).

- `parity.R` rebuilds each group's mapping codes from its persisted `streams_access`, `streams_habitat_long_vw` and `streams` with `lnk_mapping_code()`, the inputs `.lnk_mapping_code_persist()` reads, writing nothing, and hashes each `mapping_code_<sp>` with the segment ids. Groups: ADMS, BULK, ELKR, HORS, PARS in `fresh_default` (`default`); BULK, ELKR, PARS in `fresh` (`bcfishpass`; it holds no ADMS or HORS mapping codes). Species, presence and residence are resolved as a run resolves them.
- The two sides ran back to back (15:38:51 to 15:39:09 UTC); the newest `log` rows predate them (`fresh_default` 2026-11-03, `fresh` 2026-11-23), so both read the same persisted rows. BEFORE ran from a `git worktree` of `82cf1d08`.
- `compare.R` writes `compare.csv` (per schema, group and column) and `minus9.csv`.
- **Why the #351 merge change moves nothing persisted:** the recompute passes `species = active` (`lnk_pipeline_species()`, the literal presence cells), a subset of `lnk_presence()`'s group-expanded set, so the scratch access never holds `-9` for a merged column. `minus9.csv` shows none persisted.

Reproduce:

```bash
git worktree add --detach <tmp>/link-base 82cf1d08
Rscript data-raw/logs/mapping_code_rules_477/parity.R --repo=<tmp>/link-base --label=before --out=data-raw/logs/mapping_code_rules_477
Rscript data-raw/logs/mapping_code_rules_477/parity.R --repo=. --label=after --out=data-raw/logs/mapping_code_rules_477
Rscript data-raw/logs/mapping_code_rules_477/compare.R
```
