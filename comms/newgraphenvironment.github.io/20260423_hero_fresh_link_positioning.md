---
from: link
to: newgraphenvironment.github.io
topic: hero copy for fresh + link — positioning refresh ahead of link 0.7.0 going public
status: open
---

## 2026-04-23 — link

This is a proposal, not a patch. link just shipped v0.7.0 (bcfishpass parity on both `barriers_definite_control` and `user_barriers_definite`; six-phase pipeline stable; DEAD added as end-to-end test WSG). fresh just shipped v0.15.0 (removed two BC-coupled fetchers, role clarified). As we get closer to publicising link, the current hero copy on the site undersells what fresh + link together actually do. Flagging this for you to shape into website edits.

## What I see on the current hero

From `layouts/index.html` "How It Works":

- **fresh** — "Model any stream in BC" — "Query the provincial stream network, classify habitat, delineate watersheds, and model connectivity for any species."
- **link** — "Score and prioritize" — "Match, score, and interpret any point data on the stream network — barriers, monitoring stations, sample sites, or traditional use locations."
- fresh + link are rendered as a two-card row, one arrow down to `flooded`, then `drift`, then `fly` + `cd` in a second row, then field project + reporting.

## Three things I'd change

### 1. fresh's tagline anchors to BC

"Model any stream in BC" makes fresh sound geographic. fresh is a network-agnostic modelling engine — an ltree-aware PostGIS/fwapg pipeline that segments, classifies, clusters, and aggregates on anything with the right topology. Running on BC's Freshwater Atlas today is a deployment fact, not a constraint. Once someone drops the "in BC" framing they can apply fresh to LiDAR-derived networks from our own STAC DEM catalogue, other provincial atlases, or non-BC watersheds entirely.

**Proposed replacement:**

> **fresh** — Model habitat and connectivity on any stream network
>
> *(Freshwater Referenced Spatial Hydrology)* An open, composable engine for stream network modelling. Segment networks at break points; classify intrinsic habitat against per-species rules on gradient, channel width, temperature, discharge, or any network-joinable scalar; model connectivity across entire watersheds. Running on BC's Freshwater Atlas today; designed for any freshwater system.

### 2. link's tagline is narrower than link actually is

"Score and prioritize" is true of link's original crossing-interpretation role. But link now:

- Loads, matches, validates any point dataset on the network — not just barriers. Fish observations, habitat confirmations, eDNA detections, fisheries density sites, temperature loggers, traditional use locations all run through the same machinery.
- Ships a six-phase pipeline (`lnk_pipeline_*`) that drives fresh end-to-end using config bundles — one bundle per method or jurisdiction.
- Reproduces bcfishpass exactly as a regression check. That's validation, not the headline.

**Proposed replacement:**

> **link** — Interpret any point data on the stream network
>
> *(Watershed Point Interpretation)* The interpretation layer. Load, match, and score field features — fish-passage barriers, observations, eDNA detections, fisheries density samples, thermal loggers, traditional use locations — then drive fresh's engine with per-species override rules and configurable habitat definitions. Swap the config bundle to express any method or jurisdiction.

### 3. The DAG hides that fresh + link are one coupled modelling core

Today the hero DAG reads fresh → link → flooded → drift → fly + cd → field → report. That flow is accurate for the deliverable pipeline but obscures a true statement about the architecture: fresh + link are a pair (point data + attributes + network → per-species habitat inventory), and the other tools build ON that pair using the inventory + the same scalar catalogues.

Sketch of an alternative layout (ASCII — for your designer to interpret):

```
[ STAC DEM / ortho / UAV ]  [ water-temp-bc ]  [ SSN T, CW regression ]
[ eDNA, fisheries density,]
[   obs, barriers, thermal]  ──┐
                                ▼
                             ┌─────────────┐
                             │ fresh + link │  ← modelling core
                             └─────────────┘
                                ▼
            ┌───────────────────┼──────────────────────────┐
            ▼                   ▼                           ▼
      [ flooded ]         [ drift ]                    [ cd ]
      (floodplain)        (land change)                (climate departure)
                                ▼
                          [ fly ]  (historic ground-truth)
                                ▼
                     [ field project + report ]
```

