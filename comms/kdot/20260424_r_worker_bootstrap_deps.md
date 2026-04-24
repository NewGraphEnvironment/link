---
from: link
to: kdot
topic: R package dependencies worth catching in worker-machine bootstrap
status: open
---

## 2026-04-24 — link

Al started distributing pipeline work from M4 to M1 today (per rtj's M1 R-worker verification `comms/rtj/20260423_m1_r_worker_verified.md`). First real cross-machine test run on M1 hit a missing CRAN dep — `mockery` — which blocked fresh's test suite from running. Installed manually; captured the pattern as soon as it came up.

Suggested addition to the worker-machine R bootstrap (wherever kdot manages R package baselines):

### Known test-time deps for fresh + link

- `mockery` — used by test mocks (`mockery::stub()` patterns) in fresh's test-frs_extract.R and possibly others. Pure R, small, CRAN.
- `tarchetypes` — required by link's `data-raw/_targets.R` (`tar_map()` specifically). Manifests as "there is no package called 'tarchetypes'" when running `link-tarmake-*` workloads. CRAN, small.

### Broader pattern

Rather than tracking individual deps reactively, consider a worker-machine bootstrap that runs roughly:

```r
# Core NGE packages (from GitHub)
pak::pak(c(
  "NewGraphEnvironment/fresh",
  "NewGraphEnvironment/link",
  "NewGraphEnvironment/flooded",
  "NewGraphEnvironment/drift"
))

# Test + dev toolchain (CRAN)
pak::pak(c(
  "devtools",
  "testthat",
  "mockery",      # fresh tests
  "pak",
  "targets",
  "tarchetypes",
  "crew",
  "DBI",
  "RPostgres",
  "digest"        # tar_make digest checks
))

# Validate DB connectivity + R worker verify
source("rtj/scripts/hosts/crew-worker_verify.R")
```

Rolling this into a single `kdot-r-worker-setup.R` or similar would save future M1-class bootstraps from the same one-off installs. And when we add a new test dep in fresh/link, we add it both to DESCRIPTION + the kdot bootstrap so the next machine Just Works.

### Action for kdot

1. Decide if a worker-R-bootstrap script is in scope for kdot (vs. left as manual setup).
2. If yes, add `mockery` plus the list above. Mark it as the canonical source — fresh/link CLAUDE.md notes can point at it.
3. If no, leave this thread as a searchable record of what we installed manually on M1 today.

Not blocking anything — M1 is functional. Noting forward.
