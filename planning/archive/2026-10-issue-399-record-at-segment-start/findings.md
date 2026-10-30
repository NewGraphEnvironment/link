# Findings — Read a fish record at a segment's start as not upstream of that segment (#399)

## Issue context

**If done:** under `default`, the last segment reading "observed upstream" for a species is the one ending at its highest record on each line, so maps and summaries show where the highest fish is. **If never:** the segment starting at a species' highest record also reads observed, so "known" runs on past the fish to the next break of any kind.

### Problem

The code-2 walk calls `fresh::frs_network_features(direction = "upstream", include_equivalents = TRUE)` (`R/lnk_pipeline_access.R:216`, link@43e34096). That calls fwapg's `fwa_upstream()` with a 1 m tolerance (fresh@v0.43.0). On the same line it counts a record at measure `m` as upstream of a segment starting at `s` when `m > s` or `|s − m| ≤ 1`.

So the segment starting at a species' top record holds that record and reads 2. #396 measured the effect (`research/observation_breaks.md`): a species turns to 1 only at the first cut more than 1 m above its top, so its own top break never moves its own boundary.

With `include_equivalents = FALSE`, the same function counts the record only when `m ≥ s + 1`. Breaks are rounded to the metre (`frs_break_apply()`, `measure_precision = 0`), so a break at a species' top starts its segment within 0.5 m of the record. That segment then reads 1 and the one below it reads 2. The 1 m tolerance is fresh's own, so fresh needs no change.

### Proposed (as filed)

1. **A bundle key for how the walk reads a record at a segment's start.** The name is still to decide, for example `pipeline: observation_at_segment_start: upstream | not_upstream`. Absent means `upstream` (today), which the `bcfishpass` bundle keeps for parity; `default` sets `not_upstream`. Checked at manifest load, like `observation_breaks`.
2. **Only the observations call changes.** The barrier walks keep `include_equivalents = TRUE`, because a barrier at a segment's start must still block that segment.

This pairs with `default`'s `observation_breaks: top_per_species` (#396). Each species' top is already a break, so the boundary lands on it.

### Acceptance (as filed)

- **Fixture.** Species X recorded at 100 and 520.6 m on one line, breaks at 100 and 521: the segment starting at 521 reads 1 and the one ending there reads 2. The test goes red with `TRUE` restored.
- **Builds before and after** on #396's groups (LKEL, BULK, UPCE, PARS, ELKR), compared on measure-overlap pieces as `data-raw/logs/observation_breaks_396/pre_post_diff.R` does:
  - `access_<sp>` moves 2 → 1 only: never 1 → 2, never to or from 0;
  - each moved piece's segment starts within 1 m of a record of that species with none further upstream;
  - `has_barriers_<sp>_dnstr`, habitat flags and mapping codes do not move.
- **`bcfishpass` builds** of BULK and PARS are unchanged.

Related: #396, #403 (the summary that reads this).

## Plan-mode exploration (2026-10-30)

### bcfishpass reads a record at a segment's start as not upstream

`~/Projects/repo/bcfishpass` at `620dbe43` (2026-10-01), `model/01_access/sql/load_streams_upstr_observations.sql`: both CTEs join `bcfishpass.streams a` to `bcfishpass.observations b` on `FWA_Upstream(a.blue_line_key, a.downstream_route_measure, a.wscode_ltree, a.localcode_ltree, b.blue_line_key, b.downstream_route_measure, b.wscode, b.localcode, False, 1)`. `load_streams_access.sql` then codes 2 where `'<SP>' = any(obsrvtn_species_codes_upstr)`. So the issue's "the `bcfishpass` bundle keeps `upstream` for parity" is wrong: parity needs `FALSE`. This is the mechanism #403 found for link's observed km running 1.9 to 29.7 km above the reference on BULK and PARS (`research/known_suspected_km.md`, "Against bcfishpass": every disagreeing piece code 2 in link and 1 in bcfishpass, on a segment starting within 1 m of a record).

### What `include_equivalents` does in fwapg