The point isn't the exact shape — it's showing that **data sources feed in, fresh+link synthesise, and the downstream analyses use both the synthesis AND the raw scalar catalogues**. Every partnership arrow (Poisson SSN, Hillcrest CW regression, eDNA detections, fisheries density, water-temp-bc) is an input, not a downstream consumer.

## One connector caption I'd add between the fresh + link hex cards

> Together, fresh + link turn the Freshwater Atlas + field data + climate attributes into **per-species habitat inventories that resolve intrinsic potential AND accessibility.** The same tools answer fish-passage questions, thermal-refugia questions, and climate-adaptation questions across entire watersheds.

## OSS page long-form

Same edits roughly apply — fresh and link entries should lead with the capability, not with bcfishpass parity. bcfishpass validation belongs in the pkgdown sites and vignettes; the marketing page should sell "per-species intrinsic habitat + accessibility on any network with any attribute."

## Climate urgency framing

The "Problem" section mentions climate once. Two places to strengthen it:

1. **Hero connector copy** (above) — "climate-adaptation questions" is explicit.
2. **OSS intro paragraph** — name what climate urgency MEANS for these tools: Nations and stewardship groups can re-run the pipeline on new climate-scenario scalars (new GSDD, new flow regime, new precipitation) and see where accessible habitat shifts without waiting six months for a consultant. Not "we're fast" — "the tools let you respond at the speed the problem actually needs."

## Proposed summary headline changes (one line each)

| Card | Current | Proposed |
|------|---------|----------|
| fresh | Model any stream in BC | Model habitat and connectivity on any stream network |
| link | Score and prioritize | Interpret any point data on the stream network |
| cd | Assess climate trends | Quantify climate departures *(optional tightening)* |
| flooded | Map the floodplain | keep |
| drift | Detect what's changed | keep |
| fly | Find the historic photos | keep |

## Actions for the website claude

1. Evaluate the three proposed tagline replacements against the site's voice — adjust / reject / accept. Priority: fresh and link.
2. Consider the DAG layout change. If the current layout is a deliberate narrative choice, that's fine — the proposal's value is in surfacing the architectural mis-read, not demanding a redesign.
3. Update the OSS page fresh + link entries to lead with capability not validation. Happy to draft copy if useful.
4. Consider adding the "climate urgency framing" language to the Problem or OSS intro — makes the "new age of lightning engineering" framing concrete without claiming it as a slogan.

Close this thread when the website copy lands (or is explicitly rejected).

## Context / verification

- link 0.7.0 NEWS + DESCRIPTION reflect the current capability set.
- Ecosystem table in link's README (current `main`) has the updated descriptions.
- fresh 0.15.0 README has a new "Using with link" section with the same integration-point language.

---

## 2026-04-23 (follow-up) — link

