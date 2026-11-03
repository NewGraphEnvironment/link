# Code-check, PR 2 (#415 proof), round 3

## Checklist read

- code-check.md, `## Mechanisms`: the prose of every H3 (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). Tables skipped.
- code-check-shell.md: "On this Mac `stat` and `date` are GNU" (hit it while measuring the gz sizes).
- code-check-r.md: index lines for the DBI / Postgres / `data-raw/` headings (round 1 and 2 read them in full; no code in this round's diff touched them beyond what they reviewed).

## What was verified, and how

- Every number in the five texts checked against its CSV (`segments`, `superset`, `breaks_census`, `access_km`, `access_differences`, `gradient`, `status.tsv`, `connectivity`, `overlay`, `crossing_fields`, `placement`, `lifts`, `lifts_obs`) by script; the mechanism claims against the code (fresh `R/frs_cluster.R` at 0.52.0, `parameters_fresh.csv`, `parameters_habitat_method.csv`, `working_setn.crossings`); the provenance claims against `git log` and against `pick_groups.sql` run read-only on the same fwapg.
- Re-ran a copy of HEAD's `lifts.R` for SETN (scratch `zzrev_lift_setn`, output to the scratchpad): its SETN rows equal the committed `lifts.csv` byte for byte. Then classified the 601 lift-added SETN positions against that schema (query: scratchpad `rev/classify.sql`): 340 add a start (each start matched by exactly one position), 261 add none, of which 257 lie within 1 m of an FWA segment start (182 exactly on one) and 4 within 1 m of another cut; 0 unexplained. Schema dropped; `zz415_*` and `working_*` untouched; tree clean.
- `lifts.csv` from `36750888` (`lifts.R` at `234425e8`) against HEAD's: every shared column equal after the `cuts_` to `positions_` rename, so "every run of it gave the same positions and km" holds.
- `pick_groups.sql` today returns SETN, MORK, COTR, LFRA, BULK, … (also recorded in `findings.md` line 15).
- Along the Fraser main stem (`wscode` 100): SETN at 272 to 338 km, COTR 647 to 751, MORK 890 to 1,190.

## Enumeration

H = holds; F = finding below.

| where | claim | source | verdict |
|---|---|---|---|
| research:3 | builds at `6bf9ca06` (0.78.0), fresh 0.52.0, m4 | builds.csv; `hostname` | H |
| research:3 | `lifts.csv` written by `lifts.R` as of `ac52e150`, `R/` unchanged since builds | git log (`lifts.R` last changed ac52e150; no `R/`, `inst/`, DESCRIPTION commit since 6bf9ca06); reproduced | H |
| research:5 | `default` also cuts at "road crossings" | `working_setn.crossings`: 7,962 modelled, 43 PSCIS, 22 CABD dams | F4 |
| research:9 | built from one clean commit | builds.csv link_dirty FALSE, one sha | H |
| research:9 | the four are "the top of `pick_groups.sql`" | pick_groups.sql: top four SETN, MORK, COTR, LFRA; BULK 5th | F2 |
| research:9 | all four on `cw` | parameters_habitat_method.csv | H |
| research:9 | every check in `proof.R` passed | status.tsv pass yes; CSVs written | H |
| research:11-16 | segments, km, cuts matched per group | segments.csv, superset.csv | H (all 12 cells) |
| research:18 | keeps 77 to 90 % of segments | 76.6, 89.8, 88.3, 85.4 % | H |
| research:18 | 19,656 of BULK's 26,131 cuts are FWA ends; "most" | breaks_census (all four groups majority FWA) | H |
| research:19 | accessible km same for every species | access_km: max abs diff 0.002 km | H |
| research:19 | access_differences holds 10 pieces of 1 m | 10 rows, all len 1 | H |
| research:20 | gradient median 0, largest 0.022 (SETN), ≥ 99.99 % km within 0.01 | gradient.csv (SETN 99.9998 %) | H |
| research:21 | 2.8 to 6.6 min default, 3.0 to 6.5 minimal | status.tsv 2.75–6.55, 2.95–6.52 | H |
| research:25 | code 2 grows "above each record" … "more of the stream below it reads 2" | definition (2 when a record lies at m ≥ start + 1) | F3 |
| research:25 | 0 to 8.5 % per group and species; most BULK CO 628→681, COTR BT 663→698 | access_km: 0 to 8.45 %; top two are those | H |
| research:25 | accessible km (1 + 2) do not move | access_km ≤ 0.002 km | H |
| research:27 | predicate km about the same; connectivity drops rearing "with no spawning within 10 km" | fresh `.frs_cluster_both()`; parameters_fresh | F5 |
| research:31-35 | rearing table (20 cells) | connectivity.csv | F1 (MORK CH dropped, full: 200.45, written 201); other 19 H |
| research:37 | spawning moves under 1 % except MORK SK 28.2→28.6 | connectivity.csv: max other 0.94 % (SETN SK) | H |
| research:39 | overlay 53/291 (11), 22/454 (0), 19/333 (0), 8/198 (0) | overlay.csv | H |
| research:43-45 | anthropogenic loses 370 to 861; pscis 0 to 287; SETN dam_dnstr_ind +659 | crossing_fields.csv | H |
| research:47 | proof README says what each field means | README lines 49-51 | H |
| research:49 | start-window records 2,160→426 BULK; about half → a sixth or less; median segment 1.1 to 1.7× | placement.csv: 48–58 % → 10.1–16.6 %; ratios 1.14–1.70 | H |
| research:53 | two controls passed in every group | lifts.csv has all four groups (script stops otherwise); reproduced SETN | H |
| research:53 | control 2 fires when told no position moved (29 starts in COTR) | no run record; but with an empty moved-position set the first direction's count is `starts_added_by_lifts` = 29 (lifts.csv) | H by derivation |
| research:55 | a moved position cuts only where no cut is there: FWA start or another cut within 1 m | SETN classification: 0 unexplained | H |
| research:57-62 | lifts table (40 cells) | lifts.csv ALL rows, lifts_obs.csv | H |
| research:64 | only BT's observation lifts move positions | lifts.csv obs_lifts 0 for every other species | H |
| research:64 | BT lifts on one record; salmon/steelhead five since 1990 | parameters_fresh.csv | H |
| research:64 | salmon/steelhead overrides are known-habitat and control lifts; RB's are a paused species | working_* barrier_overrides; lift_n 0 for them | H |
| research:65 | SETN 6 removed, 601 added, 592 on lines with none | lifts.csv SETN ALL | H |
| research:65 | 340 added, 5 removed, net 335 | lifts.csv; 72,354 − 72,019 | H |
| research:65 | of the 261 that add no start, 257 on an FWA start and 4 within 1 m of another cut | no committed producer (only `review-pr2-round2.md`); reproduced here | F6 |
| research:66 | 0 to 0.9 % of records; KOTL 33 of 1,473 | lifts_obs.csv (0, 0.17, 0.74, 0.90 %); species_paused.md:24 | H |
| research:72 | no group has a dam below it in the scratch schema | recompute rows all exit 0 `yes`; downstream groups Fraser main stem, no dam | H |
| README:3 | 6bf9ca06, 0.78.0, fresh 0.52.0, every check passed | builds.csv, status.tsv | H |
| README:3 | "the top four of `pick_groups.sql` by combined rank" | pick_groups.sql: BULK is 5th, LFRA 4th not built | F2 |
| README:3 | "built downstream-first in that order" | status.tsv order BULK, SETN, MORK, COTR; MORK drains through COTR | F2 |
| README:3 | `lifts.R` committed before the builds | 6bf9ca06 commit 00:16 < BULK build 07:21Z (00:21 PDT) | H |
| README:3 | CSVs from `lifts.R` as of `ac52e150`; every run gave the same positions and km | git; old vs new lifts.csv equal | H |
| README:25 | lifts.R stops unless control 1 and control 2 | lifts.R lines 168-178, 230-239 | H |
| README:33 | `parent_<wsg>.csv.gz` "11.8 MB raw" | raw sizes 2.44, 4.74, 3.04, 1.62 MB; 11.8 is the four together | F7 |
| RUNBOOK:892 | superset within 1 m, same accessible km, same length-weighted gradient | superset, access_km, gradient | H |
| RUNBOOK:892 | rearing moves "(the connectivity pass drops less)" | connectivity.csv | H |
| RUNBOOK:892 | lifts move 0 to 1.2 % of km | 0.004, 0.46, 0.54, 1.19 % | H |
| CLAUDE.md | proof run at 0.78.0, every check passed; parent attributes #444 | builds.csv; #444 exists | H |
| CLAUDE.md | overlay BULK 53 of 291 km | overlay.csv | H |
| CLAUDE.md | BULK chinook rearing 2,101 to 2,205 | connectivity.csv | H |
| #444 | every minimal cut has a full cut within 1 m; straddle at most about 1 m | superset.csv (max 1) | H |
| #444 | parent gz is one row per full segment | rows 42,458 / 80,538 / 51,930 / 28,473 = n_full | H |
| #444 | gradient median 0, ≥ 99.99 % within 0.01 | gradient.csv | H |
| #444 | accessible km do not move | access_km | H |
| #444 | COTR CH rearing 1,322 to 1,419 | connectivity.csv | H |
| #444 | only BT lifts moved; 0 to 1.2 % km; 0 to 0.9 % records; median shift 0.007 to 0.073 | lifts.csv, lifts_obs.csv | H |
| lifts.R:15 (comment) | "a position on an FWA segment's start adds no segment" as the reason positions are not cuts | SETN: 4 of 261 are the 1 m skip | F8 |

## Findings

- **[severity: bug]** research/minimal_network.md:34 — the rearing table's MORK CH "dropped by connectivity, full" is 201; `connectivity.csv` gives `km_dropped` 200.45 (and predicate − rearing 2,668.64 − 2,468.18 = 200.45), so it rounds to 200. The other 19 cells of the table round correctly. Round 2 reported "the rearing table" checked.
  - **Rule:** code-check.md "One fact derived twice" (a published number has two derivations, the value and its printed form)

- **[severity: bug]** data-raw/logs/minimal_breaks_415/README.md:3 and research/minimal_network.md:9 — the group selection and build order are misstated.
  - "The groups are the top four of `pick_groups.sql` by combined rank" / "the top of `pick_groups.sql`": the query returns SETN, MORK, COTR, LFRA, BULK (run today read-only; the same list is in `planning/active/findings.md` line 15). BULK is fifth and LFRA, fourth, was not built. The picks were the README's own rule, "BULK plus two or three" groups, i.e. BULK plus the top three, which the status should say (and why LFRA was not taken, if there was a reason).
  - "built downstream-first in that order": `status.tsv` built BULK, SETN, MORK, COTR. On the Fraser main stem SETN sits at 272 to 338 km, COTR at 647 to 751 and MORK at 890 to 1,190, so MORK drains through COTR and was modelled before it. The recompute ran after all four builds on both networks (`builds.csv`), so the compared values are not affected, but the stated order is not the one run, and the README's own run decision required downstream-first.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a provenance or scope claim restated, never executed)

- **[severity: bug]** research/minimal_network.md:25 — "With no cut at the record, more of the stream below it reads 2" points the wrong way. A segment reads 2 when a record lies above its start (the sentence before says so); with a cut at a species' top record the segment starting there reads 1, and without that cut the segment holding the record starts below it and reads 2 up to its next cut. So the stretch that turns 1 → 2 lies above the record, which is what the bold lead says ("a segment's length above each record"); the stream below the record already read 2.
  - **Rule:** none (agent-operations.md §3, "A relative descriptor is meaningless without its anchor")

- **[severity: fragile]** research/minimal_network.md:5 — "`default` also cuts at … road crossings": the crossings break source is every row of `<schema>.crossings`, which holds CABD dams too (SETN: 22 dams beside 7,962 modelled and 43 PSCIS crossings). The crossing-fields paragraph (lines 41-45) explains `dam_dnstr_ind` through "no cut falls at a crossing", which holds only because dams are among the crossings the minimal network does not cut at; "road crossings" names a narrower set than the code's.
  - **Rule:** code-check.md "A proxy is not the property" (a sentence describing a set by its best-known member)

- **[severity: fragile]** research/minimal_network.md:27 — "the connectivity pass, which drops rearing with no spawning within 10 km" is not fresh's rule. Under `cluster_direction = both` (`default`'s parameters_fresh for BT, CH, CO, SK, ST), `.frs_cluster_both()` keeps a rearing cluster with spawning *anywhere* upstream (no distance), or with spawning downstream within 10 km along a path with no segment steeper than `cluster_bridge_gradient` 0.05 (fresh 0.52.0 `R/frs_cluster.R`, the three-phase roxygen). The compression drops the gradient bridge, which is a per-segment test and the likeliest reason coarser segments "disconnect less" (a longer segment averages a steep step away) — the very effect the section explains.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression that drops the condition that made the claim true)

