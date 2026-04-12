# Task Plan: SK spawning cluster divergence (#29)

## Goal
Close the +54% SK spawning gap between fresh 0.12.6 and bcfishpass v0.5.0.

## Phases

### Phase 1: Investigate bcfishpass SK spawning logic
- [ ] Read `load_habitat_linear_sk.sql` spawning sections in detail
- [ ] Document: how does bcfishpass connect SK spawning to rearing lakes?
- [ ] Compare to fresh frs_cluster approach

### Phase 2: Identify divergence
- [x] Adams River: fresh 112 km vs bcfishpass 74 km — fresh extends 10km further downstream
- [x] Root cause: no downstream distance cap from rearing lake. bcfishpass caps at 3km.
- [x] SK rearing gap was thresholds on lake segments — fixed by fresh#131, workaround removed

### Phase 3: Fix
- [x] Filed fresh#133 (connected_distance_max predicate)
- [x] Removed thresholds: false workaround (fresh#131 handles it natively in 0.12.7)
- [x] SK rearing +0.2%. SK spawning +54% blocked on fresh#133.
- [x] Code-check, commit with checkboxes

## Versions
- fresh: 0.12.6, bcfishpass: v0.5.0, link: 0.0.0.9000
