# Code-check round 4 — #399 (branch diff against 804276e6)

## Checklist read

- `code-check.md.index`, `code-check-r.md.index`, `code-check-shell.md.index` and `code-check-spatial.md.index`, all in full.
- The prose of every H3 under `## Mechanisms` in `code-check.md`. The ones that bear on this diff are "A guard's scope, escape hatches, and remedies" (terminate by enumeration against the source), "Written data outlives the fix" and "A proxy is not the property".
- Full texts, for the tools this diff uses:
  - `code-check-spatial.md`: "FWA `upstream_route_measure` misses the next segment's start".
  - `code-check-r.md`: "Postgres row order is never fixed…" and the testthat skip and mock rules.
- soul `readme.md`: "Check each claim against the code path a run takes".

## What I checked, and what held

- **The SQL fresh runs.** fresh 0.47.0 (installed, and pinned in `DESCRIPTION`) calls fwapg's 10-argument `fwa_upstream(blk, drm, wsc, lc, blk, drm, wsc, lc, ie, 1)`. That form passes the segment's start as both its downstream and upstream measure.
  - Under `FALSE` the same-line test is `m >= start + 1`. Under `TRUE` it is `m > start OR |start - m| <= 1`, which is `m >= start - 1`.
  - The code clauses (tributary, side channel, distributary exclusion) are identical under both values. So the `acc-v2` and `acc-bcfp-2` definitions are right, including "Its clauses that read watershed codes are unchanged".
- **Can the segment starting at a species' top still read 2 from that record through the side-channel clause?** That would falsify "no longer reads 2 from that record" in `acc-v2`. Over the five `default` post builds: 0 cases.
- **bcfishpass's own SQL.** `model/01_access/sql/load_streams_upstr_observations.sql` passes `False, 1` at both `smnorris/bcfishpass@620dbe43` and `9fabf7c0`.
- **`frs_break_apply()`** (fresh `R/frs_break.R`, `to_break`) cuts only at strictly more than 1 m from both of a segment's pre-call ends. So "within 1 m … does not cut" is inclusive, and the "exactly 1 m below → next end above" branch is right.
- **PARS example, `zz399_default_post`, line 359567332.** Segments 182476.7 and 183194.1 carry local code `.885589` and read BT 2. 182461 is the line's top BT record (local code `.888699`), and no other BT record shares the code with a larger local code. Segment 183353.7 (`.889845`) reads 1. Holds.
- **ELKR example, line 356549331.** BT record at 1 m, FWA feature 0–790. The record is exactly 1 m from the line start, so it makes no cut. Segment 0–112 reads 2 and 112 reads 1. Holds.
  - "the line's first end" is a segment end from a later break source, not an FWA end. That is consistent with "the next end above".
- **Tops lying within 1 m of an FWA end**, five `default` groups, per species and line: 31 with the end above, 18 less than 1 m below, 1 exactly 1 m below, and 68 equal. Each case lands where RUNBOOK's "that end if it lies above the record or less than 1 m below it, else the next end above" puts it.
- **Tops vs walk species.** `.lnk_pipeline_break_obs()` takes tops per raw `species_code`, and the walk matches `species_code` exactly, so each species' highest counted record is one of its own tops.
- **The vocabulary.**
  - The append-only check compares `definition`, `spec` and `introduced` only, so a `retired` value is allowed.
  - `.lnk_vocabulary_match()` returns the one live row of a shared spec, and refuses when only a retired row matches.

## Findings

- **[severity: bug]** RUNBOOK.md:211-213 (clause 3, "Where the segment's watershed and local codes differ, a record on a line with the same watershed code and a larger local code") — the qualifier is wrong for other lines.
  - fwapg's equal-codes branch (`wscode_a = localcode_a`, the bottom of a line, below its first tributary) counts a record on **any other blue line** whose watershed code descends from or equals the segment's. It applies no measure and no local-code test. The only exception is a distributary with identical watershed and local codes.
  - So a record on another line with the same watershed code and a larger local code counts there too. Clauses 1 to 3 as written exclude it, which makes a reader's prediction wrong:
    - clause 2 needs a code "above the segment's local code", and here the two codes are equal;
    - clause 3 is limited to segments whose codes differ.
  - Measured: PARS BT `id_segment` 30623 is line 359506268 at 0 m, with both codes `200.948755.936902.074405.539757`. It reads 2 in both `zz399_default_post` and `zz399_bcfishpass_post`.
    - It reads 2 only from the BT record on line 359015767 at 0 m (same watershed code, local code `…539757.199422`).
    - No BT record on its own line lies 1 m or more above its start, and none sits on a line with a deeper watershed code.
    - It is the only such segment in the seven post builds (0.12 km).
  - It is small, but the section presents itself as `fwa_upstream()`'s clauses, and this is a fourth branch outcome they leave out.
  - Fix: limit only the same-line part of clause 3 to differing codes. For example: "A record on a line with the same watershed code and a larger local code (fwapg's "capture side channels"), ignoring measure; on the segment's own line only where its watershed and local codes differ."
  - The other restatements ("tributaries, and fwapg's side-channel clause") carry no qualifier and are fine. So are both vocabulary definitions.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: bug]** README.md:54-56 — the example's printed output is the pre-#399 build. Running the shown code at this branch prints something else.
  - The code shown is `lnk_pipeline_run(conn, aoi = "PARS", cfg = <default>, …)` then `lnk_rollup_wsg()`.
  - The README prints BT `842.81` / `6039.34` and GR `596.01` / `3845.86`. Those are exactly `rollup.csv`'s `default,pre,PARS` rows, and `zz399_default_pre`.
  - At this branch the same run gives BT `815.31` / `6066.83` and GR `590.11` / `3851.75` (`rollup.csv` `post` rows; `pre_post_diff.csv` PARS bt 27.495 km and gr 5.893 km of 2 to 1).
  - The enumeration's candidate set is phrase-based, so it cannot see a stale number. `research/known_suspected_km.md:46-47` carry the same values, but they are marked as the pre-#399 baseline, so they are fine.
  - **Rule:** code-check.md "Written data outlives the fix"; soul readme.md "Check each claim against the code path a run takes"

- **[severity: fragile]** RUNBOOK.md:241-242 ("Both tests in the walk are monotone in the start: a record counts as upstream when its measure is at least start + 1"), with the same restatement at CLAUDE.md:142 (edited on this branch) and in `research/observation_breaks.md`, "Do the outputs move only where expected" and "What a merged piece does to code 2".
  - These sentences give the record test as the same-line measure test alone. Two paragraphs earlier, clause 3 counts a same-line record **below** the start, independent of measure (the PARS example).
  - The monotonicity conclusion still holds. The code clauses depend only on the segment's local code, which is constant within an FWA feature, and no segment spans an FWA end. So nothing a reader acts on is wrong. But the sentence contradicts the clause list it follows, and it is the kind of compression round 3 named.
  - The enumeration's verdict "names the measure test as the measure test: every 'same-line' sentence" misses these, because they say "a record counts as upstream" with no "same-line".
  - Fix: "a same-line record counts by measure when it is at least start + 1, and the code clauses are constant within an FWA feature".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"
