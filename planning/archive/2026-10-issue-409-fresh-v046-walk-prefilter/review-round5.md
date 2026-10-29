# Code-check round 5 (termination) — #409, round 4's fix (158d4144)

Scope: the added lines of `git diff e7349ecc 158d4144` in CLAUDE.md, RUNBOOK.md,
data-raw/logs/prefilter_409/README.md and research/recompute_cost.md (planning/ files are
the review record, not claims). Every claim re-derived from its producer, read-only.

## Enumeration

`rc/` = `data-raw/logs/prefilter_409/recompute/`; `f272/` = `~/Projects/repo/fresh/data-raw/logs/network_features_272/`.

| # | where | claim | producer and value | verdict |
|---|---|---|---|---|
| 1 | CLAUDE.md:21 | under 0.46.0 walks are 41 % (SALR) to 87 % (SETN) of each version's fastest run | rc/steps_*: fastest 0.46.0 runs SALR a1 9.61/23.20 = 41.4 %, LKEL a2 52.9, CHWK a1 62.0, LSKE a1 65.9, SETN a1 86.8 | SUPPORTED |
| 2 | CLAUDE.md:21 | against 66 to 96 % under 0.44.0 (same basis) | fastest 0.44.0 runs SALR b2 65.8 %, LKEL b2 79.4, LSKE b2 89.3, SETN b1 90.0, CHWK b2 95.9 | SUPPORTED |
| 3 | CLAUDE.md:21 | natural walks summed per group gain 4.7× to 17× (SETN 1.8×) | rc/summary_walks.csv (round 4 #20; unchanged text) | SUPPORTED |
| 4 | CLAUDE.md:21 | #261's 6.3× to 24.6× server-side | recompute_cost_261/README (unchanged) | SUPPORTED |
| 5 | CLAUDE.md:22 | PSCIS and dam walks slower by 1.0–1.3 s (SALR, LKEL, CHWK), 2.0–2.4 (LSKE), 3.5–4.2 (SETN) | summary_walks.csv s_a − s_b: 1.03–1.33, 2.04/2.38, 3.47/4.19 | SUPPORTED |
| 6 | CLAUDE.md:22 | a group makes 5 to 11 walk calls | rc/walks_*_a1 rows: SALR 5, LKEL 10, CHWK/LSKE/SETN 11 | SUPPORTED |
| 7 | CLAUDE.md:22, README:113, research:99-100 | what costs the rise is not measured | — | SUPPORTED |
| 8 | CLAUDE.md:22, research:100 | fresh's temp-table build is 0.07 to 0.7 s | f272/walks.tsv `ddl_seconds`: LKEL 0.072–0.078, SALR 0.101–0.109, CHWK 0.135–0.146, LSKE 0.665–0.723 | SUPPORTED |
| 9 | CLAUDE.md:22, README:114-115, research:100-101 | on a province-wide `fresh_default` | f272/README: "`segments = fresh_default.streams` (province-wide, 11.3 M rows)" | SUPPORTED |
| 10 | CLAUDE.md:22, README:115, research:101 | with no other client active | f272/README ("no other client backend active"); walks.tsv `others_active` 0 on 56 of 56 rows | SUPPORTED |
| 11 | CLAUDE.md:22, README:116, research:102 | less than the rise | 0.07–0.15 vs rises ≥ 1.03 (three groups); 0.7 vs 2.04–2.38 (LSKE); max 0.72 below SETN's 3.47 | SUPPORTED |
| 12 | CLAUDE.md:22 | #394 makes fewer calls | #394 (round 4 #30; unchanged) | SUPPORTED |
| 13 | README:114 | 0.07 to 0.15 s in SALR, LKEL and CHWK; 0.7 s in LSKE | as #8 | SUPPORTED |
| 14 | CLAUDE.md:25 | rerun.R refuses on any other lock in `fresh_default` or more than one other active client | rerun.R:42 (`sch <- "fresh_default"`), :48-60 | SUPPORTED |
| 15 | CLAUDE.md:25 | does not refuse again | rerun.R: no REFUSE after :60 (a mid-run lock wait past `lock_timeout` 60 s, :46, would error the run, which is not a company check) | SUPPORTED |
| 16 | CLAUDE.md:25 | it samples clients at its end only to stamp them | rerun.R:179-194 (`busy_end`, written to `others_end`, no branch on it) | SUPPORTED |
| 17 | CLAUDE.md:25 | SETN's 0.46.0 run had another by then | rc/steps_SETN_a1.tsv `others_end` 1 | SUPPORTED |
| 18 | CLAUDE.md:25 (bold lead, unedited but now beside #16) | "`rerun.R` checks for company only at its start" | #16: it also samples active clients at its end | WIDER (see F1) |
| 19 | CLAUDE.md:25 | driver waits for five minutes of continuous quiet (`QUIET_S`) | rerun_all.sh:17 (`QUIET_S` default 300), :48-52 | SUPPORTED |
| 20 | RUNBOOK.md:1551-1552 | the recompute's cost was its downstream walks (#261) | #261: "the walks are the job" (CHWK 589.4 of 617.6 s, SALR 28.2 of 46.3); this record under 0.44.0: 66–96 % of fastest runs | SUPPORTED (attributed to #261) |
| 21 | RUNBOOK.md:1552-1553 | since fresh v0.45.0 they read only the features on the group's lines or downstream codes | fresh `.frs_walk_prefilter` (round 4 #1) | SUPPORTED |
| 22 | RUNBOOK.md:1553-1554 | under v0.46.0 they are 41 to 87 % of five groups' fastest runs (#409) | as #1 | SUPPORTED |
| 23 | README:64 | SETN a2's refusal log kept as `rerun_SETN_a2_refused1.log` | file present (298 B) | SUPPORTED |
| 24 | README:64-65 | the committed `rerun_all.sh` now keeps an earlier attempt's log | rerun_all.sh:54-57 (added df73195f) | SUPPORTED |
| 25 | README:65-66 | and exits 2 on a `RESUME` that matches no run | rerun_all.sh:40-43 clears RESUME on match; :67 exits 2 if still set (added e7349ecc) | SUPPORTED |
| 26 | README:66 | the copy waiting to run SETN's second pair was frozen before both changes | `scratchpad/rerun_all_frozen.sh` byte-identical to `7b206f64:…/rerun_all.sh` (neither change); copied 21:44 PDT, before df73195f (22:12) and e7349ecc (22:28); pid 11752 runs it with `RESUME=SETN:a2`; status.txt has no entry after 04:36:52Z, so it is still waiting | SUPPORTED |
| 27 | README:107-108 | b1 is the slowest total in each of the four complete groups | totals b1/b2/a1/a2: SALR 49.4/41.9/23.2/23.6, LKEL 125.4/111.4/52.0/46.5, LSKE 601.8/579.6/177.9/180.9, CHWK 1,010.0/686.0/74.7/75.2 | SUPPORTED |
| 28 | README:108 | "the four complete groups" = SALR, LKEL, LSKE, CHWK | status.txt (SETN has b1, a1 only) | SUPPORTED |

**Counts:** 28 claims; SUPPORTED 27, WIDER 1 (#18), UNSUPPORTED 0, WRONG 0.

## Round 4's six findings

| R4 | edit | resolved? |
|---|---|---|
| F1 (WRONG, "on m4") | CLAUDE.md:22, README:114-115, research:100-101 now say "a province-wide `fresh_default` with no other client active"; no host named; no remaining "m4" attached to the fresh timing (grep) | yes |
| F2 (RUNBOOK "Most …" beside 41 %) | "was its downstream walks (#261)", then the 41–87 % on its own basis | yes |
| F3 (CLAUDE.md basis) | "of each version's fastest run"; both ranges re-derive on that basis | yes |
| F4 ("first runs read colder") | replaced by a measured fact (#27) | yes (see note) |
| F5 ("does not look again") | body now "does not refuse again (it samples … only to stamp them)" | body yes; the bold lead still says "checks for company only at its start" (F1 below) |
| F6 ("the driver now keeps") | scoped to the committed script; the frozen copy named | yes |

No edited sentence contradicts another in its file: CLAUDE.md:16 and :21 both state "each version's fastest run"; README:92's heading and :118-119 ("of these runs") are on the same basis as :114; research:104-105 sits under :72's "each version's fastest run".

## Findings

- **[nit] CLAUDE.md:25 — the bold lead "`rerun.R` checks for company only at its start" now sits beside a body that says it also samples clients at its end.** That is round 4's F5 surviving in the lead the fix did not touch: the body was corrected from "does not look again" to "does not refuse again", but "checks … only at its start" makes the same claim the body now walks back. Say "`rerun.R` refuses on company only at its start:".

Note, not a finding: README:107-108's new parenthesis ("b1 is the slowest total in each of the four complete groups") is true, but it supports the sentence's claim about gate, mapping code and setup only loosely, since b1's extra time is mostly walks (CHWK b1 walks 979 s against b2 658). It no longer asserts a cause, which was the point of F4.

## Termination

One WIDER, a two-word clause in a bold lead that round 4's fix sat next to; every other added claim re-derives from its producer, and all six of round 4's findings are resolved in the sentences they named. Fixing the lead closes the record on this enumeration.
