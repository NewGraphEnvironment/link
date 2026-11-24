# Enumeration ending the code-check loop (link#479)

Round 3 found defects inside round 2's fix, so the loop ends on an enumeration of the
candidate set the mechanism implies, not on a quiet round.

**Mechanism** (round 3's naming): the branch changes a fact where it is written, and every
reader that kept its own copy derives it the old way. Three facts.

## A. Who holds a gradient position (#386)

Every reader of `barriers`, `barrier_overrides` or `barrier_override_evidence` by group
(`grep -rn` over `R/`, `data-raw/*.R|sh|sql`, 2026-11-24):

| reader | reads by | verdict |
|---|---|---|
| `lnk_barriers_unify()` gradient branch | owner / fallback holder | the writer |
| `lnk_pipeline_persist()` overrides, evidence | a natural row the group holds within 1 m | handled (round 0) |
| `barriers_<sp>_access` views, `lnk_pipeline_access()` | position, any group | handled: one holder suffices |
| `.lnk_pipeline_prep_minimal()` | the working, whole-line tables | handled: working lift equals the owner's |
| `lnk_wsg_downstream_check()` | dams on the path; line-rule groups holding rows; modelled groups absent from FWA | handled (rounds 2, 3) |
| `wsg_recompute_one.R` post-condition | the check, error mode, with the written-reason override | handled (round 3) |
| recompute scheduler / audit (`recompute_deps.R`) | line rule | handled: the line rule covers the owner |
| `lnk_export_groups.R` barrier holders, `lnk_downstream_files()` | groups holding rows | handled: a holder is the owner |
| `recompute_readers_check.R` | the check's status | handled |
| `study_area_verify.sql` | one holder per position, override beside own barrier | handled |
| `lnk_presence_measures.R`, presence check and map scripts | position, any group (`barriers_known` the group's own rows) | unaffected |
| `breaks_diff.R` | the group's own segments | unaffected |
| `schema_consolidate.R` | per group copy; evidence column both ways | handled (round 1) |

## B. What a lift-rule cell means (#236)

Every column the runner (`lnk_barrier_overrides()`) reads, against the reader
(`.lnk_lift_rules()`):

| column | reader | runner | verdict |
|---|---|---|---|
| `species_code` | upper-cased, must be in parameters_fresh | used as given | same value |
| `rule` | `^[A-Za-z0-9_.-]+$` | same grammar | handled (round 1) |
| `barrier_kinds` | `natural` only | not read | handled |
| `observation_species` | blank = own species, upper-cased | blank = own (round 1), upper-cased (enumeration) | handled |
| `observation_threshold` | positive whole number | `as.integer`, NA = 0 | handled |
| `observation_date_min` | blank = none, else must parse | blank = 1900-01-01, else must be a date (round 3) | handled |
| `observation_buffer_m` | number or blank (enumeration) | `as.numeric`, NA = 20 | handled |
| `observation_control_apply` | yes/no or TRUE/FALSE (round 3) | `.lnk_flag_true()` (round 3) | handled |

## C. Which crossings are barriers (#341)

Every `barrier_status` reader in `R/` and `data-raw/`: the four barrier sets read
`.lnk_sql_barrier_selected()`; the rest read the source's own status by design (the union and
the correction files that write it, `crossings_lookup`, classify's break labels, which never
block, and the remediation set). `pscis_assessment` rows are scoped to PSCIS (round 1). No
script calls a removed function.

Nothing sits above its source of truth in A, B or C after the round-3 fixes.
