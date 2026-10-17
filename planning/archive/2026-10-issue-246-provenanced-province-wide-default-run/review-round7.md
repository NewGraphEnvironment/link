# Code-check round 7 (#246): enumeration

Diff: `cc7.diff` (CLAUDE.md, R/lnk_pipeline_access.R, R/lnk_pipeline_pscis_build.R, research/study_area_run.md, two
test files). Reviewer worked read-only against `fwapg` / `fresh_default` (temp tables only) and read the backup dump
with `pg_restore -a -t ... -f -` (no restore).

**Verdict: one wrong claim in the diff (B-31), plus two pre-existing latent defects outside the diff (A-11, A-16)
and one dangling path that becomes true only at `/planning-archive` (B-40).** The code change itself (A-4, A-9) is
consistent with the rule and with the data: no group/species in `fresh_default` has a present species with an NA
flag, and no accessible segment has an empty mapping code.

Counts: **A = 26 places, B = 61 claims** (52 numbered rows plus 9 lettered sub-rows).

## Findings

1. **[bug, prose] CLAUDE.md Status 2026-10-17, last bullet: "The pre-run `fresh_default` is kept as a machine-local
   `pg_dump` (the run's pre-consolidate backup)".** The dump is not the pre-run schema. It was taken at 22:42:46 PDT
   (`20261017_004619_consolidate.log:311`), after m1 had already modelled its 76 groups straight into
   `fresh_default`. Read from `~/fwapg_backups/fresh_default_pre_consolidate_202610162242.dump`: `streams` holds 109
   groups; `log` gives 76 of them `run_uid 20261017_004619-3f4c713b` (e.g. CHWK at `ee21eb13`, 14,346 segments,
   identical to today's), and only 5 older log rows (DUNC 0.63.1, KOTL / LARL / SLOC 0.45.1, PINE 0.44.3). So 109 =
   76 + 33 pre-run groups: 23 of the 56 pre-run groups (those in m1's bucket, CHWK among them) are not in the dump
   at their pre-run state. What the sentence is used for still holds: KOTL, LARL, SLOC and DUNC (all job3) are in it
   at their old builds. Fix: "The run's pre-consolidate dump (machine-local) still holds the pre-run KOTL, LARL, SLOC
   and DUNC builds, so they can be restored; it is not the whole pre-run schema, because m1's 76 groups were already
   rebuilt when it was taken." (findings.md "it was moved out of `/tmp`" is also a copy: both
   `/private/tmp/fresh_default_pre_consolidate_202610162242.dump` and the backup copy exist; /tmp is cleared on
   reboot, so the backup copy is the one to cite.)

2. **[latent, pre-existing, outside the diff] `R/lnk_access.R:224-228`, merge mode writes `access_<sp> = 1` for an
   absent species.** `CASE WHEN sc.a = 0 THEN 0 WHEN t.a = 2 THEN 2 ELSE 1 END` maps the scratch's `-9` to `1`
   (evaluated in Postgres: `(-9, NULL) -> 1`, `(-9, -9) -> 1`). It is reached whenever `species` holds a species the
   AOI lacks, and `species = NULL` defaults to `cfg$species`, which is what the function's own `@examples` does
   (`lnk_access(..., merge = TRUE, presence = pres)` on PARS with the bcfishpass bundle). Every rollup counts
   `access IN (1, 2)` as accessible. Not reached by shipped callers: `wsg_recompute_one.R:153` and
   `habitat_variants_build.R:582` both pass `species = active` (`lnk_pipeline_species`, literal presence, a subset of
   `lnk_presence`'s group-expanded set). Not this diff's defect; worth an issue (add `WHEN sc.a = -9 THEN -9`, or
   intersect `species` with presence).

3. **[latent, pre-existing, outside the diff] `R/lnk_mapping_code.R:186-194`, `presence = NULL` crashes.** It
   derives presence as a named logical vector and passes it on; `lnk_pipeline_mapping_code()` then calls
   `presence$is_present(sp)`, which errors (`$ operator is invalid for atomic vectors`, reproduced). Every shipped
   caller passes an `lnk_presence` object. Not this diff's.

4. **[note, not a failure] The no-presence path of `lnk_pipeline_access()` leaves flag and access disagreeing.**
   With `wsg_presence = list()` and no `presence`, the doc says "assumes all species present"; access becomes 1 / 2
   (line 374) but zero barrier rows leave the flag NA, so the mapping code emits "" on accessible segments. CLAUDE.md
   states the rule as "NA only when nothing says the species is present", and the test pins this behaviour, so it is
   a deliberate choice; no caller reaches it (A-23, A-24, A-26 all pass presence). Recorded so the next reader does
   not take the default as "present" for the flag.

## A. "Zero rows / NA means absent": every place

Rule under test: present + no barrier = flag FALSE, access 1/2; absent = flag NA, access -9 (in persist, absent
species are never in `barriers_per_sp`, so their columns are NULL / NULL: measured, 0 groups carry -9 anywhere).

| # | place | reads/writes | consistent? | wrong value given the new FALSE? |
|---|---|---|---|---|
| 1 | `lnk_pipeline_access.R:126-133` presence -> `wsg_presence` | derives per-species TRUE/FALSE | yes | no |
| 2 | `:149` absent species skip `frs_network_features` | absent -> no frame | yes | no |
| 3 | `:242-243` no frame -> flag NA | absent -> NA | yes | no |
| 4 | `:244-250` zero rows -> FALSE if present, else NA (the fix) | per-sp flag | yes | no; DB: 0 of 2,651 group×species rows have a present species with any NA flag |
| 5 | `:251-253` rows > 0 -> `%in%` | per-sp flag | yes | no |
| 6 | `:256-263` per-source zero rows -> NA | anth / pscis / dams / remediations | yes (see below) | no |
| 7 | `:274-293` `dam_dnstr_ind` | reads source frames; empty -> FALSE | yes | no; 0 groups with any NULL |
| 8 | `:306-334` `remediated_dnstr_ind` | empty -> FALSE | yes | no; 0 groups with any NULL |
| 9 | `:353-377` access: -9 if absent, NA blocked -> FALSE | per-sp access | yes; with presence the NA path is now unreachable | no |
| 10 | `lnk_access.R:217-222` merge SET of flags from scratch | copies FALSE / NA as built | yes | no |
| 11 | `lnk_access.R:224-228` merge access CASE | -9 -> 1 | **no** (finding 2, pre-existing, unreached) | unrelated to FALSE |
| 12 | `lnk_access.R:190-196` overwrite mode | passes presence | yes | no |
| 13 | `lnk_pipeline_mapping_code.R:166-210` per-source `has()` = `na_to_false` | NA -> FALSE -> NONE/MODELLED | yes | no |
| 14 | `:224-227` presence short-circuit -> "" | absent | yes | no |
| 15 | `:229-236, 282` per-sp `no_data` = NA -> "" | per-sp flag | yes; FALSE now builds tokens | no; DB: 0 accessible species-segments (of 9,514,064) with an empty code |
| 16 | `lnk_mapping_code.R:186-194` derived presence | NULL presence | **crashes** (finding 3, pre-existing, unreached) | n/a |
| 17 | `lnk_pipeline_persist.R:159-180` INSERT projection | copies flags + access | yes | no |
| 18 | `lnk_persist_init.R:80-105` DDL | boolean flags, integer access | yes | no |
| 19 | `lnk_rollup_wsg.R:120,170` `access IN (1, 2)` | access | yes; NULL not accessible | no |
| 20 | `lnk_scenario_export.R:134,189` `has_barriers_dnstr` passthrough | per-sp flag | yes; UPET RB now ships FALSE, not NA, which is the truth | no |
| 21 | `lnk_habitat_validate.R:844,1210` `coalesce(access IN (1,2), false)` | access | yes | no |
| 22 | `lnk_compare_rollup.R:232` `access IN (1, 2)` | access | yes | no |
| 23 | `lnk_pipeline_run.R:226,270` presence object, `barriers_per_sp` = active only | caller | yes | no |
| 24 | `data-raw/wsg_recompute_one.R:149-177` `species = active`, `presence = pres` | caller | yes; active (literal) is a subset of `pres` (group-expanded), so no -9 reaches row 11 | no |
| 25 | `data-raw/wsg_run_one.R` | no reads; calls `lnk_pipeline_run` | n/a | no |
| 26 | `data-raw/habitat_variants_build.R:576-582` | `species = active`, presence | yes | no |

**Per-source flags keep "zero rows -> NA" unconditionally, and that is right, not the same defect.** Their only
reader is the mapping code (row 13; `grep` finds no other R reader), which reads them through `na_to_false`, so NA
and FALSE give the same token (no anthropogenic barrier downstream -> `NONE`), matching bcfishpass's
`barriers_anthropogenic_dnstr IS NULL`. The per-species flag differs because row 15 reads NA as "no data" and emits
"". Groups where a source has zero rows today: anthropogenic 9, pscis 111, dams 85, remediations 9 of 241; none of
them produces a wrong code (row 15's check covers every accessible segment).

**"UPET RB is the only such case" (CLAUDE.md) re-derived two ways.** (a) At `ee21eb13` any present species with
zero barrier rows failed persist (logical `access_<sp>`); only KITR (pkey) and UPET (access_rb) failed. (b) Only
UPET was recomputed after `91a968ab`, yet no group in the DB has a present species with an NA flag or an accessible
segment with an empty code, so KITR (re-run at `a17e9177`) has no such species either.

## B. Every number and quantified claim in the changed prose

Sources: DB = `fresh_default` / `fresh` / `fresh_parity246` now; F = `planning/active/findings.md`.

### CLAUDE.md, Status 2026-10-17

| # | claim | source | verdict |
|---|---|---|---|
| 1 | run_uid `20261017_004619-3f4c713b` | DB log, `run.log` | ✓ |
| 2 | "every `default`-modelable group (241)" | buckets_default.md (246 focal, 5 dropped); DB 241 groups in log and streams | ✓ |
| 3 | "on m1 and three cloud hosts" | DB log hosts: m1, cypher-job1..3 | ✓ |
| 4 | both verifiers pass at `expected_n=241` | `run_verify_2.log`, `run_verify_extra_2.log` PASS 241 | ✓ |
| 5 | one config_hash, one fwapg / bcfishobs / bcfp pin | DB: 1 / 1 / 1 / 1 distinct | ✓ |
| 6 | every group's newest log row from this run | DB: DISTINCT ON newest = run_uid for 241/241 | ✓ |
| 7 | `fresh` is unchanged | DB `fresh.log` / `log_recompute` newest 2026-09-26 | ✓ |
| 8 | parity at the same code, 48/50, on ADMS BULK BABL ELKR | `fresh_parity246.log` all `a17e9177` (= the shipped recompute code); `parity_crosssection.log` OVERALL 48/50 | ✓ |
| 9 | 17-group closure into `fresh_parity246`, four scored | DB 17 groups log + log_recompute; compare 17/17 | ✓ |
| 10 | one run_uid, more than one link SHA | DB: 2 in log, 3 in log_recompute | ✓ |
| 11 | log: 239 `ee21eb13`, KITR and UPET `a17e9177` | DB | ✓ |
| 12 | "re-run on m1 under the same run_uid" | DB host m1, run_uid | ✓ |
| 13 | log_recompute: all 241 stamp `a17e9177` | DB 241 rows / 241 groups | ✓ |
| 14 | UPET recomputed again at `eb93f343` | DB row 10:59:09 UTC, clean | ✓ (the parenthetical "round 6's mapping-code fix" refers to the bullet below / `91a968ab`; `eb93f343` itself only adds the review file. True as worded, reads ambiguously) |
| 15 | "one stray row between those is link_dirty TRUE (an uncommitted review file)" | DB row at `91a968ab`, dirty, 10:58:12 UTC; `91a968ab` 10:57:58, `eb93f343` (adds review-round6.md) 10:59:01 | ✓ |
| 16 | "the clean re-run follows it" | DB 10:59:09 clean | ✓ |
| 17 | 18 finished groups missed (#347) | run_job*.log: 2 + 12 + 4 `done` markers mid-line | ✓ |
| 18 | "an R warning put the done marker mid-line" | job logs (`...:[wsg_run_one] FIRE done`) | ✓ |
| 19 | driver consolidates only what it counted; burn would destroy the rest | `study_area_run.sh:1287-1322,1373` | ✓ |
| 20 | #348: failed group with no earlier rows skips the recompute for every group | `study_area_run.sh:1392-1407` exits before recompute; KITR and UPET not in the pre-consolidate dump, so they had no earlier rows | ✓ |
| 21 | failed group with earlier rows passes the gate | same gate checks row existence only | ✓ |
| 22 | recompute 154 min at 241 and `-j4` | DB a17 rows 06:56:44–09:30:25 = 153.7 min | ✓ |
| 23 | median 2.0 min, longest 16 min | `_recompute.log`: median 2.00, max 16.24 | ✓ |
| 24 | "not the ~1 h the plan assumed" | F:117 | ✓ |
| 25 | present species with no barrier: access 1 or 2, flag FALSE | code A-4/A-9; DB | ✓ |
| 26 | NA only when nothing says present | code A-4 (see finding 4 for the no-presence default) | ✓ as code behaves |
| 27 | before `91a968ab`, UPET RB `mapping_code_rb` "" on every segment | F round 6 (5,103 / 5,103); a17 code path | ✓ (not re-measurable now; mechanism confirmed) |
| 28 | UPET RB the only such case in the 241 | A section, two derivations | ✓ |
| 29 | `fresh_default` 31 GB (14 tables, 17 indexes), 11.39 M segments | DB now: 14 / 17 / 31 GB; 11,388,157 | ✓ |
| 30 | up from 7.3 GB | F:154 planning measurement, method not recorded | unverifiable now; consistent with 5.9 KB per source segment; not contradicted |
| 30a | all-relkinds sum counts each index twice (48 GB) | DB 48 GB | ✓ |
| 30b | volume 600 GiB, 253 G free after the run | df now 590G fs, 324 used, 241 avail, 25 G reserved; after run 312 used -> 253 avail | ✓ |
| 31 | "The pre-run `fresh_default` is kept as a machine-local pg_dump (the run's pre-consolidate backup)" | dump read | **✗ finding 1**: 23 of 56 pre-run groups are already this run's builds in it |
| 32 | "so those builds can be restored" (KOTL, LARL, SLOC, DUNC) | dump log rows 0.45.1 / 0.63.1; all four on job3 | ✓ |
| 33 | run replaced August KOTL/LARL/SLOC and 2026-10-12 DUNC | dump vs DB | ✓ |

### CLAUDE.md, the two superseded notes

| # | claim | source | verdict |
|---|---|---|---|
| 34 | "all four groups are now this run's builds" | DB newest log rows | ✓ |
| 35 | "`fresh_default` is now one build of 241 groups" | DB; one run_uid (two link SHAs stated above) | ✓ |

### research/study_area_run.md

| # | claim | source | verdict |
|---|---|---|---|
| 36 | header issues #175, #246, #347, #348; logs `provincial_246/`, `20261017_*` | gh titles; ls | ✓ |
| 37 | step 5: only the groups each log reports are consolidated, from log text; missed 18 | `bucket_done()`; job logs | ✓ |
| 38 | step 6: burn does not check consolidation | `study_area_run.sh:1373-1374` | ✓ |
| 39 | step 7: median 2.0 (quartiles 1.1 / 3.2, longest 16), 597 summed, 154 at `-j4`; ~10 s was FINA alone | `_recompute.log` 2.00 / 1.13 / 3.18 / 16.24 / 596.96; DB 153.7; research :87-88 FINA 11.86 s | ✓ |
| 40 | record in `planning/archive/2026-10-issue-246-provenanced-province-wide-default-run/` | ls: not yet present (task_plan `/planning-archive` unchecked) | conditional: true only if the archive step uses that slug; check at archive |
| 41 | `default` into `fresh_default`, m1 + three cloud hosts, `--refresh-primitives`, link `ee21eb13` | run.log:11; DB | ✓ (239 of 241 at `ee21eb13`, stated below) |
| 42 | modelling job1 171, job2 207, job3 277, m1 ~225 | DB spans 170.8 / 207.3 / 277.0 / 224.8 | ✓ |
| 43 | planned ~4.7 h each, ~1 h, ~6 h, ~$3, ~+65 GB / ~21 GB | F:117-118, :155 | ✓ |
| 44 | consolidate 46 min (3 hosts) | `_consolidate.log` 22:42:46 → last stamp 23:27:26 (verify step), recover at 23:28:00 | ✓ within a minute |
| 45 | wall clock 8 h 48 m, incl. ~30 min pause | run.started 00:46:19Z; run.log mtime 09:35:41Z, F exit 09:34; pause ~06:28→~06:55 UTC (recover18 23:28, re-runs to 06:49, recompute 06:56) | ✓ |
| 46 | 3 × ~6 h ≈ $4.50 at $0.25/h | up ~00:56Z, burn after resume ~06:5xZ; research :309 price | ✓ |
| 47 | DB 221 → 275 GB | F:233; now 287 GB = 275 + parity's ~12 G | consistent; 221 not re-measurable |
| 48 | "34-group run had cloud hosts at or above m1's rate, against the 0.45" | F host table: job1 0.113, job2 0.220 vs m1 0.219 min/1k source (job2 within 0.5 %); per persisted 0.048 / 0.082 vs 0.093 | ✓ ("at" covers job2) |
| 49 | slowest cloud host finished 52 min after m1 | DB 05:42:45 − 04:50:26 = 52.3 | ✓ |
| 50 | recompute the long pole after modelling; #274, #250 the levers | stage table; gh titles | ✓ |
| 51 | "what went wrong" bullet: 18 groups, two failures fixed in `a17e9177`, one failed group would skip all, KITR/UPET re-ran on m1, log 239 / 2, log_recompute 241 at `a17e9177`, UPET again at `eb93f343` | as rows 11-20 | ✓ |
| 52 | parity `20261017_093603-31ab6242`, 17 groups built, 48/50, BULK SK over and parked (fresh#190) | DB; parity logs; script allowlist | ✓ (fresh#190 is closed NOT_PLANNED, migrated to link#130; the script and repo still cite it as the parking reference, so accurate to source) |
| 52a | link_dirty bullet: #257 closed; FALSE on all 241 rows on 2026-10-17 | gh; DB log 0 dirty of 241 (log_recompute's one dirty row is covered in CLAUDE.md) | ✓ |

### Comments added in R/ and tests

| # | claim | source | verdict |
|---|---|---|---|
| 52b | pscis: an xref row may set both ids (KITR 203838); both branches then emit it | both xref CSVs: exactly 2 such rows (203324 ATNA, 203838 KITR) | ✓ |
| 52c | bcfp: one INSERT, ON CONFLICT DO NOTHING, no branch precedence | `bcfishpass/model/01_access/pscis/sql/04_pscis.sql:110,119,154` (local `f8db4b9`) | ✓ |
| 52d | the two agree for both rows: KITR's modelled crossing on its lfid; ATNA's absent, so only B emits | DB `fresh.modelled_stream_crossings`: 8501815 on 84042066 KITR; 1000400002 absent | ✓ |
| 52e | a duplicate becomes a duplicate `barriers_pkey` | F (KITR error) | ✓ |
| 52f | access comments: NA flag "emitted "" for every UPET RB segment"; `blocked` all NA only when no presence given | code paths A-4, A-9 | ✓ |
| 52g | test comments (UPET RB history, "bcfp's NULL column", KITR) | as above | ✓ |

(52 numbered claims plus 9 lettered sub-claims, 61 in all; every one has a verdict. One is wrong: #31.)
