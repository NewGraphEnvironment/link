# Code-check round 3 — #259 (branch diff 998c986a...HEAD)

## Checklist read

- code-check.md.index: in full. code-check.md: the prose of all 14 H3 under `## Mechanisms`
  (tables skipped), in full. No other code-check.md sections read.
- code-check-r.md.index: in full. code-check-r.md full sections read: "Postgres row order is never
  fixed…", "`ifelse()` with an all-NA test…", "`read.delim()` quotes by default…", "`$` on a list
  partial-matches…" (4 read; the other ~130 headings not read, judged not to touch this diff).
- code-check-shell.md.index: in full. No full sections read (the shell change is one awk test on
  `$2 == "model"` plus echo lines; "grep -c" / "awk ==" headings judged not to apply).
- code-check-spatial.md.index: first ~3,000 bytes in full, headings only for the rest; no full
  sections read (no spatial code in the diff).

## The mechanism behind rounds 1-2

Every earlier finding is one shape: **a host's identity, or a host's speed, is read in two places
from two sources that agree only by convention, and the plan file does not carry enough to make the
second read check the first.** Round 1 (role key vs alias; packed speed as the damping base; log.host
vs --host-names) and round 2 (correction measured at packed speed; cloud speeds unequal; skip by
host key) were each a pair of keys or a pair of speeds that coincide on the default path and diverge
off it. The fixes moved the packed speed out of the learning by recording it in the plan
(`speed`) and re-projecting at `old`. The one speed-shaped input the plan still does not record is
the normalization factor each weight carries.

## Findings

- **[severity: bug]** data-raw/study_area_buckets.R:328 (`weights_normalize(..., speed_state)`),
  data-raw/study_area_packing.R:165-166 (`projected_old`), data-raw/host_speeds_calibrate.R
  (no normalization input) — **the plan's weights embed the learned state read at PACK time, and the
  calibrator re-projects them against the state read at CALIBRATE time, assuming the two are the same
  file contents.** `projected_old = Σ weight / old` is only "weight at the calibrating state" if the
  minutes were normalized with that same state. The plan records the packed speed (so --host-speeds
  is undone) but not the factor each weight was multiplied by, so the calibrator cannot undo a
  normalization made with another state. Reachable on the documented workflow: the calibrator is run
  by hand after a run, so packing run N+1 before calibrating run N (or packing from a worktree whose
  committed `host_speeds.tsv` predates a calibration, or with `--speeds-state=` / another path while
  the calibrator reads the default) gives run N+1 weights at S_old and an `old` at S_new.
  Because most groups are self-measured, each leg then reads ratio ≈ drift × S_new/S_old, and the
  update pulls the factor back toward S_old. Measured by sourcing study_area_packing.R (240
  lognormal groups, truth cloud 0.7 of m1, scratchpad r3/sim.R):
  - state already at truth (cloud 0.7), packed and calibrated on it: stays 0.700;
    packed on the older equal state, calibrated on the true state: **moves off truth to 0.715**.
  - state cloud 0.9, consistent: 0.837 (toward 0.7); packed on equal state (or `--speeds-state=`
    empty): 0.852 — about a quarter of the step is undone.
  So the docs' claim that "the speed a run was packed at (`--host-speeds`, **an older state**)
  decides only which groups a host got, never what is learned" is false for the older-state half
  (RUNBOOK "The arithmetic" bullet; study_area_packing.R speeds_calibrate header; CLAUDE.md Status
  "Each leg is re-projected at the stored factor … (`--host-speeds`, an older state)"). The
  --host-speeds half holds (normalization reads the state, not the CLI speeds), and the existing test
  "the speed a run was packed at decides routing…" passes because it builds `projected` directly and
  never goes through normalization; `pk_simulate` packs and calibrates on one state, so it cannot
  reach this either.
  Fix options: (a) write the per-group normalization factor (and raw minutes, or the state's
  `name/factor` snapshot) into the plan, and have the calibrator re-normalize each weight at the
  calibrating state before re-projecting; or (b) write the state's identity (e.g. the
  `source_run_uid`/factor of every row, or a digest) into the plan and refuse when the state the
  calibrator reads differs. (a) keeps late calibration usable; (b) is smaller.

- **[severity: fragile]** data-raw/study_area_buckets.R:145 —
  `Sys.getenv("LNK_HOST_ALIAS", Sys.info()[["nodename"]])` is a second derivation of `.lnk_host()`
  (R/utils.R:251) that disagrees when `LNK_HOST_ALIAS` is set but empty (the usual way to "unset" it
  in an Renviron): `.lnk_host()` falls back to the node name, while `Sys.getenv(x, default)` returns
  `""` (the default applies only when unset), so the default dispatcher name is `""` and
  `host_names_check()` stops the packer with "no … blank". Loud, not silent, but it refuses a valid
  configuration and the message points at --host-names rather than the variable. Use the same
  `nzchar()` fallback as `.lnk_host()`.

## Enumeration: every place the mechanism reaches

Host identity:
- driver role key — `phases.tsv` host (`phase_begin/phase_end model|account dispatcher|$WS`,
  study_area_run.sh:1893-1995, study_area_legs.sh:159), `run_wsgs.tsv` host (finish.sh:94-98), plan
  `host_key` (buckets `host_key()`): consistent when `--cy-workspaces=job1..N` in order and workers
  are `worker1..N` (driver keys them so). Any other cloud workspace names or order make the plan's
  `jobN` differ from the run's key; the calibrator's per-host group check refuses it — loud, no
  silent path. `--skip=<host key>` uses the plan key, which the same check ties to the run's.
- plan `name` ↔ state `name` ↔ history `name`: one source (`--host-names`), checked by
  `host_names_check()` on both sides; consistent.
- `log.host` → `host_class()` → state name (normalization): consistent for cloud (`cypher-*`, `jobN`)
  and for the default dispatcher name (same alias/nodename source, domain stripped on both), except
  the empty-alias edge above. An explicit `--host-names` alias that differs from the machine's
  `LNK_HOST_ALIAS`/node name gets the median (accepted, and printed).
- `account` row keyed by the same role key as `model`; consistent.

Speeds:
- packed (plan `speed`): recorded, re-projected out at `old`; per-name uniqueness enforced in the
  packer and the calibrator; consistent.
- stored/old (calibrate-time state, median for a missing name, 1 with none): used for
  `projected_old`, `run_ratio`, damping and clamp; consistent with each other.
- normalization (pack-time state): **not recorded — finding 1.**
- observed / new / clamp: from `old`; consistent.
- `run_ratio`: over every non-skipped leg at `old`, role keys included; consistent.

Doc numbers against fit.md (all checked): 3.6 / 28.9 points stalls out and 16.4 / 28.5 as logged
(equal-speed rows) ✓; 12-20 % over (from −11…−17 % short) ✓; 13-16 % drift, m1 1.130, cloud 1.159 ✓;
10 of 239 moved ✓; cloud 0.964 vs drift ratio 0.976 ✓; m1→cloud 1.436 (n 7), cloud→m1 0.941 (n 3) ✓;
3.4 / 228, 6.0 / 214, cloud 1.04 ✓; "eight times" (28.9 / 3.6 = 8.0) ✓; job3 −38 %, job2 +5 % ✓;
the per-group-means simulation ends at 0.140 after 20 runs (doc "0.13 to 0.15") ✓; legs converge to
0.706 ✓. The only claim that fails execution is the "an older state" clause in finding 1.
