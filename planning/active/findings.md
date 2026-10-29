# Findings — Adopt fresh v0.46.0: the walk prefilter (fresh#272) in the recompute (#409)

## Issue context

**If we do it:** every group's recompute walk reads only the features that can reach the group. #261 estimated that cuts 36 to 51 % of the recompute's summed work on every provincial run, and it unblocks #394. **If we never do:** each walk keeps probing the group's segments once per feature in the province, so CHWK costs 18 times what SALR does.

- Bump `DESCRIPTION`'s fresh floor and `Remotes:` pin from v0.44.0 to v0.46.0. v0.45.0 carries NewGraphEnvironment/fresh#272 (fresh PR #276). v0.46.0 makes fresh's connectivity passes match `watershed_group_code` (NewGraphEnvironment/fresh#242).
- **Outputs should not move.** fresh#272 returned the same features in 32 of 32 walks. link's habitat tables hold one group each, which fresh#242's fix leaves alone. Check this with per-table digests on a few groups built before and after.
- **Measure** with `data-raw/logs/recompute_cost_261/` on CHWK, SALR and SETN, and fill #377's line.
- Hosts need the new fresh, re-prepped with `--auto-install` (RUNBOOK §8d).

## Library isolation

`pak::pkg_install(lib = <scratch>)` installs every dependency it resolves into that library too (26 here: RPostgres, sf, DBI, …), so an `R_LIBS` arm would differ from the shared one in more than fresh. Keep only `fresh/` in the scratch library and check `find.package()` for the others (`data-raw/logs/prefilter_409/model/stamp.txt`, the `[rerun]` header line).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff` reported 0 changed lines for an edited copy | `diff` is a shell function here; use `command diff` |
