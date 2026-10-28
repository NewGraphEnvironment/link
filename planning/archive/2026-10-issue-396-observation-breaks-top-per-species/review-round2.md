# Code-check round 2 (#396)

Read-only review. I ran no R, psql, tests or scripts and opened no database connection.

## Checklist read

- **code-check-r.md** (111 headings): I read 26 in full and left 85. The 26: on.exit at top level; data-raw must load the source tree; Tests that silently do not run; testthat counts an uncaught error; skip_if_not scope; `$` partial-matches; A database driver's value is not a base R type; `::text` spelling; Inserting a helper between roxygen and function; nzchar(NA); paste() zero-length; Under R CMD check tests run against the installed package; match() and NA; expect_false(identical); `[[` on an atomic vector; yaml mixed sequence; Postgres row order; sprintf %g into SQL; information_schema lookup; Rscript reads as it runs; pkg:: in a test; dplyr column masking; read.delim quoting; function(...) mock; tryCatch nesting; ifelse all-NA.
- **code-check-shell.md** (67 headings): I read 28 and left 39. The 28: Empty arrays under set -u; Quoting; Heredoc precedence; Paths; Diagnose env/PATH; Parallel writers; BSD vs GNU sed/grep; GNU stat/date on this Mac; `&` binds to the whole list; destructive setup and undo; numeric grammar; bare `wait`; `if ! cmd; rc=$?`; pgrep -f waiter; shadowed verification commands; psql `:'var'` and `\quit`; second trap EXIT; `local` multi-assign; `grep -c`; sed replacement variables; exit in a loop condition; failed `cd`; bash 3.2 heredoc in `$( )`; awk `==` on versions; EXIT vs RETURN trap; `for x in $(cmd | grep || true)`; sed/awk range to EOF; Python CLI buffering.
- **code-check-spatial.md** (93 headings): I read 4 and left 89. The 4: FWA upstream_route_measure misses the next start; FWA main flow is not 1000 alone; FWA main stem's downstream end; pdist precision.
- **code-check.md** (37 headings): I read the prose of all 14 H3s under `## Mechanisms`, without their tables, plus 4 standalone rules: Do not edit files a long test run is reading; Bare y/n YAML booleans; Documentation Staleness; An assertion that matches an interpolated value. I left 19.

Round-1 fixes reviewed first:
- **Fix 2 (province.sql per group) is correct.**
- **Fix 3 (cuts.sql) is correct:** `frs_break_apply()` tests every break in one call against the original segment ends (`fresh/R/frs_break.R` ~613-626), so two observation positions 1 m apart both cut.
- **Fix 1 (slivers) is incomplete.** See finding 2.

## Findings

- **[bug: load-bearing claim] RUNBOOK.md:199-201, R/lnk_pipeline_break.R:26 and :153-155, inst/extdata/configs/default/config.yaml:120-122.** These lines say the top observation is "the one place on a line where code 2 changes", so "the tops are the only breaks code 2 needs". The access walk shows that a top break changes no access code at all.
  - **How the walk reads it.** It is `frs_network_features(direction = "upstream", include_equivalents = TRUE)`, which calls `fwa_upstream(seg.blk, seg.drm, …, obs.blk, obs.drm, …, true, 1)` (fresh `R/frs_network_features.R` ~221; fwapg `db/schema.sql` ~3287). A segment reads code 2 when an observation lies at or above its downstream end, or within 1 m of it.
  - **The top break leaves the codes as they were.** With a break at the top T, the segment `[q, T]` below reads 2, because T_raw lies above q. The segment `[T, next]` also reads 2, because T_raw is within 1 m of its start. Without the break, the single segment `[q, next]` reads 2. So every metre reads the same in both cases.
  - **Where code 2 actually stops** on the persisted network is the first cut more than 1 m above T, wherever that falls. This is exactly what code2_class.sql and the "access changes" paragraph measure.
  - **Consequence.** `top_per_species` gives the same `access_<sp>` everywhere as dropping `observations` from `break_order`. The kept tops (45.6 % of positions province-wide) only add segments.
  - **The design rationale does not hold.** The knob's value, and the stated reason for preferring it over "no observation breaks", rest on a false mechanism. The same applies to redundancy.sql's question 5 premise: that only a "redundant" top changes no access code.
  - **Not a data bug.** The outputs are as intended, but the shipped docs justify the choice wrongly and the decision between "tops" and "none" was never put. I recommend correcting the three statements and putting the tops-against-none choice to the operator before release.

