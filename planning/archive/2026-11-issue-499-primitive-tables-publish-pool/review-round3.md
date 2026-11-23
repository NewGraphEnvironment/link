# Code-check round 3: branch `499-backlog-move-14-primitive-tables-in-one` (HEAD b5ec40d4) against origin/main (be06e2b4)

## Checklist read

- **code-check.md**: read the prose of every H3 under `## Mechanisms`, with table rows skipped. Read in full: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", and "A guard's scope, escape hatches, and remedies", including "Compression runs both ways" and the six ways a restatement names its population. The other nine Mechanisms H3s were read only by their heading and opening lines. 31 standalone headings were not read.
- **code-check-shell.md** (read by heading): read in full "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0", "A `local` statement cannot read a variable it is assigning in the same statement" and "`a && b || c` runs `c` when any step before the `||` fails". 70 headings were not read.
- **code-check-r.md** (read by heading): read in full "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising, so a `tryCatch(error =)` around it never fires" and "`clusterApply()` returns `NULL` for no tasks, not an empty list". 128 headings were not read.
- **code-check-spatial.md**: none read. No heading names the ogr2ogr-into-PostgreSQL staging shape, and the GDAL headings are about rasters and reads. 96 headings were not read.

## What I ran

All of this ran in a detached worktree at b5ec40d4, which has since been removed. `zz_lnk_test_cabd494_*` schemas left behind: 0.

- `test-snapshot_bcfp_lib.R` (NOT_CRAN=true): 18 tests, 0 failures.
- `test-lnk_publish.R`: 13 tests, 0 failures.
- **Mutation of `cabd_load()` to today's direct ogr2ogr call:** the cabd tests 13, 14, 16 and 18 fail (four), and 15 and 17 pass.
- **`CASCADE` added to the drop:** tests 13 and 18 fail (two).

So the cabd README's sentence "four of these fail; with `CASCADE` on the drop, two" holds as measured.

## The mechanism behind round 1

Each round-1 finding is one observed instance written down as if it were the whole set the code admits:

- The put reply's last line was taken to be the reply, because on the clean run it was. stderr is merged in.
- "one `list-object-versions`" was written from a reading of one directory. The code runs one per per-group directory.
- A pool width of 3 assumed a machine with no core limit. R CMD check allows 2.
- Provenance in a private repository was written into a public file, as if it were provenance this public file could carry.

In code-check.md terms this is compression, where a condition drops out ("A guard's scope, escape hatches, and remedies", "Compression runs both ways"), and a proxy standing in for the population.

I checked every place in the branch where an `aws` output is parsed:

| parser | how it reads the output | verdict |
|---|---|---|
| put reply | tab line only | holds |
| `.lnk_publish_list` | tab lines only. A per-page `None` is dropped. A per-page query under `--output text` concatenates correctly for both projections. | holds |
| `etag(live)` | uses only presence or absence | holds |
| `get-bucket-versioning` | a stray trailing line refuses | fails toward abort |
| stale keys | `startsWith` is asserted | holds |
| `version()` | refuses `None`, `null` and an empty value. A pre-versioning `null` refuses, as before. | holds |

I also checked the cabd_load assumptions:

| assumption | verdict |
|---|---|
| The staging table holds `ogc_fid` and `geom` | Otherwise the CTAS fails inside the transaction under `ON_ERROR_STOP=1` |
| A field list with no attributes | `format()` with a NULL `%s` gives a syntax error, so it fails loud |
| bash 3.2 | Every step carries `|| return 1`, because errexit is off under the caller's `|| exit 1`. There is no `local` dependency, and no heredoc sits inside `$( )`. |

The mechanism reaches the prose once more, below.

## Every quantified or numeric claim, against code and evidence

### NEWS 0.87.0

| claim | verdict |
|---|---|
| geom last on the first load and second on every later load, with or without `OGR_TRUNCATE`, GDAL 3.13.0 | holds: `today1`/`today2`/`ow1`/`ow2` and the README table |
| "three starting states give `6f7f44c0…`, the published run's" | holds: `p_none`, `p_last` and `p_second` all read `6f7f44c0`, and the README ties it to the published dispatcher's md5 |
| "recorded md5s stay valid while CABD returns the same dams" | holds, with its condition |
| "The checks read one listing of the prefix instead of a `head-object` per key" | holds: one `head-object` remains, for the live manifest |
| "every put runs on a PSOCK pool … (default 8) and answers with its VersionId" | holds in context: the same sentence sets the manifest apart ("before the manifest goes up"), and the manifest's put runs in-process and its VersionId is not read |
| "one `list-object-versions` per per-group directory" | holds: `habitat_publish.R` loops over `dirs` of the unchanged parts |
| a failed put, a 412 or a missing VersionId stops PUBLISH before the manifest | holds in code and in the tests |
| "36.5 min serially and 4.1 min on the pool" | holds: 01:48:24 to 02:24:52 is 36.47 min, and 02:25:02 to 02:29:08 is 4.1 min |

### RUNBOOK

