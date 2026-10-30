# Plan review — #401 (Plan agent, 2026-10-30, against baseline 8294e106)

Reviewer: unnamed `Plan` subagent, read-only. Findings as returned, each verified here before acting.

## Blockers (both reproduced)

1. **bcfishpass's code 2 is a hybrid.** `load_streams_upstr_observations.sql` (`smnorris/bcfishpass@620dbe4`)
   inserts `FROM spp INNER JOIN ids`; `ids` is same-group (`a.watershed_group_code = b.watershed_group_code`).
   A segment with no own-group record upstream gets no row; `load_streams_access.sql:72` coalesces it to an
   empty array, so it reads 1. Other groups' records count only where an own-group record (any species) is
   upstream. The plan's "no key" gate decision rested on reading `spp` alone.
   *Verified:* lines 60-73 of the SQL. *Resolved:* operator, 2026-10-30: reproduce it in the `bcfishpass`
   bundle (a `pipeline:` key), and file the draft in our fork: NewGraphEnvironment/bcfishpass#16
   (`upstream-draft`; confirm again and check what is pending before offering upstream).
2. **The walk's cost is output size.** fresh's array walk `array_agg`s every segment-record pair with no
   `DISTINCT` (`frs_network_features.R:343-365`), and R parses every element. bcfishpass takes
   `SELECT DISTINCT segment, species_code`. Province-wide, a Fraser main-stem segment would carry ~10^5
   codes. An upstream prefilter would not help (every Fraser record really is upstream).
   *Verified:* LFRA holds 287 segments of the Fraser main stem (`wscode_ltree = '100'`), and bcfishobs
   holds 126,371 records under `100`. *Resolved:* per-species existence walks (`result = "exists"`, which
   fresh already supports upstream) over each species' records, no fresh change; measured on LFRA and SETN
   before the builds. A fresh distinct-result mode is the fallback if that is too slow.

## Ordering

- The drop belongs in an `on.exit()` (line ~217 is a `stop()`; every later step can error). *Already done
  in 708fd066.* Phase 1 checkboxes were stale in the baseline the reviewer read; flipped in 7d6bb330.

## Assumptions

- Walk-cost harness: copy each group's segments into a temp table (a build walks a one-group working
  table), note that only the province table has GiST indexes, and read speed from the PRE/POST pairs, with
  #396's minutes as context only.
- Vocabulary: `introduced` 0.73.0 while DESCRIPTION is 0.72.0 during the builds, as #399's builds logged
  0.72.0 tokens under 0.71.x; noted in the evidence README, bumped at release.
- CT alias codes: both tables apply `.lnk_pipeline_break_obs_species()`, and the walk matches
  `sp_upper %in% x`, so nothing changes beyond out-of-group records. bcfishpass remaps CCT/ACT; no shipped
  species is CT. Parity note only.

## Acceptance

- `pre_post_diff.R`'s "each 1 → 2 has an out-of-group record upstream" is nearly guaranteed by
  construction. Add checks that can fail: (1) completeness, no POST piece at 1 with a qualifying record
  upstream (under the bundle's rule); (2) the AOI slice of the province table equals
  `<schema>.observations` row for row; (3) bcfishobs unchanged between PRE and POST.
- Add a downstream group (UPCE) to the `bcfishpass` builds: BULK and PARS main stems mostly hold their own
  records, so they cannot show the gate.

## Gaps

- Docs saying code 2 reads `<schema>.observations`: `R/lnk_pipeline_break.R:23` and `:152`, RUNBOOK §2c
  (line ~197) and §5 (lines ~586-587), `research/access_columns.md:80` (the table's ~4 s build now lives
  longer).
- No other code reader of either table (`habitat_variants_build.R:794`, `wsg_recompute_one.R` use
  `lnk_access(merge = TRUE)` with no observations).

## Scope

- LNTH is reasonable, but `recompute_deps.R`'s line rule lists groups *downstream*, so it cannot confirm
  LNTH reads upstream groups. Confirm by counting out-of-group province records upstream of LNTH's lowest
  segment per species. UPCE (below PARS) is already in the set.
