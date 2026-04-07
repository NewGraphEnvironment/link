# link ![](reference/figures/logo.png)

Crossing connectivity interpretation for fish passage.

link is the domain layer between raw crossing data and
[fresh](https://github.com/NewGraphEnvironment/fresh)’s generic network
engine. It scores, overrides, and prioritizes crossings using
configurable severity thresholds and multi-source data integration.

Crossings are features on the network. Some break geometry (confirmed
barriers fed to fresh as break sources). Others just index for
downstream relationship queries (unassessed crossings, observations).

## Installation

``` r
pak::pak("NewGraphEnvironment/link")
```

## Data sources

No database required for the core pipeline:

| Data                      | Source                                                               |
|---------------------------|----------------------------------------------------------------------|
| Crossings (province-wide) | `fresh::system.file("extdata", "crossings.csv")`                     |
| PSCIS assessments         | `bcdata::bcdc_get_data("7ecfafa6-...")`                              |
| Override CSVs             | `bcfishpass/data/` directory                                         |
| Habitat thresholds        | `fresh::system.file("extdata", "parameters_habitat_thresholds.csv")` |

## What it does

    bcfishpass CSVs (overrides) --> link (interpret, score) --> break source spec --> fresh
    fresh CSV (crossings)       -->
    bcdata (PSCIS assessments)  -->

1.  **Override corrections** — load and apply hand-reviewed crossing
    fixes accumulated across field seasons
2.  **Multi-source matching** — link PSCIS assessments, modelled
    crossings, and MOTI culvert inventory using network position
3.  **Severity scoring** — classify crossings by biological impact
    (high/moderate/low) using actual measurements, not binary
    BARRIER/PASSABLE
4.  **Break source bridge** — produce specs that plug directly into
    `frs_habitat(break_sources = ...)`

## Quick start

``` r
library(link)

# Load crossings from fresh CSV
crossings <- read.csv(
  system.file("extdata", "crossings.csv", package = "fresh"))
morr <- crossings[crossings$watershed_group_code == "MORR", ]

# Load and apply override corrections (DB needed for SQL operations)
conn <- lnk_db_conn()
lnk_override_load(conn, csv = "overrides.csv", to = "working.fixes")
lnk_override_apply(conn, "working.crossings", "working.fixes")

# Score severity
lnk_score_severity(conn, "working.crossings")

# Feed to fresh
src <- lnk_break_source(conn, "working.crossings")
fresh::frs_habitat(conn, "MORR", break_sources = list(src))
```

See
[`vignette("crossing-interpretation")`](https://newgraphenvironment.github.io/link/articles/crossing-interpretation.md)
for the full pipeline on the Morice (MORR) watershed group — the same
steps scale to any watershed group for provincial coverage.
