# Progress — Provincial run autonomy + script renames (#172)

## Session 2026-05-14 (afternoon — post-#168)

- Resumed #172 against the new #168 architecture. PG-state resume + decoupled `wsg_pipeline_run`/`wsg_compare` are now in place, so most of yesterday's first-attempt scab fixes (smoke auto-skip, archive --config, phantom-cy mitigation via fallback paths) became unnecessary.
- Plan-mode exploration — phases approved by user. Locked in yesterday's rename decisions (umbrella = `wsgs_run_pipeline.sh`, per-host loop = `wsgs_run_host.R`, mixed nouns for other wrappers).
- Cypher integration deferred to follow-up — keeps PR scope tight, matches #168 discipline.
- rtj cross-repo update authorized (direct commit + push).
- Created branch `172-provincial-run-autonomy-renames` off main (v0.37.0 baseline).
- Scaffolded PWF baseline (`task_plan.md`, `findings.md`, `progress.md`) with 7 approved phases.
- Next: start Phase 1 — patch `trifecta_provincial.sh` for `--wsgs`, `--no-cyphers`, `--force`, plus phantom-cy fix.
