# variants_parallel_406 — a variant's groups in parallel (#406)

## Run decision (written before any build)

- **What is measured.** `habitat_variants_build.R --step=variants` at `--jobs` 1, 2, 4 and 8:
  the `default` pass and `bt_rear_wet_p10`'s pass over #331's nine groups, with each pass's
  wall minutes (`pass_wall`) and per-step seconds. The question is how much width buys and
  where the database stops paying, against #404's greedy bound (1.6 and 1.8 min at four jobs)
  and #374's ceiling of about four jobs on a full-width recompute.
- **The base is #404's, reused.** `score404_default` and `working_score404_<wsg>` (built
  2026-10-28 at `45b12b2e`, fresh 0.44.0) still sit on m4. A variants step reads them and
  rebuilds nothing of the base. Each width builds into its own `--out` (`j<N>/`), into which
  #404's `base_habitat_digest.csv` and `closure.txt` are copied, so no width overwrites
  another's timing rows. Every width writes the same schema, `score404_bt_rear_wet_p10`.
- **Order.** Widths 1, 2, 4 then 8, one after another. After each, `digest.R` writes
  `digests_j<N>.csv`: the variant schema's `streams`, `streams_access` and
  `streams_habitat_bt`, each working schema's `streams_habitat`, and the base's
  `streams_habitat_bt` as a control. `compare.R` then requires every digest identical across
  the widths. It must fail on a perturbed digest and see the base against the variant as
  different, or it stops.
- **Host and software.** m4 (Apple M4 Max, 16 cores, 128 GB), local docker fwapg
  (`fresh-db`, `max_connections` 40). fresh 0.44.0 (the pin). link from a `git worktree` at
  the branch commit the stamp names, so this checkout can take commits while it runs.
- **Load from elsewhere.** At planning (14:56 PDT) the host's load average was 5.4 / 5.4 / 4.9
  with no other client on the database. Each timing row carries the 1-minute load at its
  pass's start, and `launch_state.txt` holds the load and other database clients at each
  width's launch.
- **Schemas stay**, as every `score*` schema has.

## Files

| file | what it is |
|---|---|
| `run.sh` | the four builds and their digests, in order, with each launch's state |
| `j<N>/` | the build at `--jobs=N`: `build.log`, `built.csv`, `variant_timing.csv`, `stamp_build.txt`, `bundles/`, and the copied base files |
| `digest.R` → `digests_j<N>.csv` | md5 per schema, table and group after each build |
| `compare.R` → `compare.csv` | every digest across the four widths, with its two self-checks |
| `analyze.R` → `wall.csv`, `steps.csv` | wall minutes per pass and width; summed step minutes per width |
| `launch_state.txt` | load and other database clients at each launch and at the end |
