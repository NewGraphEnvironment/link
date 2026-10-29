# Code-check round 1: branch `394-recompute-test-existence-instead-of-buil` at `52d7d1a2`

## Checklist read

All four FULL TEXT files are over 40,000 bytes, so I read parts of each. INDEX.md I read in full.

- **code-check.md:** the prose of every H3 under `## Mechanisms`, all 14, with the `|` rows skipped. I did not read the 33 H3s under "Rules that stand alone", Security, or Spreadsheets and PDFs, because none of them names a tool or shape this diff uses.
- **code-check-r.md:** I read the full sections for these 7 H3s:
  - "Postgres row order is never fixed…"
  - "A `function(...)` mock hides arguments…"
  - "A value compared as `::text`…"
  - "`on.exit()` at a script's top level never fires"
  - "A `data-raw/` script must load the source tree…"
  - "`load_all()` refuses an installed dependency below the `Imports:` floor…"
  - "`identical(-0, 0)`…"

  For the other headings I read only the index lines (about 120 not read in full).
- **code-check-shell.md:** index lines only. The diff has no shell code.
- **code-check-spatial.md:** index lines only. The diff runs no spatial tools. The FWA headings ("FWA main flow…", "FWA `upstream_route_measure`…") did not apply.

## What I ran

- I ran `test-lnk_pipeline_access.R` and `test-lnk_preflight_fresh.R` against the scratch fresh 0.47.0 library: 0 failed, 0 errors, 0 skipped. The live `.lnk_walk_keys` test ran against local fwapg.
- `devtools::document()` in the review worktree left `man/` and `NAMESPACE` unchanged, so the Rd is in sync.
- I mutated the code once to probe a test (finding 1). I restored the file afterwards, and `git status` is clean.
- I checked the committed numbers against `steps.tsv`, `ceiling.tsv` and `walks.tsv` in `/Users/airvine/Projects/repo/link/data-raw/logs/recompute_access_394/` (untracked). These all match:
  - access seconds at every step for all four groups;
  - the prefilter's gains (25×, 13×, 7×, 2.2×);
  - SETN's 1.2× and 2.1×;
  - the 57 % repeat share (pooled 57.1 %);
  - 7 of 11 walks;
  - the digest query at 0.7 / 2.2 / 9.2 / 0.16 s;
  - SETN's species walks 327 → 270 s and LFRA's 83 → 68 s;
  - CH-shaped walks 50 → 40 s;
  - `pscis` 0.2 → 3.3 s and `dams` 1.2 → 4.2 s;
  - SALR's 0.2 s overhead;
  - 153 rows with NULL `localcode_ltree`;
  - 5.6× to 57×.

I found no errors in the dedup key's logic:
- link admits a superset of fresh's prefilter: `subpath` from 0 against fresh's from 1, with the same AOI segments, the same blue lines and the same NULL handling.
- Every column the walk reads is in the key.
- The record text is unambiguous: a `)|(` boundary can only appear inside a quoted field.
- The order is total.

Two tables with equal keys therefore get the same existence walk from the AOI.

## Findings

- **[fragile] tests/testthat/test-lnk_pipeline_access.R, the live test ".lnk_walk_keys sees the rows a walk can read" (with R/lnk_pipeline_access.R:493). Nothing tests the key's blue-line arm.**
  - I replaced `OR f.blue_line_key = ANY (ARRAY(SELECT blue_line_key FROM lines))` with `OR false`, and the whole file still passed (0 failed, no error).
  - Every fixture row on blue line 10 also enters through its wscode. The one row only the blue-line arm admits is in `kg` (NULL wscode). Without that arm its key becomes `md5('')`, which still differs from `kf`'s, so the `expect_false` still holds.
  - This arm is what keeps the dedup exact for features on a group's own line whose wscode is NULL or not an ancestor. Without it, two views that differ only in such rows get equal keys, and the second species takes the first's walk. That is an output change, not a slowdown.
  - A fixture pair differing only in a row with a NULL or unrelated wscode on AOI blue line 10 would pin the arm (expect the keys to differ).

