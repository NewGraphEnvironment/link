# Task Plan: lnk_barrier_overrides (#25)

## Goal
Build `lnk_barrier_overrides()` — process fish observations, habitat confirmations, and control tables into a barrier skip list for fresh. Replicate bcfishpass v0.5.0 barrier filtering logic.

## Phases

### Phase 1: Function skeleton + observation overrides
- [x] Write `R/lnk_barrier_overrides.R` with roxygen docs
- [x] Observation counting via `fwa_upstream()` SQL (per-species thresholds from params)
- [x] Date filter, buffer distance, species grouping from params CSV
- [x] Test with `bcfishobs.observations` on ADMS — 14 BT barriers overridden

### Phase 2: Habitat confirmation overrides
- [x] Load `user_habitat_classification` from bcfishpass CSV (15,226 records)
- [x] Any confirmed habitat upstream = barrier removed — 3 per species group
- [ ] **BLOCKER**: 29 overrides is too few. Cayenne Creek still blocked in fresh despite no barriers in streams_breaks downstream. Need to understand how fresh computes accessibility — it's not checking streams_breaks directly.
- [ ] Investigate fresh access SQL to understand where barrier list comes from

### Phase 3: Exclusions and control table
- [ ] Apply observation exclusions (filter bad data)
- [ ] Apply barrier control table (locked barriers not overridable)
- [ ] Load both from bcfishpass data CSVs

### Phase 4: Integration test
- [ ] Run `lnk_barrier_overrides()` → pass to `compare_adms.R`
- [ ] Until fresh#129 ships, manually apply overrides in compare_adms.R SQL
- [ ] Verify CH/CO gap closes toward bcfishpass v0.5.0

### Phase 5: Code-check, tests, commit
- [ ] Code-check all diffs
- [ ] Write tests (mock or integration)
- [ ] Document + commit with planning checkboxes
- [ ] PR to adms-comparison branch

## Key SQL pattern
```sql
-- Count observations upstream of each barrier via fwa_upstream()
SELECT b.blue_line_key, b.downstream_route_measure
FROM barriers b
WHERE (
  SELECT count(*) FROM observations o
  WHERE o.species_code IN ('CH','CM','CO','PK','SK')
  AND o.observation_date >= '1990-01-01'
  AND fwa_upstream(b.blk, b.drm, b.wscode, b.localcode,
                   o.blk, o.drm, o.wscode, o.localcode, false, 20)
) >= 5
```

## Versions
- fresh: 0.12.6 (barrier_overrides param pending #129)
- bcfishpass: v0.5.0
- link: 0.0.0.9000
- bcfishobs: v0.3.2 (372,420 observations on Docker)
