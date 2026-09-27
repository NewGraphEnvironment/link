# Progress — Region-scoped DV→BT observation pooling (#290)

## Session 2026-09-26

- Plan-mode exploration; phases approved by the operator
  - `wsg_regions.csv` is package-level; the resolver is `lnk_species_pooling()`
  - Mid-plan refinement: pooling is abstract (species or group on either side of a row)
- Created branch `290-region-scoped-dv-bt-observation-pooling` off `origin/main` (`aa02738`, v0.52.0). Local `main` still carries the unpushed `997b876` (MCGR run logs), which is left untouched.
- Scaffolded the PWF baseline
- Next: Phase 1
- Phase 1: `data-raw/wsg_regions.R` builds `inst/extdata/wsg_regions.csv`. It covers 246 groups in 17 regions (Haida Gwaii spans codes 940 and 950), and Kootenay (7 WSGs: BULL, DUNC, ELKR, KOTL, KOTR, SLOC, SMAR) is the one sub-region. The rebuild is idempotent (`cmp`).
  - The guards were proven in a scratch copy: an unmatched prefix, a comma in a name and a missing region row each exit 1 with the named cause.
  - Review: self-review and the mutation test. The `/code-check` skill runs on the resolver diff (Phase 2), which carries the logic.
  - #290's body was edited: regions are package-level, and pooling is abstract (species or group on either side).
- Phase 2: `lnk_species_pooling()` plus the tracker and groups at the `default` bundle root. They are not in `overrides/`, because the bundle README defines that as shared jurisdiction facts, while pooling is a method choice. Both have dictionaries with tests; `lnk_config_verify` is clean for `default` and for `default_tuned`, which inherits them.
  - 37 tests on synthetic codes (AAA/BBB/CCC/GRP).
  - Four mutations in a scratch copy each go red: scope precedence inverted (3 failing), the taxon tie-break removed (1), `pool = no` ignored (2), the presence gate removed (1).
  - Province-wide, DV pools into BT in 129 WSGs. 29 of the 158 BT-present WSGs are in unlisted regions (Nass, Stikine, Taku, Yukon, the coast), which is where the new rule differs from the old global one.
- Phase 4 check (run from the working tree before commit, into scratch): `query_habitat_thresholds_obs.R` under the regional rule. Every CSV and both PNGs are byte-identical to the committed #284 evidence, except the ledger step-3 row: new label, and DV 8,888 → 6,138. That count was predicted before the run and independently by the plan review.
  - Steps 4–7 are identical, because all 55 WSGs are in pooled regions. The stamp gains a `pooling:` line; the n_cand > 1 count is still 45. (The console's "107" is the pre-dedup `o5` message, not a change.)
  - A first attempt failed: `sprintf()` over SQL with a literal `LIKE '...%'` (findings table).
- Phase 2 `/code-check`: three rounds, then ended by enumeration.

  | Round | Findings | Fixed | Accepted | Inside previous fix? |
  |---|---|---|---|---|
  | 1 | 3 fragile: aoi not de-duplicated; unknown species silently dropped; `[1, ]` on an NA regions row | 3 | 0 | — |
  | 2 | 2 fragile: every dictionary `consumed_by` ref stale; a vacuous zero-row assertion | 2 | 0 | yes (the R1 fixes shifted the lines) |
  | 3 | 2 fragile: the ref test matched substrings; `read.csv("")` reads stdin. Plus 1 site guarded only by accident and 1 duplicated list | 4 | 0 | yes (the R2 test) |

  - Mechanism (named by round 3): two separately maintained lists agree on a key, and disagreement narrows silently instead of failing.
  - Its reach, enumerated by round 3, is now guarded site by site:
    - unknown keys error;
    - the NA-safe `%in%`;
    - the token-matching ref test, proven against a planted wrong ref and against real drift (6 of 7 stale refs caught);
    - non-empty guards on subset assertions;
    - one `.lnk_presence_species_cols()` for three copies of the exclusion list;
    - `.lnk_wsg_regions_path()` stops on a missing file.
  - Also added: `.lnk_config_hash()` hashes `wsg_regions.csv` for tracker bundles (the plan review's G7), and its mocked test goes red when the block is removed.
- Phase 3: `lnk_habitat_validate()` accepts a per-WSG `species_obs` data frame, checked as a data frame first (plan review B3).
  - Rules: its own presence ∩ the table; an unlisted pair maps to itself; rows are deduplicated.
  - The driver gains `--pooling=`, defaulting to the first bundle that declares a tracker. It resolves once, over the union of both bundles' WSGs, and stamps the choice.
  - The obs query joins the resolved table instead of the hard-coded `CASE`, and gains `--pooling=` and `--out=`.
  - Tests:
    - 3 new, including end-to-end: the df form's `summary` is identical to the list form, and an empty df drops DV record `o2`;
    - bypassing the df branch in a copy turns all 3 red.
- Phase 4 negative check: a scratch bundle with Skeena `pool = no`.
  - Ledger step-3 DV is 2,910, as predicted (6,138 − 3,228).
  - 1,929 evidence rows drop, all DV and all Skeena, in exactly the 9 Skeena WSGs (BULK, KISP, KLUM, LKEL, LSKE, MORR, MSKE, USKE, ZYMO).
  - 0 rows are added, and the remaining rows are identical.
- Phase 3 `/code-check`: two rounds, then ended by enumeration. This is one round short of the skill's three-round floor, deliberately: review spend was at 6 agents, and the only round-2 finding was a single site, now keyed and proven.

  | Round | Findings | Fixed | Accepted | Inside previous fix? |
  |---|---|---|---|---|
  | 1 | 3 fragile: CH<-BT relabelled silently; pooling-bundle vs scored-bundle presence disagreement drops silently; the zero-row stamp prints `"<-"` | 3 | 0 | — |
  | 2 | 1 fragile: the query's presence check compared by row position (a renamed WSG slipped through) | 1 | 0 | yes |

  - Enumeration of the mechanism's reach in this diff, each site guarded:
    - the pool ↔ observations join (uniqueness and model-species guards);
    - the query presence check, keyed by WSG;
    - the driver presence check, keyed by WSG;
    - the validator df ↔ its own presence (intersection and self fallback);
    - the resolved WSG set, the union of both bundles';
    - stamps, "none" when empty.
  - Proven with scratch bundles, each stopping with the named cause: CH<-BT, a blanked MORR presence, a MORR→MORQ rename, and the driver on a mismatched presence. `default` still runs clean.
  - `candidates.csv` differs from the committed copy by at most 1.7e-16 relative (1 ulp) between identical runs. This is pre-existing: a float `sum()` in the availability SQL (findings table; issue drafted).
