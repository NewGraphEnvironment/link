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

## 241-group split (2026-10-16)

- `study_area_buckets.R --hosts=4 --config=default --focal=<all 246> --write`: 246 focal → 62 components, 241 modelable,
  5 dropped by species presence. The overlap, drainage-closed and DS-first assertions all `stop()` on failure; exit 0.
  Report: `data-raw/logs/provincial_246/buckets_default.md`.
- Host speeds left at the default 0.45, which is the measured dispatcher:cypher ratio (1 / 2.23, 2026-08-31 pilots).
  #259's open question (per-group weight ∝ segments has R² 0.64) is not settled by this run; per-WSG times from it are
  new data for #259.
- The generator had typed "not all of BC ... 217 are modelable" into its output; now computed from the focal set and
  config.
- Setdiff: all 56 groups in `fresh_default.streams` are in the 241 (and all 98 in `fresh.streams` in bcfishpass's 217).
  No orphan rows can survive.

## Host speeds (2026-10-16)

From `fresh.log`, run `20260901_234743-6628379d` (bcfishpass, link 0.50.0):

| host | groups | minutes | min per 1k source segments | min per 1k persisted |
|---|---|---|---|---|
| m1 | 19 | 88.1 | 0.219 | 0.093 |
| cypher-job1 | 9 | 24.5 | 0.113 | 0.048 |
| cypher-job2 | 6 | 35.4 | 0.220 | 0.082 |

`default` on m1 at link 0.63.1 (DUNC, 2026-10-12): 0.096 min per 1k source. The 0.45 default came from one 7-minute
pilot. At 0.45, m1 would take 2.06 M segments (~7.5 h) while cloud hosts idled and billed. With equal speeds, each host
takes ~1.21 M source segments, so modelling should run ~2–4.4 h per host.

## Disk (revised by review 1, A5)

`wsg_run_one.R` keeps `working_<wsg>` (`cleanup_working = FALSE`), at ~35 KB per source segment (measured on
`working_score331_*`). The persist is ~5.9 KB per source segment (`fresh_default` 7.3 GB / 1.24 M). For m1's
1.21 M segments, that is ~42 GB of working schemas plus ~21 GB of persist growth for all 241, so ~65 GB against
26 GB free.

## Cross-host input identity is judged only after the spend (code-check round 2)

`preflight_hosts()` checks cloud-host vintage by age and parity by code stamp. Neither compares
`provenance.source_artifact` version ids or row counts between hosts. Cloud hosts snapshot at prep, while the
dispatcher's load can be up to 7 days old, so an upstream change in that window passes every gate. It then fails
`verify_extra.sql` after the run (`cabd.dams` just moved 2,594 → 2,592). For this run: `--refresh-primitives` on the
main run itself, so the loads are minutes apart. The lasting fix belongs with #276: compare `source_artifact` across
hosts in `preflight_hosts()`.

## Pilot (2026-10-16)

- Rates (min per 1k source segments): m1 0.086 over 84,296 segments (4 groups), job1 0.175 over 19,814 (2 groups).
  That reverses the September 34-group run (m1 0.219, cypher 0.113 / 0.220). Equal packing is the minimax choice:
  if cloud hosts are 2× slower, makespan is ~3.5 h on the cloud hosts; if faster, ~4.4 h on m1. The 0.45 split's
  worst case was ~7.5 h.
- FWA identity across hosts: m1's exact `count(*)` is 386,025 lakes and 375,178 wetlands, exactly the cloud host's
  logged values. m1's own logged values (386,429 / 374,560) are stale `reltuples`. Streams: m1 exact 4,907,441, cloud
  4,898,813 (an estimate on an 866k-page table). That is consistent with one FWA load, but streams are not proven
  exactly.
- The cloud host (`s-8vcpu-32gb-amd`) has a 400 GB disk, against ~110 GB needed for FWA + working schemas + persist
  at ~1.21 M segments.

## The run (2026-10-17)

run_uid `20261017_004619-3f4c713b`, label `provincial-241-default-246`, launched 00:46 UTC 2026-10-17, driver exit
09:34 UTC (8 h 48 m). Logs: `data-raw/logs/provincial_246/run*`, `data-raw/logs/study_area_run/20261017_004619_*`.

**Modelling** (`fresh_default.log`, `date_start` → `date_end`):

| host | groups | span | minutes |
|---|---|---|---|
| job1 | 49 (+ KITR failed) | 01:05–03:56 | 171 |
| job2 | 55 | 01:05–04:33 | 207 |
| job3 | 59 (+ UPET failed) | 01:05–05:42 | 277 |
| m1 | 76 | 01:05–04:50 | ~225 |
| m1, re-run at `a17e9177` | KITR, UPET | 06:40–06:49 | 8.4 |

Equal packing was right in direction: the slowest cloud host (277 min) finished 52 min after m1. The pilot's minimax
range was 3.5–4.4 h; the makespan was 4.6 h.

**What went wrong, and what was done:**
1. **The driver counted 18 finished groups as missing** (2 on job1, 12 on job2, 4 on job3). `bucket_done()` matches
   `^\[wsg_run_one\] … done` at the start of a line, and an R warning flushed without a newline put the marker
   mid-line (`8: In st_read.DBIObject(…) :[wsg_run_one] FIRE done in 4.6 min`). The driver consolidates only what
   it counted and burns the hosts right after, which would have destroyed the 18 groups' only copy.
   - Each of the 18 was on its host with one `log` row for the run_uid and its `streams` rows (queried on the hosts).
   - The operator paused the driver (`kill -STOP`; auto mode refused it as "Interfere With Workloads"). The 18 were
     consolidated with the driver's own `schema_consolidate()` call (`_consolidate_recover18.log`, ok on all three
     sources), then the driver resumed. Filed as #347.
