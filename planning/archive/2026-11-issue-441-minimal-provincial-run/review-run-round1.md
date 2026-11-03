# Code check, branch 441-minimal-run, round 1

## Checklist read

- code-check.md: prose of the Mechanisms section, table rows skipped: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property" (in full), "A wrapper's exit is not the work" (in full); the other 10 mechanism headings by their index line only. Of "Rules that stand alone", "Documentation Staleness" by index line. About 38 headings not read in full.
- code-check-shell.md: "Empty arrays under `set -u` on bash 3.2", "`&` binds to the whole `&&` list, so assignments never reach the parent" (in full). The rest by index line only (about 75 not read in full).
- code-check-r.md, code-check-spatial.md: index only; the branch changes no R or spatial code (all headings not read in full).

## What was checked

- `launch.sh`: `set -uo pipefail`, empty `pre` array under `set -u` (safe on bash >= 4.4; the script names 5.1 and execs `$BASH`), `cd` guarded, `exec` passes the driver's exit through to the outer `echo DRIVER_EXIT=$?`. No defect found.
- Every number in the new `research/study_area_run.md` section, the RUNBOOK bullet, the CLAUDE.md Status block and the PWF entries against `phases.tsv`, `run.log`, `checks/`, `plan.tsv`, `buckets.md`, `host_speeds*.tsv`, #377's body, and the database (`fresh_default_minimal.log` / `log_recompute`: 241 rows each, one link sha `193cb8aa` 0.78.1 clean, one fresh sha `245c8d8d` 0.52.0; group minutes 690.2 summed, median 2.32, QUES 20.91 / MORK 12.76 / BULK 10.74 on job3 / job2 / job1; recompute 126.8 summed, median 0.41, HOMA 4.98, 21:51:33 to 00:15:29; 4,987,761 segments; tables 19.97e9 bytes; local `fwa_stream_networks_sp` reltuples 4,910,797 against an exact count of 4,907,441, so the reltuples explanation holds; history rows all 0.68.0 run `20261023_074321-24d85e8c`). Critical path 228.2, cloud host-hours 9.86, 29.4 and 12.3 min recompute tails, calibrator arithmetic: all match.
- Public-repo hygiene: no IPv4 or IPv6 address, tailnet address, `user@host` with a real host, token or key pattern in any file the branch adds or changes (droplets appear as `cypher@<host>`, the worker as `<worker1>`).

## Findings

- **[severity: fragile]** CLAUDE.md:21 (also RUNBOOK.md:2609-2612, research/study_area_run.md:332-336, planning/active/findings.md:100) — "m4 reaches m1 through a Tailscale relay" is filed under "Facts not worth re-deriving" as a standing fact, and the 47.6 min consolidate is attributed to it, but it is a transient path state and no committed log carries the probe (no output, no timestamp, so nothing shows it was the path during 22:10 to 22:58 UTC rather than when probed afterwards). Re-probed from m4 at 2026-11-03 00:30 UTC: `tailscale ping -c 5 m1` answered direct over the LAN on the first pong, and `tailscale status` lists m1 as "active; direct". `tailscale ping` itself drives the path toward direct, so a later reader who "does not re-derive" it will pack a worker on a premise that is already false, and one who probes will usually see direct. The RUNBOOK's advice (probe before launch) is right; the CLAUDE.md wording ("m4 reaches m1 through a relay") and the causal sentence in research should say it was the path observed at the time, with the probe's time, not a property of the m4-m1 pair. Throughput is consistent with the claim (COPY text of m1's bucket: streams 1.83 GB in 2,093 s, about 870 KB/s; barriers 309 MB in 562 s, about 550 KB/s), so the attribution is plausible, only unevidenced and stated as permanent.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** research/study_area_run.md:327 (CLAUDE.md does not repeat it) — "The minimal network modelled at 0.69 of the history's minutes overall" sits under a table whose own row gives 690.2 group minutes against 1,012 history minutes, which is 0.68. The 0.69 is the calibrator's run-wide ratio of leg minutes (701.6 / 1,011.9 = 0.693), which includes per-leg overhead. Also, 7.4 of the 1,012 are KTSU and OKAN at the median, not history. Small, but it is a published number that the table beside it contradicts; name which ratio it is.
  - **Rule:** none
