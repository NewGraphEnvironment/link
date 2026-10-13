# Code-check round 2 — branch 328-build-dunc-into-fresh-default (base 2edc4105)

Reviewer: subagent, 2026-10-12. Read-only SELECTs against local fwapg, `git show` / `git diff`
between commits, and a read-only `gh issue view 328`. No repo file changed except this one.

## Round-1 fixes: hold

- **CLAUDE.md density split.** Recomputed (`fresh_default.streams` count / `fwa_stream_networks_sp`
  count per group): 56 groups. KOTL 4.30, LARL 3.99, SLOC 3.60, PINE 2.86, DUNC 2.79, PARS 2.62;
  CHWK 1.538; the other 49 are all under 1.5 (HARR 1.497 the highest). 49 + 1 + 6 = 56, and "2.6 or
  more" holds.
- **task_plan Phase 2 log-row box.** Every field it names is in the printed log row in verify.txt
  (link_sha `8215d2d`, link_dirty f, fresh_sha, fwapg_sha, schema_persist, run_label, date_end), and
  run_uid is stated as NULL.
- **task_plan Decided paragraph.** KOTL / SLOC `322389a` `3cfde7…`, LARL `8c8c29b` dirty `44e452…`:
  matches `fresh_default.log`.

## Re-checked and holds

- Log rows: exactly PINE (2026-08-06), LARL, KOTL, SLOC (2026-08-27) and DUNC (2026-10-12).
- `fresh`: 98 / 59 / 39 groups in streams / streams_access / log. Every group with a log row has
  streams_access rows (none contradicts "stale, not broken"). `fresh` has 0 DUNC rows in
  streams_access, streams_mapping_code and log; streams and streams_habitat_bt still 26,827.
- verify.txt: 19 PASS lines; all figures in README match it.
- `default`'s YAML `schema: fresh` (config.yaml:80); `wsg_run_one.R` reads `LNK_SCHEMA`.
- "six FWA tables logged for both": the intersection of KOTL's and DUNC's `fwa_%` inputs is six.

## Findings

- **[doc]** data-raw/logs/dunc_default_328/README.md:37 (also planning/active/task_plan.md:5, and the
  #328 issue body's "Vintage" bullet) — states DUNC's habitat flags follow current rules "(#282
  thresholds, #307 MAD ranges, #310 lake rearing, #311 wetland floor), and theirs do not". Two of
  the four do not change DUNC's flags:
  - #307: DUNC is `cw` (`inst/extdata/configs/default/parameters_habitat_method.csv:37`; all 188
    rows are `cw`). MAD ranges are inert on a `cw` group; CLAUDE.md's own #307 entry says "`cw`
    moves nothing".
  - #282: for BT, WCT and RB, every gradient and width threshold in today's
    `configs/default/parameters_habitat_thresholds.csv` equals fresh v0.33.0's
    `parameters_habitat_thresholds.csv` (the August builds' source). The only differences are the
    BT / RB `*_mad_*` columns (#307 again, inert under `cw`).
  The rules that do differ for these species are #310 (`rear_*_connected_distance_max`, added to
  `dimensions.csv` between `322389a` and `8215d2d`) and #311 (fresh 0.38+ wetland floor). A reader
  told that #282 / #307 make the flags differ will look for a threshold effect that is not there.
  Fix: cite #310 and #311 (and the fresh 0.33 → 0.39 bucket changes, if wanted), drop #282 and #307.

- **[doc]** #328 issue body, "Vintage differs" bullet — "built 2026-08-27 at link 0.45.1
  (`322389a`, LARL from a dirty tree)" attaches LARL to `322389a`. LARL is `8c8c29b` (dirty), hash
  `44e452…`. This is round 1's third finding (fixed in task_plan) reproduced in the issue body,
  which is the spec a reader sees first.

- **[doc, minor]** planning/active/progress.md:12 — "segments-per-FWA-line split (49 of 56 groups
  sparse)". With six dense groups and CHWK at 1.54, sparse is 50 if CHWK counts as sparse, or the
  49 are "under 1.5"; "49 of 56 sparse" leaves one group unaccounted for, which is the CHWK
  omission round 1 fixed in CLAUDE.md, one file over. Fix: "49 of 56 under 1.5".

- **[doc, minor]** data-raw/logs/dunc_default_328/README.md:30 — "The data is the same" rests on the
  six FWA tables both rows logged. DUNC's row also logs `fwa_obstructions_sp` and
  `fwa_stream_networks_discharge`, which KOTL's row does not carry (KOTL logs `fwa_obstacles_sp`
  with NULL counts), so those two are unverified. Non-FWA inputs did move between the builds:
  `fresh.modelled_stream_crossings` 524,562 rows (DUNC) vs 529,244 (KOTL), `bcfishobs.observations`
  373,050 vs 372,690. Not false as scoped to the six tables, but "The data is the same" reads wider
  than the evidence; scope it to "these six FWA tables". (The crossings / observations difference is
  a further vintage difference the "Vintage" section does not mention.)

No bugs or security issues in verify.R; no infra identity beyond what the caller listed as accepted.
