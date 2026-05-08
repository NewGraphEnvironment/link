# Progress — manual snapshot of bcfp dependencies (#137)

## Session 2026-05-08

- Plan-mode exploration: confirmed observations source is `bchamp/bcfishobs/observations.parquet` (matches bcfp's `jobs/load_observations`); the s3://newgraph fgb dump of `fiss_fish_obsrvtn_events_vw` is a different artifact and NOT what bcfp consumes.
- Cadence alignment confirmed: Simon's dump_weekly Sun 03:00 UTC captures most-recent Tue rebuild output. bcfp views from s3://newgraph are aligned with the most recent rebuild SHA at any time between Wed and the next Tue.
- Branch `137-data-raw-manual-snapshot-of-bcfp-depende` created off main.
- Scaffolded PWF baseline.
- Phase 1 done: `data-raw/snapshot_bcfp.sh` shipped — 6 sections + `--with-bcfp-views` flag. `bash -n` clean.
- Phase 2 done: `data-raw/README.md` `## Bootstrap` section added with prereqs + quick-start + output schema list.
- Phase 3 in progress: DESCRIPTION + NEWS bumped to 0.31.1. Tests no-op pass (808). Commit + push + PR + merge next.
