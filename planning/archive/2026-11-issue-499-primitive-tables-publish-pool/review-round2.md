# Code-check round 2: branch `499-backlog-move-14-primitive-tables-in-one` (HEAD b5ec40d4) against origin/main

## Checklist read

- **code-check-r.md** (read by heading): read in full "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising, so a `tryCatch(error =)` around it never fires", "`clusterApply()` returns `NULL` for no tasks, not an empty list", "Forked `parallel::mclapply()` workers segfault in `glm.fit` under macOS Accelerate BLAS" and "Under `R CMD check`, tests run from a temp dir against the INSTALLED package". Checked the index lines for testthat, `tempfile()`, `Rscript -e` and jsonlite against the diff without opening them. The rest were not read.
- **code-check-shell.md** (read by heading): read in full "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0", "An S3 multipart ETag depends on the uploader's part size, so try every size that gives its part count" and "macOS `/bin/bash` 3.2 quote-matches a heredoc inside `$( )`, so an apostrophe in the body is a syntax error". Checked the index lines on `local`, traps, `a && b || c` and empty arrays. The rest were not read.
- **code-check-spatial.md** (read by heading): none read in full. No heading names ogr2ogr loading into PostgreSQL.
- **code-check.md**: read the prose under `## Mechanisms` for "A guard that fails toward pass", "A fixture that cannot reach the failure mode" and "A proxy is not the property", and skimmed the other Mechanisms headings. The standalone headings were not read.

## What I ran

All of this ran in a detached worktree at HEAD, which has since been removed.

- `test-lnk_publish.R`: 13 tests, 0 failures, 0 skips. The end-to-end PUBLISH tests on the stub `aws` ran with `_R_CHECK_LIMIT_CORES_=TRUE`.
- `test-snapshot_bcfp_lib.R`: 18 tests, 0 failures, 0 skips. The live `cabd_load` tests ran against local fwapg and dropped their own schemas.
- `test-pretest.R`: 36 tests, 0 failures. This confirms the `none` map row for `R/lnk_publish.R` still holds.
- `cabd_load` on stubs under `/bin/bash` 3.2.57: exit 0, and the transaction script reached psql intact (`$$`, `'cabd.dams_load'::regclass`).
- R CMD check's `R_TESTS=startup.Rs` breaks PSOCK workers whose working directory has no `startup.Rs`: I reproduced the hang. testthat 3.3.2's `local_test_directory()` sets `R_TESTS=""`, so the pool tests are unaffected. Not a finding.

## Round-1 fixes

The three round-1 findings are fixed.

- **(b) The VersionId parse.** `.lnk_publish_put_version()` now reads only a tab-separated line.
- **(b) The other aws output parsers.** Each one either filters or fails toward abort:
  - `.lnk_publish_list()` keeps tab lines only.
  - The stale step asserts `startsWith`.
  - `get-bucket-versioning` refuses on a stray line, which is a refusal and not a pass.
  - `etag(live)` uses only whether the key is present, and the value it reads is never compared.
- **(c) and (a) The prose.** NEWS, CLAUDE.md and the publish README now say one listing per per-group directory. No private repo, issue or image id remains in the branch's diff outside `planning/`.
- **(d) The pool tests.** They run at 2 workers, which `_R_CHECK_LIMIT_CORES_` allows.

## Guarantees checked in the code

- The tree is verified first.
- `LNK_PUBLISH_JOBS`, the gate, versioning, the regressions and the write-once ETag check all run before the first put.
- `--content-md5` is on every put, the manifest's included.
- `--if-none-match "*"` is on the provenance and config puts.
- The manifest goes up only after `clusterApplyLB()` has returned every put and each result has been checked and has a VersionId.
- Deletes come after the manifest, only under segment/, barriers/ and barrier_overrides/.
- The read-back is unchanged.
- `cabd_load` drops its staging table first, rebuilds in one transaction under `ON_ERROR_STOP=1` without CASCADE, and checks the first two columns after the commit.

## Clean
No issues found.
