# Findings — Count every group's fish records when asking whether a species is observed upstream (#401)

## Issue context

**If done:** a segment reads "observed upstream" when the species is recorded anywhere upstream of it, including in another group. **If never:** a main stem reads "accessible, not observed" right up to its group boundary even where the species is recorded just upstream, so a known-fish summary undercounts the corridors fish pass through.

## Problem

The code-2 walk reads `<schema>.observations` (`R/lnk_pipeline_run.R:284`, link@43e34096), which holds the group's own records only (`WHERE o.watershed_group_code = aoi`, `R/lnk_pipeline_prepare.R:346`). Barrier lifts had the same limit. Since #349 they read `<schema>.observations_province`, built in the same step. The recompute (`lnk_access(merge = TRUE)`) keeps a prior 2 and computes no new one (`observations = NULL`), so it does not fix this either.

Not measured: how many km this moves. bcfishpass models the province in one pass, so its code 2 likely sees every group's records; that is not checked against its SQL.

## Proposed

- **The code-2 walk reads `observations_province`** under `default`.
- **Breaks keep the group's own records,** since a record in another group cannot cut this group's segments.
- **The `bcfishpass` bundle** follows whatever bcfishpass's SQL shows.

**Cost.** A walk's cost is its province-wide probe of the features it is given (#261), so a province-wide record table may slow it. Measure it on the slowest group. NewGraphEnvironment/fresh#272's prefiltered walk may matter here.

## Acceptance

- **Fixture.** A record in group B upstream of group A's line makes A's segments below it read 2.
- **Builds before and after** on #396's groups plus one main-stem group downstream of others:
  - `access_<sp>` moves 1 → 2 only;
  - the walk's minutes are recorded against #396's.

Related: #349, #396, #403.


## Errors Encountered

| Error | Resolution |
|-------|------------|