- **[fragile] R/lnk_pipeline_access.R:497-502 (`.lnk_walk_keys`, the `codes` CTE). A group segment with an empty `wscode_ltree` aborts the access step.**
  - `subpath(wscode_ltree, 0, k)` with `generate_series(0, nlevel(wscode_ltree))` calls `subpath(''::ltree, 0, 0)` for an empty code. That raises `ERROR: invalid positions` (checked on local fwapg). `WHERE wscode_ltree IS NOT NULL` does not exclude an empty code.
  - fresh's prefilter uses `generate_series(1, nlevel(...))`, which yields no rows for an empty code, so fresh alone would not fail.
  - This happens only when two or more existence-walk species tables are keyed. `fresh_default.streams` holds 0 such segments today, so it is latent.
  - The roxygen and plan-review item 10 say the length-0 subpath is there to include the empty code. That works only for non-empty segment codes.
  - Fix: guard with `nlevel(wscode_ltree) > 0` and add `''::ltree` to `codes` explicitly, or start at 1 as fresh does and add `''`.

- **[fragile, low] R/lnk_pipeline_access.R:183-199 and 236-256. A table given both as a keyed species view and as a non-array source is walked twice.**
  - When two or more species tables are keyed, the species walk is cached under `rows:<md5>`. The source loop still looks up `dnstr_cache[[src_tbl]]` by table name, misses, and walks again.
  - The result is identical, so only cost is affected. But the roxygen ("A table given in several roles is walked once"), the 1b comment ("only run the SQL once") and RUNBOOK §3 ("Each table is walked once") all state the opposite.
  - No current caller passes such a pair: `pscis` is `barriers_pscis[_unified]`, never a species view.

- **[docs, check against TSV] RUNBOOK.md, the new "How the walks run" section ("Existence … no (segment, feature) pairs. That removes SETN's output cost.")**
  - fresh's `"exists"` mode is `SELECT DISTINCT a.<id>` over the same join (fresh047 `R/frs_network_features.R`). The join still enumerates every (segment, feature) pair. It only skips building and returning the arrays.
  - The TSVs agree with the code, not the sentence:
    - SETN's access step goes 347 → 292 s, and its species walks 327 → 270 s.
    - Most of SETN's gain comes from dedup (292 → 136 s), not from removing output.
  - "no pairs returned / no arrays built" is accurate. "removes SETN's output cost" is not.
  - `research/recompute_cost.md`'s "without the (segment, feature) pairs" reads the same way.

- **[docs, stale] research/recompute_cost.md:83-85 ("The walk's `ORDER BY` has no unique tiebreak, so co-located features come back in plan order").**
  - The file is now stamped Verified 2026-10-29 and describes the walks at the fresh 0.47.0 pin. But fresh 0.47.0's array walk ends its `ORDER BY` on `b.<feature_id_col>` (fresh#272), so this sentence describes 0.44.0.
  - It matters for `dam_dnstr_ind` (`anth[1]`): plan-review item 16 notes 0 co-located ties in `fresh_default.barriers`, and the digests cover it. The prose is still wrong for the pinned version.

- **[evidence ordering] CLAUDE.md (new status) and research/recompute_cost.md ("Scratch models of ADMS and ELKR, built at each step, digest identical in every persisted table").**
  - "Each step" includes dedup (`d047`). At review time `model_digest.tsv` has only `m044`, `m047` and `b047` rows (20 each). `model_digest.R … d047 ADMS ELKR` is still running, and the untracked README still carries the `@@D047@@` and `@@END@@` placeholders.
  - The committed claim is ahead of its evidence.
  - The evidence directory these docs cite (README, TSVs) is untracked on the branch; only the scripts and the round-0 TSVs are committed.
  - Hold the claim until d047 lands, and commit the directory with it.

/Users/airvine/Projects/repo/link_wt394_review/review-round1.md