- **[fragile: measurement expectation] RUNBOOK.md:213-220 and data-raw/logs/observation_breaks_396/pre_post_diff.R:11-18 (and lines 100-101 and 111, which exclude only `sliver` pieces).** Round 1's fix says an access, `has_barriers` or mapping-code move from a removed observation is always a 1 m boundary sliver. That misses a case that changes a whole segment.
  - **The case.** A natural barrier with a raw measure b_raw in (p+1, p+1.5) above a removed observation cut p, so its break is round(b_raw) = p+1.
  - **BEFORE.** The observation cuts at p first. The barrier's break at p+1 is not more than 1 m from p, so it does not cut. The segment `[p, r]` holds the barrier, which is more than 1 m above its start, so `fwa_downstream(include_equivalents, 1)` does not read it as downstream (fwapg `schema.sql` ~2161-2210: `b < a OR abs(a - b) <= 1`). The whole segment reads open. This is #349's metre-rounded "accessible segment holding a barrier" family.
  - **AFTER.** The barrier cuts at p+1, and `[p+1, r]` reads it within 0.5 m, so it is blocked.
  - **What changes.** The piece `[p+1, r]` moves open to 0, `has_barriers` FALSE to TRUE, and the mapping code with it, along the whole segment. It is not a sliver, so it lands in `km_acc_open_to_0` and `km_has_barriers_change`, which the header says should be 0.
  - **The cascade can go the wrong way.** That newly cutting barrier at p+1 can now suppress a later-source break at p+2 that cut before. A second barrier raw at about p+2.3 then sits 1.3 m inside the segment starting at p+1 and reads open: 0 to open on a whole segment.
  - **Impact.** A correct run can report non-zero non-sliver changes that the README, RUNBOOK and script header call impossible. It is rare (it needs a barrier 1 to 1.5 m above a removed position) but likely at the scale of 5 groups. Name the case in RUNBOOK §2c and the script header. It would help to count it apart, for example pieces whose AFTER segment starts at a non-observation break within 1 m of a removed position, rather than reading any non-zero as unexplained. Also, "each such sliver is 1 m long" should be "at most about 1.5 m": raw barrier measures, not breaks, decide the downstream test.

- **[fragile: restated claim] R/lnk_pipeline_break.R:18-19 (and man/lnk_pipeline_break.Rd).** "Omitting a barrier source skips both segmentation and access-gating from it." This is false for every barrier source except `subsurfaceflow`.
  - Only `subsurfaceflow` reads `break_order`: `lnk_pipeline_prepare.R:513/681` and `lnk_pipeline_classify.R:107`.
  - `falls`, `barriers_definite`, `gradient_minimal` and `crossings` still feed classify's `streams_breaks` and the per-species barrier tables the access walk reads, whatever `break_order` says.
  - The old wording had the same error, but this diff rewrote the sentence and kept the claim. Say that omitting a source skips only its segmentation, with `subsurfaceflow` the one source whose barriers are also dropped.

No other issues. Checked and found sound:
- The SQL in `.lnk_pipeline_break_obs()`: `round(max)` equals `max(round)` under Postgres rint.
- The manifest check and the `extends:` shallow merge: `default_tuned` inherits `top_per_species`.
- The config hash: it covers every config.yaml on the chain.
- The tests' mocks and expectations.
- run.sh: guarded `cd`, `local` per statement, `set -u` defaults, the macOS `sysctl` load average, and the group order (UPCE before PARS, LKEL before BULK).
- bias.R's attach rule matches the validator's (`< 1`).
- integer64 counts through `pmax`, `/`, `round` and `write.csv`.
- psql `-v` interpolation outside dollar quotes.
- The POST worktree at `71ccc2ce`, against HEAD, differs in R/ only by roxygen.