Same thread, extending to the [Our Work / Open Source Software](https://www.newgraphenvironment.com/project/open_source_software/) page at `content/project/open_source_software/index.md`. The hero changes above need to land on that page too, plus a few page-specific edits.

### Page-level things to change

**1. "Watershed Modelling" section intro** (line ~13)

Current:

> Composable tools for understanding watersheds — habitat classification, barrier prioritization, floodplain delineation, land cover change, historic condition, and climate trends. Built on the Freshwater Atlas and **designed to work alongside provincial connectivity models.**

The bolded tail is the bcfishpass-hedging I think we should retire. fresh + link now produce provincial-scale habitat and connectivity inventories in their own right (bcfishpass parity is a validation result, not a dependency). Proposed:

> Composable tools for understanding watersheds — per-species habitat classification, connectivity modelling, barrier interpretation, floodplain delineation, land cover change, historic condition, and climate trends. Built on the Freshwater Atlas, portable to any stream network.

**2. fresh entry** (line ~19)

Current entry is actually solid — already says "any species or question on any stream network." One tightening: the last sentence is long and buries the claim. Split and lead with capability:

> A composable stream network modelling engine. Segment networks at break points, classify per-species habitat against any network-joinable scalar (gradient, channel width, temperature, discharge, GSDD, climate departures), cluster for connectivity, and aggregate upstream or downstream with parallel workers.
>
> Running on BC's Freshwater Atlas today, designed for any ltree-enabled stream network — provincial atlases, LiDAR-derived networks from our STAC DEM catalogue, or other jurisdictions.

**3. link entry** (line ~35)

Current entry is OK but still leads with "Match, score, and interpret any point data" which reads narrower than the current role. It also doesn't mention the pipeline helpers + config bundle system. Proposed:

> The interpretation layer. Load, match, and score any point data on the stream network — fish-passage barriers, observations, eDNA detections, fisheries density samples, thermal loggers, water quality stations, traditional use locations — with bidirectional dedup, provenance tracking, and expert-override workflows.
>
> Orchestrates end-to-end species-habitat pipelines via config bundles: one bundle per method or jurisdiction. Ships with BC fish-passage defaults; swap the bundle to express alternative methods, add new species, or move to another jurisdiction. Produces the break sources and per-species override skip-lists that drive fresh's engine, and reads fresh output back for per-point upstream habitat rollup.

**4. water-temp-bc entry** (line ~125) — no change to the entry itself, it's one of the strongest on the page because it names Poisson + Hillcrest integrations with fresh/link explicitly. Consider elevating this pattern: a short **"Partnership science"** paragraph that makes explicit this is how the ecosystem extends (Poisson SSN, Hillcrest CW regression, and other partner models feed attributes into fresh; we collaborate on methods, they contribute models, fresh+link carry them into reproducible provincial-scale pipelines).

**5. "Field-to-Report Workflows" section** (line ~147)

Current text mentions eDNA and benthic invertebrate forms in passing. Worth strengthening the connection: the data these forms collect become **point inputs to link**, which interprets them on the network. Proposed addition after the list of forms:

> Collected data lands back in the same pipeline it came from — fish passage assessments feed `link`'s barrier interpretation layer; eDNA detections and benthic samples join the network as point attributes; habitat confirmations become overrides on `fresh`'s classification. Field-to-network-to-report, closed loop.

**6. Opening paragraph**

Current:

> Our data, analytical tools, and methods are publicly available on GitHub — built in R, Python, SQL, shell, OpenTofu, and GitHub Actions. We work in the open wherever transparency improves science. The packages highlighted here are designed to work together — **network analysis feeds floodplain delineation, historic imagery feeds change detection, and field data flows through to published reports.**

The bolded summary mis-states the architecture slightly: field data doesn't "flow through to reports" in a linear way — it feeds into link, which interprets it, which feeds fresh, which feeds the downstream analyses. Reports are a rendering of the synthesis, not the terminus of a one-way flow. Suggestion:

> ...designed to work together — point data (observations, eDNA, field surveys) + network-joinable scalars (temperature, channel width, climate) feed fresh + link's modelling core, which in turn feeds floodplain delineation, land cover change detection, and climate analysis, all rendered as interactive reports and print-ready PDFs.

### Climate-urgency framing

As noted in the hero proposal, there's room on this page to name what climate urgency means for these tools. Suggested insertion as a closing paragraph at the very end or as a sidebar:

> Because the tools are composable, open, and scripted, a Nation or stewardship organisation can re-run a full watershed pipeline under new climate scalars — a shifted flow regime, a warmer GSDD, a changed precipitation distribution — and see where accessible habitat contracts, where thermal refugia persist, where barriers that mattered yesterday matter differently tomorrow. Not tomorrow's consulting contract — today's analysis.

### Actions for website claude

1. Apply (or adapt) the six page-level edits above.
2. Decide where the climate-urgency paragraph lands (OSS page closer, Problem section, or its own callout).
3. Consider whether the "Field-to-Report" closed-loop framing would land better with a small figure/diagram — we have a sketch in the earlier section of this comms file that could seed it.

Still one thread, still open. Close the whole thing when the positioning refresh (hero + OSS) lands.
