# Findings — A minimal network for tuning, with parent attributes on the full network (#415)

## Issue context

**If we do it:** habitat thresholds can be tuned on segments that know nothing about where fish were caught, and a rule tuned there applies unchanged to every other output, because each segment carries the habitat attributes of the minimal segment it was cut from. **If we never do:** a segment's gradient keeps depending on where fish were recorded and where a road crosses, and every tuning inherits that.

## Problem

`lnk_pipeline_break()` cuts streams at observations, gradient barriers, falls, definite barriers, habitat end points and crossings. Each cut shortens a segment, and a segment's gradient is averaged over its length, so the cuts change the gradient a habitat rule reads:

- **Observations make the gradient depend on the outcome.** On link 0.66.0's build (every observation a break), 86 % of electrofishing visits that caught a modelled species sat on a segment starting at the visit, against 10 % of visits that caught nothing (median segment 113 m against 305 m). `observation_breaks: top_per_species` (#396) cuts fewer, but a species' highest record on a stream is still a catch.
- **Crossings and habitat end points** don't depend on fish, but they cut segments at places unrelated to the stream's form.
- A downstream tuning of chinook rearing moved its gradient limit when the gradient source alone changed, so the tuning is sensitive to this.

Connectivity needs those cuts; habitat measurement doesn't.

## Proposed

- [ ] **Prove it on a few test groups first,** before any province-wide build: BULK and two or three groups with many chinook rearing records and many crossings, the minimal and full networks built from one commit. The assumption is that dropping `observations`, `habitat_endpoints` and `crossings` from `break_order` changes segmentation only. Check each place it might not:
  - **Superset:** every minimal cut is also a full cut, so each full segment lies inside exactly one minimal segment (none straddles a minimal cut). `gradient_minimal` depends on the species present, so both builds need the same species set.
  - **Access code 2** (`access_<sp>`, observed upstream) is computed at the resolution of the segments that remain: compare its km per species between the two builds and say what it means on longer segments.
  - **Crossings:** with no crossing cuts, classify's `barrier`/`potential`/`passable` labels and anything measured upstream of a crossing have no segment boundary to sit on. Confirm natural access (`streams_access`) is unchanged, and that crossing-based fields are absent or flagged rather than wrong.
  - **Habitat end points:** without their cuts, the user habitat overlay applies to whole segments. Measure how many km it over-extends.
  - **Connectivity pass** (rearing clusters with no spawning within 10 km): compare what it drops between the builds.
  - **Gradient:** the minimal segments' gradient against the full segments' length-weighted gradient over the same stretch, which should agree.
  - **Run time and row counts** per group for both builds.
- [ ] **A minimal network.** One output whose `break_order` is `gradient_minimal`, `falls`, `barriers_definite` (and `subsurfaceflow` if the methodology decision adds it), built from the same commit, Atlas, flow load and species as the full network it is compared with, so the break set is the only difference. `break_order` already supports omitting sources; check what code 2 access (`access_<sp>`, observed upstream) means at this coarser resolution.
- [ ] **Access on the minimal network.** Each segment carries `access_<sp>` per species (-9, 0, 1, 2) as the full network does. Which barriers observation overrides lifted, and the records behind each, is #434, so this network does not wait on #400.
- [ ] **Parent attributes on the full network.** Each segment of a fully broken network carries the id of the minimal segment it lies in, and that segment's gradient (and any other attribute a habitat rule reads), beside its own. A rule can then read either, and a rule tuned on the minimal network applies to the full one exactly.

Its outputs take their names from #414. The test builds don't wait on it; a province-wide build does.

## Not proposed

No change to `default`, `default_tuned` or `bcfishpass`; the minimal network is an addition. `default_extrabreaks` and `default_rearbreaks` cut at habitat gradient ceilings, which is the opposite question (more cuts, at thresholds a tuning would choose), and are untouched.

Relates to #294 (where observation points sit on a site, and how that biases threshold evidence) and #414 (output vocabulary).




## Exploration (2026-11-01, plan gate)

The findings that shaped the phases are in `task_plan.md` under "What the consumer needs" and
"What exploration settled". Two reversed the issue's premises: the user habitat overlay applies to
fewer segments without endpoint cuts, not more (`frs_habitat_overlay()` and `lnk_habitat_gate()`
require the segment wholly inside the range); and a full segment is not always inside one minimal
segment (observations cut first; a later cut within 1 m of an end is skipped), so the parent join
is largest overlap, not containment.

## Errors Encountered

| Error | Resolution |
|-------|------------|
