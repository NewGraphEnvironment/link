# link

> Stream Network Habitat Interpretation

An interpretation layer between field/modelled evidence and
stream-network habitat modelling. Loads override CSVs through a
canonical schema, snaps points to the network, matches records across
data systems, resolves per-species barrier connectivity from
observations and confirmations, and orchestrates a multi-phase pipeline
that produces per-segment habitat outputs. Pairs with
[fresh](https://github.com/NewGraphEnvironment/fresh) for the modelling
engine. Currently reproduces
[bcfishpass](https://github.com/smnorris/bcfishpass)’s fish-passage
classification method on BC’s Freshwater Atlas; interpretation logic is
network-agnostic by design.

> Experimental — APIs and outputs change without notice as the package
> consolidates.

## Installation

``` r

pak::pak("NewGraphEnvironment/link")
```

## Prerequisites

PostgreSQL with [fwapg](https://github.com/smnorris/fwapg) loaded (same
prerequisite as `fresh`; see `fresh`’s `docker/` for a local setup).
Connection via
[`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)
or direct
[`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## What link does

link sits between raw evidence — PSCIS crossings, fish observations,
habitat confirmations, falls, user-defined barriers — and the
habitat-modelling engine:

1.  **Load** override CSVs
    ([`lnk_load()`](https://newgraphenvironment.github.io/link/reference/lnk_load.md),
    [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md))
    with canonical-schema validation via
    [crate](https://github.com/NewGraphEnvironment/crate).
2.  **Snap** points to the network
    ([`lnk_points_snap()`](https://newgraphenvironment.github.io/link/reference/lnk_points_snap.md)).
3.  **Match** crossings across data systems by network position
    ([`lnk_match()`](https://newgraphenvironment.github.io/link/reference/lnk_match.md))
    within a configurable in-stream distance tolerance — linking PSCIS,
    MoTI, operator-submitted, and provincial inventories.
4.  **Resolve** per-species barrier overrides from evidence
    ([`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)):
    which gradient or falls barriers to skip given upstream
    observations + habitat confirmations.
5.  **Orchestrate** the pipeline (`lnk_pipeline_*()`, or
    [`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
    end-to-end) that produces per-watershed-group habitat outputs
    reproducing bcfishpass.
6.  **Compare** runs across configurations (`lnk_compare_*()`,
    [`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md),
    `lnk_baseline_*()`) for province-wide parity audits and
    reproducibility checks.

## The pipeline

For a given watershed group:

    load → setup → prepare → break → access → classify → connect → crossings → persist

Each phase is a callable function (`lnk_pipeline_<phase>()`), so a user
can stop, inspect, resume, or rebuild from any phase.
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
chains them end-to-end.
[`lnk_baseline_current()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_current.md)
captures a known-good run as a reference for diffing future runs.

## Using with fresh

[fresh](https://github.com/NewGraphEnvironment/fresh) is the modelling
engine — it segments, classifies, and aggregates on the network. link
prepares fresh’s two key inputs:

- **Break sources** for `frs_network_segment()` — per-table specs
  assembled via
  [`lnk_source()`](https://newgraphenvironment.github.io/link/reference/lnk_source.md).
- **Barrier overrides** for `frs_habitat_classify()` — a per-species
  skip list produced by
  [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md).

The two together reproduce bcfishpass on the Freshwater Atlas.

## Roadmap

link is currently FWA-grounded through its dependency on `fresh`. The
interpretation logic — what counts as evidence of a passable barrier,
how observations resolve override decisions, how cross-system crossings
are matched — is network-agnostic by design. Active design work:

- **Network agnosticism** inherited from `fresh`’s in-flight `spyda`
  topology engine
  ([fresh#41](https://github.com/NewGraphEnvironment/fresh/issues/41))
  and configurable column names
  ([fresh#44](https://github.com/NewGraphEnvironment/fresh/issues/44)).
- **Crossing-connectivity scoring** —
  [`lnk_score()`](https://newgraphenvironment.github.io/link/reference/lnk_score.md)
  framework for combining multiple connectivity signals into a
  prioritization output.
- **Province-wide parity audits** — `lnk_compare_*()` machinery for
  systematic comparison of pipeline variants and reproduction of an
  authoritative reference run.

## Ecosystem

| Package | Role |
|----|----|
| **link** | Stream-network habitat interpretation (this package) — interprets evidence, drives the modelling engine |
| [fresh](https://github.com/NewGraphEnvironment/fresh) | Stream-network modelling engine — segment, classify, cluster, aggregate |
| [crate](https://github.com/NewGraphEnvironment/crate) | Canonical schema + validation for input CSVs |

## License

MIT (see
[`LICENSE`](https://newgraphenvironment.github.io/link/LICENSE)).
Redistributed bcfishpass override data carries its own license — see
[`NOTICE.md`](https://newgraphenvironment.github.io/link/NOTICE.md) and
[`LICENSE-bcfishpass`](https://newgraphenvironment.github.io/link/LICENSE-bcfishpass).
