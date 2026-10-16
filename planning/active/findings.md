# Findings — Provenanced province-wide `default` run (#246)

## Issue context

**If done:** `fresh_default` holds a `default` build of all 217 modelable watershed groups, every row traceable to one
run, its code and its inputs, so threshold calibration can be scored wherever a species occurs (#346), and a
`bcfishpass` parity check confirms the engine at the same code. **If never:** `fresh_default` stays at 56 groups with
provenance on 5, and every calibration drops the groups it does not cover.

*Rewritten 2026-10-16. The 2026-08-30 body planned a `bcfishpass` rerun of the 119-group closure on four hosts. #256
widened the scope to all 217 modelable groups, and Phases 1-2 shipped. The run is now `default`, because that is what
calibration and the product read; `bcfishpass` drops to a parity check on its comparison suite, since nothing
downstream needs it province-wide. The original body is in this issue's edit history.*

## Where things stand (2026-10-16)

- **Gates are done and proven.** Phases 1-2 shipped in v0.47.0-0.47.2; a one-host pilot ran clean end to end in 7.0 min
  with full provenance (`research/run_record_2026_08_31_cypher_pilots.md`). Follow-on provenance gaps closed in #257,
  #262 and #264; the recompute is parallel (#250, #205).
- **Scope is 217 groups** (#256): 4.49 M source segments, 1.76× the 119-group closure. Measured rates put the 119 at
  about 150 min of modelling on four hosts, so the 217 is roughly 4.5 h of modelling plus the recompute (an estimate from
  those rates, not a measurement).
- **The province-wide run never happened.** `fresh_default` has stream rows for 56 groups, 5 of them logged (last
  2026-10-12). `fresh` (`bcfishpass`) has 98 groups, 39 logged (last 2026-09-26, link ≤ 0.50.0); it stays as it is.
- **The code has moved.** link is at 0.66.0. The gates were proven at 0.47 on `bcfishpass`; since then the discharge
  source became a bundle setting (#331; `default` reads fwapg, so no wet load is needed) and `default`'s thresholds
  changed (#307). The gates themselves do not depend on the config.
- **Primitives are stale.** They were refreshed on 2026-08-31 and fail the 7-day vintage gate today.
- **The host split is for the old scope.** `research/study_areas.md` packs the 119-group closure; it has not been
  generated for 217.
- **No wipe.** Persist replaces per group, so the run overwrites every existing `fresh_default` row with a provenanced
  one, provided every group now in it is in the 217 (checked in Phase 3).

## Phase 1 — unblock (done, v0.47.0)
- [x] Cloud-host prep installs fresh from a pinned ref, so the baked image version is never load-bearing
- [x] Assert the installed fresh exports `frs_wsg_drainage` / `frs_wsg_outlets` before any group runs

## Phase 2 — pre-flight gates in `study_area_run.sh` (done, v0.47.0-0.47.2)
Each fails toward stop, not skip, and was tested against both known answers.
- [x] Sibling-host version parity: link and fresh version, SHA and dirty state on every host; abort on mismatch
      (`--auto-install` escape)
- [x] Credential probe that forces a real provider API call (a plan against an empty workspace is a false green)
- [x] Primitive vintage: the oldest input table within N days on every host, using
      `GREATEST(last_analyze, last_autoanalyze)`; an absent table or a NULL timestamp fails
- [x] Branch pushed before cloud hosts reset to it
- [x] Persist-schema guard: any config but `bcfishpass` needs an explicit `--schema=`
- [x] fwapg SHA recorded on every host's log row

## Phase 3 — re-baseline at HEAD
- [ ] Refresh primitives (`--refresh-primitives`); the vintage gate passes at its 7-day default
- [ ] Generate the 217-group split: `data-raw/study_area_buckets.R --config=default --hosts=4 --focal=<all modelable>
      --write`, its disjoint-closure and downstream-first assertions passing, host speeds from measured rates (#259)
- [ ] Check every group now in `fresh_default` is in the 217 (`setdiff`), so no stale rows survive the run
- [ ] `study_area_run.sh --preflight-only` at HEAD on every host
- [ ] One-host pilot at HEAD with `--config=default --schema=fresh_default`, so nothing between 0.47 and 0.66 breaks
      the paid run on its first group
- [ ] Optional tidying: orphan `working_*` schemas and `zz_lnk_mc_scratch_*` tables, by `state_clean.sh --schemas=`
      scoped to the orphans (never the unscoped mode, which drops persist schemas)

## Phase 4 — the run
- [ ] `study_area_run.sh --config=default --schema=fresh_default` on the dispatcher plus three cloud hosts, all 217,
      with the Phase 3 split
- [ ] Post-consolidate recompute across all 217 (#274's scope question is moot when every group is in the run)
- [ ] Parity check at the same code: `--config=bcfishpass` on the comparison suite named in that config (ADMS, BULK,
      BABL, ELKR) into a scratch schema, compared against the bcfishpass reference with `lnk_parity_annotate` (#167: a
      dropped reference connection errors per group silently, so read the compare log for gaps)

## Phase 5 — verify provenance
- [ ] `fresh_default.log` has one row per group from this run, all 217, with non-NULL `config_hash`, `link_sha`, `fresh_sha`,
      `fwapg_sha`, and no group's newest row predates the run
- [ ] `fresh_default.log_input` carries per-primitive row counts and `source_at`; `config_drift` FALSE everywhere
- [ ] `log_parameters_fresh` / `log_dimensions` populated (they carry no `watershed_group_code`, so consolidate skips
      them; the dispatcher writes them, which holds only while every host runs one config)
- [ ] `study_area_verify.sql` passes (#268 limits it to runs logged from v0.50.0, which this run is)
- [ ] Run record in `research/` with every host's stamp

## Decided (operator, 2026-10-16)
1. **Config:** `default` province-wide; `bcfishpass` only as the four-group parity check. Nothing downstream needs
   `bcfishpass` province-wide, so `fresh` keeps its current rows.
2. **Stream size:** every group stays on `cw`. Width and discharge are both on every segment, so `mad` rules are scored
   from this run without another; a group moves to `mad` only in `default_tuned`, regenerated from it.
3. **Hosts:** the dispatcher plus three cloud hosts, as designed. A second local workstation is not in this run: joining
   a host that is already up needs a run path that does not exist yet.

## Notes
- **Image residue.** `lnk_persist_init(force_recreate = TRUE)` keeps a baked `fresh.streams` whose DDL is correct, rows
  and all. Bucket-filtered consolidate (#180/#185) is what contains it; the root fix (a fwa-dump-only image) is
  upstream infrastructure work and not blocking.
- link's bcfishpass override CSVs ship in the package and follow the git branch, so they are not a staleness axis.
- Relates to #256 (scope), #346 (calibration that reads this run), #183, #181, #259, #268, #274, #167.



## Planning (2026-10-16)

#246 was rewritten 2026-10-16. The goal is a `default` build of every modelable group in `fresh_default`, with every
row traceable to one run, so #346's calibration can score wherever a species occurs. `bcfishpass` becomes a
four-group parity check at the same code, and `fresh` is left as it is. Phases 1–2 (the gates) shipped in v0.47.x.
The plan below follows the body's Phases 3–5, with the operator's decisions and what planning measured.

**Decided (operator, 2026-10-16)**
- `default` province-wide; `bcfishpass` only on ADMS, BULK, BABL and ELKR.
- Every group stays on `cw`.
- Hosts: the dispatcher plus three cloud hosts.
- **Scope: 241 groups, not 217.** 217 is bcfishpass's modelable set. `default` adds KO, RB and GR, which brings in 24
  more groups (ATLL … UPET, including the six the old body dropped: LEUT LFRT LKEC LNRS MFRT UFRT). The two issue
  bodies get corrected.
- **Disk:** grow colima to 600 GiB. Every `score*` / `working_score*` schema is kept.

**Measured during planning (read-only)**
- `study_area_buckets.R --config=default --hosts=4 --focal=<all 246>` gives 241 modelable and 4.84 M source
  segments. The split is 117 on the dispatcher, then 40 / 41 / 43 on the three cloud hosts, balance 100 %.
- **No stale rows can survive.** All 56 groups now in `fresh_default` sit inside the 241, with no orphans.
- **The disk is a blocker.** The fwapg volume is 295 G and 92 % used, with 26 G free. A 241-group `fresh_default` is
  roughly +120 GB (about 8 KB per persisted segment). The host has 706 GB free.
- **Estimate**, from August rates (an estimate, not a measurement):
  - ~4.7 h of modelling on each host, plus ~1 h of recompute at `-j4`;
  - ~6 h wall clock and ~$3 of cloud-host time.
- **#276 (open):** cloud hosts pull primitives at spin, and the dispatcher only does with `--refresh-primitives`.
  Launch the same day, then assert that every host read identical `log_input.artifact_*` version ids.
- `study_area_run.sh` runs dispatcher-only when `--cy-workspaces` is empty, which serves both the pilot and the
  parity check.

## Errors Encountered

| Error | Resolution |
|-------|------------|