| claim | verdict |
|---|---|
| §6d: about 2.4 s on the cloud host that measured 53.5 min, and about 0.55 s on m1 | holds: #488's body gives 2.4 s and 53.5 min on hourly-billed hosts, and the README gives 0.55 to 0.63 s |
| §6d: `LNK_PUBLISH_JOBS` from 1 to 64, default 8 | holds: `.lnk_publish_jobs()` |
| §6d: an unchanged per-group part's version comes from one `list-object-versions` of its prefix | holds, read per directory |
| §6d: delete markers are listed apart | holds |
| §6d: a test holds the manifest's put after every other put | holds: `expect_gt(man$start, max(rest$end))` |
| §8d: `cb194733…` against `6f7f44c0…` | holds |
| §8d: "two loads of a view, one into a new database, gave one md5" | holds: `pscis.txt` has three loads, two into one database and one into a new one, all at `f94d327c`. Only `pscis_remediation_svw` was measured, as the README says. |
| §8d: a host loaded before 0.87.0 keeps its layout until `--force` | holds |

### CLAUDE.md, the 2026-11-23 block

| claim | verdict |
|---|---|
| "every host's content md5 agrees and matches … `6f7f44c0…`" | **drops a condition**: see the finding below |
| default 8; one `list-object-versions` per per-group directory | holds |
| about 0.55 s per call, 0.33 s of it start-up | holds: the README gives 0.32 to 0.34 s |
| 36.5, 4.1 and 1.9 min | holds: the logs' wall times and the 1.9 min internal total |
| the pre-run gate is not voided: `DESCRIPTION` and `R/lnk_publish.R` map `none`, and the scripts sit outside `PRETEST_LINK_PATHS` | holds: `pretest_inputs.csv` lines 93 and 172, and `pretest.R:109` |
| the first stub raced and failed one run in two | not checkable from the committed files. The stub does lock `versions.json` and `log.jsonl`. |

### publish_parallel_488/README.md

All of these hold.

- **The scratch versions:** 2,800 versions were removed afterwards. Two full publishes of 1,345 keys and a republish of 110 make 2,800.
- **The tree:** 108 parts, 482 per-group parts and 753 files. `serial.log` holds 110 puts (108 parts, the dependency map and the manifest).
- **Serial run, by step:**

| step | README | log span |
|---|---|---|
| files | 16.0 min | 01:48:25 to 02:04:26 |
| parts | 3.4 min | to 02:07:51 |
| per-group parts | 11.2 min | to 02:19:00 |
| versions | 5.8 min | to 02:24:47 |
| remainder | 5 s | |

- **Parallel run, by step:** the checks take 3.4 s, the puts 231.3 s, the versions 0.3 s, and the rest 1.2 + 2.3 + 4.1 = 7.6 s, written as 8 s.
- **The headline ratio:** 36.47 / 4.1 is 8.9×.
- **The republish:** 0 new files, 108 parts, the dependency map, and 482 of 482 per-group parts unchanged.
- **The versions read from each directory:** 482 is 2 × 241, which is consistent with both `barriers/` and `barrier_overrides/` holding parts.
- **Keys under each prefix:** 1,344 apart from the manifest, which the 1,345 listed confirms.
- **Start-up share:** about 60 %, from 0.33 / 0.55.

### cabd_shape_494/README.md

All of these hold.

- 2,593 dams in every load.
- `geom` at column 113 of 113, against column 2.
- `ogc_fid` runs 1 to 2,593 in every file.
- The typesigs are `d709b8a7` against `a7bd75bc`.
- The three rebuild states match the reload reference.
- The PSCIS load gives 177 rows.
- The mutation sentence is verified above.

### Code comments

| comment | verdict |
|---|---|
| `cabd_load`: 2,593 dams, GDAL 3.13.0 | holds |
| `cabd_load`: geom-last on the first load | holds |
| `cabd_load`: "Nothing in link creates" a view over `cabd.dams` | holds: grep finds none in `R/` or `data-raw/` |
| `cabd_load`: "a failure leaves the table as it was" | holds: one transaction under the caller's `ON_ERROR_STOP` |
| `habitat_publish.R` header: 53 min | holds |
| `habitat_publish.R` header: one `list-object-versions` "of its prefix" | holds, read per directory |
| `habitat_publish.R` header: each step prints its seconds | holds |
| `.lnk_publish_run`'s roxygen: "about 2.4 s whatever it moves" | unqualified, but it is #488's own figure, and the RUNBOOK and CLAUDE.md qualify it. Not a finding. |

## Findings

- **[severity: fragile]** CLAUDE.md:20. The status lead says the rebuild makes "every host's content md5 agree[] and match[] the reload layout's recorded `6f7f44c0…`" with no condition.
  - **What the evidence supports.** `6f7f44c0…` comes from one saved CABD response (2,593 dams, 2026-11-22). The rebuild fixes the column layout, not the data. NEWS ("so recorded md5s stay valid while CABD returns the same dams") and RUNBOOK §8d ("while CABD returns the same dams") both carry the condition. The CLAUDE.md line drops it in compression.
  - **Why it matters.** CLAUDE.md is the line the next session reads first. Once CABD adds or edits a dam, every correctly loaded host records a different md5, and a reader holding this sentence would take that as the #494 defect returning, or as a broken host.
  - **The fix.** Add ", while CABD returns the same dams" after `6f7f44c0…`, as NEWS and RUNBOOK do.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

Nothing else found. The code guarantees hold as round 2 recorded them, re-checked here:

- the tree is verified first;
- every refusal comes before the first write;
- `--content-md5` is on every put;
- provenance and config are write-once;
- the manifest goes up only after every put has returned and been versioned;
- deletes are limited to the three prefixes and come after the manifest;
- the read-back is unchanged.
