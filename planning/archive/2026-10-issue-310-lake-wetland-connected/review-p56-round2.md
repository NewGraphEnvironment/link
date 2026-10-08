# Review p56, round 2 (#310 measurement logs + docs)

## Clean

No real issues found. What was checked:

### The rewritten README claims hold against the B snapshots
- **Wetland "ha, no km" split** (README:68-70). Polygons with `wetland_rearing AND NOT any rearing`, split by the edge types of their lines and by `accessible`:
  - NATR BT 808: 515 hold 1050/1150 lines, and all 515 have such a line accessible. 12 hold only 1000/1100, all accessible. 281 are construction-only.
  - ADMS: BT 28 (14 wetland-flow / 14 construction-only), CH 19 (10 / 9), CO 26 (7 / 19), RB 13 (0 / 13). NATR RB 273, all construction-only.
  - The bucket is gated on access (0 bucket lines inaccessible in any species). The 1050/1150 lines in those polygons are accessible, in polygons of at least 1 ha (the bucket uses the same floor), and admitted by the `thresholds: false` W rule. So "admitted lines that `cluster_rearing` drops" is the right reading. The README omits ADMS CO's split (7 / 19), but "different proportions per species" does not claim otherwise.
- **CO on ADMS** (README:52): gains 6 wetlands (max 0.486 ha, 2.02 ha in total) and loses 1 (3.24 ha), so the net is −1.2 ha against 1,106 → 1,105. A's CO floors were 0.5 ha for wetlands and 2.0 ha for lakes (`865bd04` rules.yaml), which fits "under 2 ha" / "under 0.5 ha". The lost wetland can only be the connection test: same segmentation, same access, and B's floor is lower.
- **Species lists** (README:10): they match summary.csv.
- **GR's 160 wetland "km, no ha"** (README:71): GR's rearing lines in wetland polygons are only 1000 (369 segments, 76 km) and 1100 (6 segments, 2 km), so it is the stream rule. GR has no W rule.
- **Adams Lake ratios**: 211.6 / 62.8 = 3.4× ("roughly three times"). It is 84–90 % of each species' ADMS lake km ("about 85 %"). Without it, CH would be +22 % and CO +15 % against bcfp, so "this is what puts ADMS CH and CO past +50 %" holds.
- **The CLAUDE.md / research / RUNBOOK bullets**:
  - "237–525 km" and "NATR BT wetland −2 %" (17,128 → 16,772 = −2.08 %) check out.
  - `requires_connected: spawning` is stamped twice for BT/CH/CO/RB/ST/WCT and once for GR (13 in all). It is absent for SK/KO.
  - CT/DV have no rules block.
  - The validator's lake/wetland predicates are fresh's membership + area predicates, with no connection test (`lnk_habitat_validate.R:974`), so the `post_predicate` wording is accurate.
  - fresh `v0.39.0` resolves to `e247ca1`.
  - A's BT L rule is on 1000/1100 only.
  - 865bd04 is an ancestor of HEAD.
  - rollup_check `parts_minus_total` ≤ 0.01.

### run.R dirty flag
- `git -C <repo> status --porcelain -- R inst`: under `-C`, the pathspecs resolve against the repo root. Untracked files are listed too. `inst` covers the bundle that `lnk_config("default")` resolves under `load_all`. None of the arguments carries a shell-special character, so `system2`'s raw pasting is safe.
- If git fails, the dirty test would read FALSE. But `rev-parse` on the line above would then return `character(0)`, and `data.frame()` stops on the length mismatch, so the run cannot finish with a silent FALSE.
- DESCRIPTION is not in the pathspec, but nothing in this measurement depends on an uncommitted DESCRIPTION edit. Not an issue.

### Host identity
runs.csv carries schema and snapshot names, SHAs, versions, the config hash and minutes. The stamps carry the AOI, a timestamp in PDT, versions, a provenance count and the bcfishobs row count. Neither holds a path, hostname, user or address.
- Minor, and not wrong: each `stamp_<run>.txt` holds the stamp for the first AOI only (ADMS), because of the `file.exists` guard. The stamp also does not carry the link SHA. runs.csv has both per WSG.

### summarise.R bcfp merge
`fresh.streams_vw_bcfp`'s `rearing\_%` columns are `rearing_bt|ch|co|sk|st|wct`. `toupper(sub("^rearing_", ""))` gives BT/CH/CO/SK/ST/WCT, the same codes link uses, so the merge has no silent mismatch. RB/GR/KO come out NA ("—") because bcfp has no model for them, which is the right reason.
- The `LIKE 'rearing\_%'` escape works under `standard_conforming_strings`.
- The table is unique per segment in ADMS (15,781) and NATR (32,335).
- ADMS BT 674.2 km reproduces.
- A missing column would give a zero-row rbind, and the merge would then error rather than pass.

planning/active/review-p56-round2.md
