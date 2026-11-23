# Code-check round 1: branch `499-backlog-move-14-primitive-tables-in-one` against origin/main

## Checklist read

- **code-check-r.md** (read by heading): read "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising…", "`clusterApply()` returns `NULL` for no tasks, not an empty list", "Postgres row order is never fixed unless the query fixes it…", "`on.exit()` at a script's top level never fires". Scanned every index line; 126 of 130 not read in full.
- **code-check-shell.md** (read by heading): read "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0" and "An S3 multipart ETag depends on the uploader's part size…". Checked the index lines on heredocs, bash 3.2, `local`, traps and `a && b || c` against the diff without opening them. 71 of 73 not read in full.
- **code-check-spatial.md** (read by heading): none read in full. No heading names the ogr2ogr-to-PostgreSQL shape this diff uses. 96 of 96 not read.
- **code-check.md**: read the prose of `## Mechanisms`. I read in full "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness" and "A wrapper's exit is not the work". I only skimmed the headings and first lines of "Restore the bug…", "A shared working tree…", "Zero-length…", "The probe is broken…", "Written data outlives the fix", "Serialization loses meaning silently" and "One fact derived twice". 31 standalone headings not read.

What I ran: a detached worktree at HEAD, with `NOT_CRAN=true`. `test-lnk_publish.R` gave 13 tests and 0 failures. `test-snapshot_bcfp_lib.R` gave 75 expectations and 0 failures; its live cabd tests ran against local fwapg and dropped their own schema. I also checked that an empty listing goes through the stale-key `setdiff`/`startsWith` path without error. The worktree has been removed.

## Findings

- **[severity: security]** CLAUDE.md:24 — The new status block writes a private repository's issue reference into a PUBLIC repo's tracked CLAUDE.md. The same line names two of our cloud images by id. The project's own rules forbid an `owner/private-repo#N` reference in public text "not even as provenance", and they keep anything learned about our machines out of the repo and in memory. The PR-merge private-reference gate may also refuse the branch over this line. Fix: write the owed item without the repo name, issue number or image ids (for example, "the scheduled cloud runs move to a rebuilt image, tracked privately"), and keep the ids in private notes.
  - **Rule:** none

- **[severity: fragile]** R/lnk_publish.R:195-203 (`.lnk_publish_put_version`) — The VersionId is taken from the last non-empty line of `r$out`. That output has stderr merged into it (`.lnk_publish_aws` passes `stderr = TRUE`). A valid reply to `--query "[VersionId,ETag]" --output text` is always one line holding a tab. Any stray stderr line that lands last, such as a CLI warning, has no tab and is taken whole as the VersionId. It passes the `None`/`null`/empty test and is written into the manifest as the version that pins the part, so the check fails toward pass. On m1 the evidence shows every version id was correct, so this has not happened yet. Fix: accept only a line containing a tab whose first field is non-empty, and refuse anything else.
  - **Rule:** code-check.md "A wrapper's exit is not the work" ; code-check.md "A guard that fails toward pass"

- **[severity: fragile]** NEWS.md:6, CLAUDE.md:20, data-raw/logs/publish_parallel_488/README.md:43 — These say an unchanged per-group part's version comes from "one `list-object-versions`". The README says it was one listing "of `barriers/` and `barrier_overrides/`". The code (data-raw/habitat_publish.R:255) runs one `list-object-versions` per top-level directory that holds an unchanged part. With unchanged parts under both `barriers/` and `barrier_overrides/`, which the README's republish had, that is two listings. RUNBOOK §6d and the driver's header comment say "of its prefix", which is accurate. The published NEWS line and the evidence README overstate it. Fix: say "one per per-group directory".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

Nothing else found. These guarantees hold in the code:
- the tree is verified first, and every refusal comes before the first write;
- `--content-md5` is on every put, the manifest's included;
- write-once keys carry `--if-none-match "*"`;
- the manifest goes up only after `clusterApplyLB` has returned every put and every result has been checked and versioned;
- stale deletes come after the manifest, only under the three prefixes, with `startsWith` asserted;
- the read-back is unchanged.

`cabd_load` runs its drop and rebuild in one transaction under the caller's `ON_ERROR_STOP=1`, drops without CASCADE, and checks the result's first two columns afterwards.
