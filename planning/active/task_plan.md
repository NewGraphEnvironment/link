# Task Plan: requires_connected in lnk_rules_build (#27)

## Goal
Add `requires_connected` support to dimensions CSV and `lnk_rules_build()` so SK/KO spawning is constrained to lake proximity.

## Phases

### Phase 1: CSV + function
- [x] Add `spawn_requires_connected` and `rear_requires_connected` columns to both dimensions CSVs
- [x] Update `lnk_rules_build()` to emit `requires_connected` predicate when column value is non-empty
- [x] Regenerate both YAMLs
- [x] Code-check (clean), commit

### Phase 2: Test
- [ ] Rerun ADMS comparison with updated YAML
- [ ] Verify SK spawning converges toward bcfishpass 85.70 km
- [ ] Code-check, commit

## Design
Column value is the connected habitat type: `"rearing"`, `"spawning"`, or empty. Not a yes/no — the value IS the predicate argument. Abstracts beyond SK.

## Versions
- fresh: 0.12.6, bcfishpass: v0.5.0, link: 0.0.0.9000