- **[severity: fragile]** research/minimal_network.md:65 — "of the 261 that add no start, 257 fall on an FWA segment's start and 4 within 1 m of another cut" has no committed producer: no CSV column and no script in `minimal_breaks_415/` computes it; its only record is `planning/active/review-pr2-round2.md`, and the counterfactual schema it was measured on is dropped by `lifts.R`. Reproduced here and it holds (340 / 257 / 4, 0 unexplained, each added start matched by exactly one position), with one refinement: 182 of the 257 lie exactly on an FWA start and 75 within 1 m of one. Either add the classification to `lifts.R`/`lifts.csv` or cite where it was measured.
  - **Rule:** code-check.md "Written data outlives the fix" / "The probe is broken before the world is" (a number with no producer cannot be re-derived)

- **[severity: fragile]** data-raw/logs/minimal_breaks_415/README.md:33 — the table row for `parent_<wsg>.csv.gz` says "11.8 MB raw", which reads as per file; the four files are 2.44 (BULK), 4.74 (SETN), 3.04 (MORK) and 1.62 MB (COTR) raw, 11.8 MB together.
  - **Rule:** code-check.md "One fact derived twice" (one name carrying different populations)

- **[severity: fragile]** data-raw/logs/minimal_breaks_415/lifts.R:15-16 — the header comment still gives one reason ("a position on an FWA segment's start adds no segment") for why a position is not a cut. Round 2's fix added the 1 m skip to the write-up but not to the script's own comment; SETN has 4 such positions.
  - **Rule:** code-check.md "Written data outlives the fix" (enumerate every artifact quoting a corrected fact)
