# Run logs

**These are retained deliberately as contemporaneous evidence of measurement
runs, not accumulated by accident.** They are tracked in git, not gitignored,
and should stay that way — see NewGraphEnvironment/soul#129.

Every number quoted in a `research/` run record, a NEWS entry or a PR body
should be traceable to a file here.

## What is here

| pattern | produced by | holds |
|---|---|---|
| `study_area_run/<TS>_up_<ws>.log` | `cypher_up.sh` via `study_area_run.sh` | droplet spin, tofu apply, cloud-init wait |
| `study_area_run/<TS>_prep_<ws>.log` | `cypher_prep.sh` | git reset, package install, snapshot, persist_init |
| `study_area_run/<TS>_stamps.tsv` | `host_stamp.R` | one provenance line per host — the parity gate's input |
| `study_area_run/<TS>_vintage.log` | `host_vintage.R` | primitive freshness per host |
| `study_area_run/<TS>_run_{local,<ws>}.log` | `wsg_run_one.R` | per-WSG modelling, `done in N min` |
| `study_area_run/<TS>_consolidate.log` | `schema_consolidate.R` | cross-host COPY |
| `study_area_run/<TS>_recompute.log` | `wsg_recompute_one.R` | post-consolidate access rebuild |
| `study_area_run/<TS>_compare.{log,csv}` | `study_area_compare.R` | bcfishpass parity |
| `study_area_run/<TS>_burn_<ws>.log` | `cypher_down.sh` | teardown + verification |
| `bcfp_baselines.csv` | `snapshot_bcfp.sh` | which upstream bcfp build each host loaded |
| `provincial_*/`, `methodology_delta/` | earlier orchestrators | historical runs |

`<TS>` is UTC `YYYYMMDD_HHMMSS` and is shared by every file from one run, so a
single run's artifacts sort together.

## Reading a run

Phase durations are not logged as such — reconstruct them from file mtimes,
which is how the timings in `research/` were derived:

```bash
python3 -c "
import glob,os,datetime
fs=sorted(glob.glob('data-raw/logs/study_area_run/<TS>_*'),key=os.path.getmtime)
t0=os.path.getmtime(fs[0])
for f in fs: print('%6.1f min  %s' % ((os.path.getmtime(f)-t0)/60, os.path.basename(f)))"
```

Per-WSG runtimes are better read from the run log itself
(`grep 'done in' <TS>_run_*.log`) or, for any run after v0.45.0, from
`<persist>.log` in Postgres, which records `date_start` / `date_end` per WSG
alongside the software SHAs.