2. **KITR** (job1) failed at persist: `duplicate key … barriers_pkey (203838, KITR)`. The xref row for PSCIS 203838
   sets both `modelled_crossing_id` and `linear_feature_id`, so both insert branches emitted it. Two of the xref's
   3,657 rows have that shape; the other, ATNA 203324, modelled without a duplicate in this run (why is not checked).
   Fixed: one row per `stream_crossing_id`, Branch A first, as bcfishpass's `ON CONFLICT DO NOTHING` keeps it.
3. **UPET** (job3) failed at persist: `column "access_rb" is of type integer but expression is of type boolean`.
   RB is present in UPET with no barrier in the AOI, so `has_barriers_rb_dnstr` is all NA ("no data", which the
   mapping code reads) and `ifelse(NA, …)` returns logical. Fixed: a present species with no barrier is accessible
   (1, or 2 where observed upstream). The mutation test fails with the line removed.
   - Only groups that would have failed are affected: any group with this case failed the integer insert before.
4. **One failed group would have skipped the recompute for all** (#348). The coverage gate `exit 1`s before the
   recompute, so resuming with KITR and UPET missing would have left 239 groups unrecomputed. Re-running them before
   resuming is what avoided it.

**Provenance consequence:** one run_uid, two link SHAs. 239 groups stamp `ee21eb13`; KITR and UPET stamp `a17e9177`,
which differs from it only by the two fixes. `link_dirty` is false on every row. fwapg `f9718cb`, bcfishobs
`08630cf` and the bcfp pin `v0.7.15-50-g620dbe4` are the same on every row.

**Recompute:** 241/241, 06:56–09:30 UTC, 154 min at `-j4`. The plan's ~1 h estimate (August's ~10 s per group,
serial) was low by about 2.5×; the median job here took 0.68 min and the longest groups several minutes.

**Verification:** `study_area_verify.sql` PASS ("241 WSG(s), all modelled, recomputed, segmented and provenanced");
`verify_extra.sql` PASS, one config_hash `sha256:7e9dffa4…`, loader versions and snapshot row counts agreeing across
the four hosts, every group's newest row from this run (`run_verify*.log`). FWA rows remain probes, as A-4 states.

**Size:** the database grew 221 → 275 GB (+54 GB); `fresh_default` 11 → 48 GB, 11,388,157 segments. The volume holds
312 G of 590 G. Cloud hosts were up about 6 h each: about $4.50 at $0.25 per host-hour (`research/study_area_run.md`).

**Compare:** 677 mapping-code rows across 217 of 241 groups; the 24 without a row are the `default`-only groups,
which share no species with the bcfishpass reference (each logs `no shared mapping_code_<sp> columns`).

## Parity (2026-10-17)

run_uid `20261017_093603-31ab6242`, `bcfishpass` into `fresh_parity246`, dispatcher only: the closure of ADMS, BULK,
BABL and ELKR is 17 groups, all modelled, recomputed 17/17, compared 17/17 with no silent errors (#167).
`parity_crosssection.R ADMS BULK BABL ELKR` against `fresh.streams_vw_bcfp`:

- accessible 17/17 within 1 % (max 0.07 %); spawning 16/17 and rearing 15/16 within 5 %. Over: BULK SK +11.0 %
  spawning, +7.4 % rearing, both parked (fresh#190). **PASS**, 48/50.
- Annotated at the taxonomy's 2 % (`parity_annotated.csv`): 44 WITHIN_TOLERANCE, 1 class C (BULK SK spawning,
  `sk-lake-clustering-divergence`), 5 UNEXPLAINED: BULK SK rearing +7.39, BABL ST rearing −2.05, BABL CH rearing
  −2.44, ELKR WCT spawning +3.33, ELKR WCT rearing +2.50. Not diagnosed here; segmentation (#324) is the first
  suspect for the 2–3 % rows, unmeasured.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Completeness check counted 18 finished groups as missing | Paused the driver, consolidated them by hand, resumed (#347) |
| KITR `barriers_pkey` duplicate | One row per PSCIS id in the xref insert (`a17e9177`) |
| UPET `access_rb` boolean into integer | Present species with no barrier is accessible (`a17e9177`) |
| `kill -STOP` refused by auto mode | Operator ran it |
