# Code-check round 1 — data-raw/query_width_mad_equivalent.R (#307)

## Clean

No issues found.

What was checked (not findings):
- `inherits_size()` and `floor_signif2()` are byte-identical to the helpers in
  `data-raw/query_habitat_thresholds_mad.R:321-335`. Run against the current
  `default` rules.yaml, they convert BT/GR/RB spawn+rear and KO spawn only (KO rear is
  a single `waterbody_type: L` rule), as the header says.
- `floor_signif2` on the #302 medians gives 0.021 (1.5 m), 0.041 (2 m), 0.20 (4 m).
- BETWEEN bin edges: `w_bin ± 0.1` in double precision rounds to the same doubles as
  the literals 1.4/1.6, 1.9/2.1, 3.9/4.1, so edge inclusion matches the ad-hoc query. The
  1.5 and 2.0 bins do not overlap.
- An empty bin cannot pass silently: the inner join drops it and `setequal()` stops.
  `match()` on 1.5/2/4 against the DB doubles is exact.
- `sprintf("%s")` and `as.integer()` on RPostgres integer64 counts both give the right
  values (probed).
- The `link_dirty` pathspec leaves out `--out` (data-raw/logs), so the run cannot mark
  its own tree dirty (#257). It reports dirty while the script is only staged, which is
  correct.
- Reachable only with a `--species` list that has no stream-rule stage: `conv` is NULL, and
  `paste0("(", NULL, ...)` builds `VALUES (::double precision)`. Postgres then raises a
  syntax error. That fails loudly, not silently, and the default species cannot reach it,
  so it is not reported as a finding.
