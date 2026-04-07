# link <img src="man/figures/logo.png" align="right" height="139" alt="" />

Crossing connectivity interpretation for fish passage.

link is the domain layer between raw crossing data and
[fresh](https://github.com/NewGraphEnvironment/fresh)'s generic network
engine. It scores, overrides, and prioritizes crossings using configurable
severity thresholds and multi-source data integration.

## Installation

```r
pak::pak("NewGraphEnvironment/link")
```

## What it does

```
raw crossing data -> link (interpret, score, override) -> fresh (segment, classify)
```

1. **Override corrections** — load and apply hand-reviewed crossing fixes
   accumulated across field seasons
2. **Multi-source matching** — link PSCIS assessments, modelled crossings,
   and MOTI culvert inventory using network position
3. **Severity scoring** — classify crossings by biological impact
   (high/moderate/low) using actual measurements, not binary BARRIER/PASSABLE
4. **Break source bridge** — produce tables that plug directly into
   `frs_habitat(break_sources = ...)`

## Quick start

```r
library(link)
conn <- lnk_db_conn()

# Load and apply corrections
lnk_override_load(conn, csv = "overrides.csv", to = "working.fixes")
lnk_override_apply(conn, "working.crossings", "working.fixes")

# Score severity
lnk_score_severity(conn, "working.crossings")

# Feed to fresh
src <- lnk_break_source(conn, "working.crossings")
fresh::frs_habitat(conn, "MORR", break_sources = list(src))
```

See `vignette("crossing-interpretation")` for the full pipeline on the
Morice (MORR) watershed group.