`whse_basemapping.fwa_upstream(…, include_equivalents boolean DEFAULT false, tolerance double precision DEFAULT 0.001)`, read with `pg_get_functiondef` on the local fwapg. The 10-argument overload fresh calls passes the segment's `downstream_route_measure` as both its downstream and upstream measure. Same-line test with `include_equivalents` false: `downstream_route_measure_b >= upstream_route_measure_a + tolerance`, i.e. `m >= s + 1` at fresh's tolerance of 1 (`fresh/R/frs_network_features.R`, the `walk_from` template passes `%4$s, 1`). With true the same branch returns true for locations at the same measure within tolerance (`m >= s - 1`). The tributary and distributary tests are the same in both branches.

### Where the walk is called

- `R/lnk_pipeline_access.R:272-283`: the one observation walk, `include_equivalents = TRUE`, `features_wscode_col = "wscode"`, `features_localcode_col = "localcode"`, arrays (species codes). Called from `lnk_pipeline_run()` (`R/lnk_pipeline_run.R:290-301`) with `observations = <schema>.observations`.
- `lnk_access()` (`R/lnk_access.R:193, 206`) passes `observations = NULL`; its `merge = TRUE` keeps a prior 2 (`R/lnk_access.R:224`). So the recompute cannot see this change, and every persisted group keeps the old reading until re-modelled.
- Barrier walks (`:217-227`, `:247-257`) keep `include_equivalents = TRUE`.

### The vocabulary

`.lnk_vocabulary_spec_acc()` digests `cfg$species`, the seven access columns of `parameters_fresh`, the presence table and two code-held rules; a code change in the walk leaves the digest unchanged. `.lnk_vocabulary_match()` returns the one live row for a spec and ignores retired rows that share it, so "retire `acc-v1` and `acc-bcfp`, add `acc-v2` and `acc-bcfp-2` with the same specs" works without code change. `vocab_append_only()` (`tests/testthat/test-lnk_vocabulary.R`) allows filling `retired` and adding rows, refuses a rename, a re-spec or an unretire. RUNBOOK §6b names `acc-bcfp-2` for "a new transcription of bcfishpass's rules".

### Where to build

m1's local docker fwapg (`fresh-db`, up 13 days, 0 other active clients at planning time, 325 G free on the host). It holds `fresh.streams_vw_bcfp` (BULK 42,965 rows, PARS 43,655; no version comment; #403's reference on m4 was `v0.7.14-113-ga7373af`), `bcfishobs` (4 tables), `fresh` (bcfishpass-config builds of BULK, PARS, UPCE at link 0.50.0 / fresh 0.33.0, 2026-09-02) and `fresh_default`. The `zz396_*` schemas live on m4, not here. Installed fresh 0.47.0 (`RemoteSha 2c35e3eb`) matches the pin.

### Reusable harness

`data-raw/logs/observation_breaks_396/`: `run.sh` (quiet-database gate, PRE/POST worktrees, `wsg_run_one.R` with `LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn LNK_SCHEMA=…`, `status.tsv` with load averages, a retry per model step), `pre_post_diff.R` (measure-overlap pieces per `(wsg, blue_line_key)`, pieces under 1 cm dropped, direction rule per piece, `n_violation` must be 0). `data-raw/logs/known_suspected_403/rollup.R` and `parity_pieces.sql` give the observed/unobserved split and the parity reading against the reference view.

### Readers of the code-2 rule in prose

RUNBOOK §2c ("within 1 m of it", "at least start − 1"), `R/lnk_pipeline_break.R` (the break-source table row and `.lnk_pipeline_break_obs()` roxygen), `inst/extdata/configs/default/config.yaml` (`observation_breaks` comment), `research/observation_breaks.md` ("The rule"), `research/known_suspected_km.md` ("What will move these numbers"), `data-raw/logs/observation_breaks_396/pre_post_diff.R` (frozen evidence; not edited).

## Errors Encountered

| Error | Resolution |
|-------|------------|
