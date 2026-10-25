# #376 — persistent worker hosts beside the dispatcher and the cloud hosts

## Outcome

`study_area_run.sh --workers=<ssh target>,...` adds a third host kind: a machine
that exists and stays up, keyed `worker1..N`, prepped by `data-raw/worker_prep.sh`
from a clone the driver owns, modelled by load_all, accounted, consolidated and
released when its leg ends, its failed groups' leftover rows dropped, never burned.
Its premise is the remote-status rule, now applied to cloud hosts as well: no
decision reads ssh's exit status, because Tailscale SSH to macOS returns 0
whatever ran (`data-raw/study_area_remote.sh`, `consolidate_remote()`). Writing
it found a data-loss path that predates the branch: on such an ssh a COPY that
died part-way loaded its partial file and, with the bucket's total still rising,
consolidate deleted the source. Each table's load is now also counted against the
lines sent. The CY_* maps keyed by any remote host became HOST_*, and the packer
learned `--workers=N`.

Most of the design came from review, not the first draft. The plan review found
four blockers (no kept report on a run with no cyphers, workers in the burn list,
a `~/.Renviron` pin that beats any export, target validation). The code check ran
four rounds (3, 3, 6 and 4 findings), three of them finding a defect inside the
previous round's fix, and ended on enumerations: every value pasted into a remote
string, every input a worker has that the driver did not write, every pid the
trap signals, and every environment variable link's R reads. Round 3 named the
mechanism: cloud-host code assumes the host is the driver's alone. The worst find
was round 1's: in schema `fresh`, consolidate and the drop also reached the
snapshot primitives and the bcfp reference, which on a worker other sessions
share. Both now take link's tables only, held to what `lnk_persist_init()`
creates.

## Measurement

- **The premise:** on the worker, `ssh <w> 'exit 3'` returns 0 and the printed
  trailer reads 3 (2026-10-25 05:16 UTC). In Run C ssh reported 0 for a session
  whose loop had been SIGKILLed, and only the missing end marker held the worker.
- **A `~/.Renviron` line beats an exported variable, and a cwd `.Renviron`
  replaces `~/.Renviron`** (probe, 2026-10-24). An empty export does not clear a
  non-empty Renviron value (review round 4). Hence prep refuses what a worker sets
  for R, rather than trying to override it.
- **Run A:** six groups on two hosts, critical path 11.5 min, worker consolidate
  1.9 min for three groups, both verifiers pass at `expected_n=6`, the worker's
  schema left empty. Group minutes 1.3 to 2.4 on both hosts, all below the
  2026-10-23 run's, which ran under load: no speed ratio is drawn from them.
- **The worker needed two operator-approved writes first:** fresh 0.39.0 was below
  link's 0.42.0 floor (installed by the `--auto-install` path), and it had no
  primitive load stamps (`snapshot_bcfp.sh --force`, 14.5 min, under a login
  shell: a non-interactive ssh PATH on macOS lacks `psql`, `ogr2ogr`, `bcdata`).
- **Wrong turns kept:** the first Run C kill matched nothing (macOS runs R as
  `R --file=wsg_run_one.R --args HORS`); the first Run A launch stopped on a dirty
  fwapg checkout (another session's planning file), relaunched with `FWAPG_DIR`
  on a clean clone of the same commit; `worker_prep.sh` broke three times on an
  apostrophe in a comment inside its single-quoted R programs (now a bash 3.2
  parse test); the launcher's stdout named the worker once
  (`lnk_preflight_parity`'s summary), redacted since `7a62dc76`. Runs B and C
  also caught the dispatcher's own groups timing out under another session's
  database load (`frs_near_river_walk` past 30 min where it takes under 2), the
  2026-10-23 shape.

## Evidence

`data-raw/logs/worker_376/` (its README indexes Runs A, B and C).

## Owed

- Acceptance 2: a provincial run with a worker has a longest leg within 10 % of its packing estimate (next provincial `default` run; fills #377's runs row)
- Whether a dropped ssh session kills the remote loop: unmeasured (Run C killed the loop, not the session)

Closed by: PR for branch `376-study-area-run-sh-persistent-worker-host`
