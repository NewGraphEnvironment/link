# Progress — study_area_run.sh: consolidate each cloud host when its own leg finishes, then burn it (#369)

## Session 2026-10-23 / 24

- Plan-mode exploration — phases approved by user (2026-10-23); gate: backup before the dispatcher leg; live check on little groups
- Created branch `369-study-area-run-sh-consolidate-each-cloud` off main
- Scaffolded PWF baseline from issue #369 with approved phases
- Operator, 2026-10-24: run all phases, launch the cyphers without waiting, poll so a hung run is caught
- Next: start Phase 1
- Phase 1: lock experiment shows both no-op DDLs (index, log column) block behind a COPY's lock, and the ALTER behind pg_dump's; fixed in `lnk_persist_init()` / `.lnk_log_create_tables()` with catalog reads, tested live. pg_dump of fresh_default: 7.6 min.
