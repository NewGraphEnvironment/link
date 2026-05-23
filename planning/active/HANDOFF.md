# HANDOFF — #196 mapping_code / access work → M1 (2026-05-23)

**You are picking up mid-stream. Do NOT start over. The mechanism is solved and
the next step is planned.** Read this, then `RUNBOOK.md`, then the PWF files. ~5
min and you're oriented.

> Why this file exists: memory (`~/.claude/...`) is machine-local and did NOT
> travel from M4. The repo is the only bridge. Everything you need is committed.

## Read in this order

1. **`RUNBOOK.md`** (repo root) — the durable mental model. §5 is the heart:
   how bcfp's per-species access set works and exactly where link diverges.
2. **`planning/active/findings.md`** — the investigation trace + the RESOLVED
   2026-05-23 section (bcfp source read authoritatively).
3. **`planning/active/phase4d_plan_draft.md`** — the approved-direction fix,
   scoped (composition + wiring, not new modelling).
4. **`planning/active/issue_phase4d_draft.md`** + **`issue_blocks_species_redesign_draft.md`**
   — issue bodies to FILE (user said yes; review then `gh issue create`).
5. `task_plan.md` / `progress.md` — checkboxes + session log.

## State (what's done / decided)

- **v0.40.3 ready to ship.** Branch `196-streams-access-source-flags`. Persist
  per-source-flag fixes (commits 91f3f90, e23819a, 475e397) are correct +
  verified in isolation. DESCRIPTION + NEWS bumped. PR open (or open it:
  `/gh-pr-push`) → merge with `/gh-pr-merge` from a stable connection.
- **Mechanism SOLVED** (RUNBOOK §5). bcfp `barriers_<sp>` = natural-only
  (gradient@species-threshold + falls + subsurface) − observation/habitat
  override + user_definite. Dams are descriptors (token2), never in the access
  set. link diverges by (1) carrying dams in `barriers_per_sp` and (2) wiring
  the override to classify (habitat) not access.
- **User decisions (approved):** (1) ship v0.40.3; (2) file the Phase 4d issue;
  (3) file the blocks_species/dam-override redesign issue (later, depends on 4d).
- `lnk_pipeline_run` `barriers_per_sp` is reverted to `_unified` —
  KNOWN-DIVERGENT (dam-downstream segments emit bare `SPAWN`, not `SPAWN;DAM`).
  Phase 4d fixes it.

## What's NOT done (pick up here)

- File the two issues (drafts ready, user approved).
- Build Phase 4d (the access-set fix). Plan is in `phase4d_plan_draft.md`.
- Validate on **PARS + LFRA** (resident + anadromous dam systems).

## DB state does NOT travel — rebuild on M1

The docker `fresh-db` (snapshot + persist tables + working schemas) is M4-local.
On M1 you must either rebuild or use the tunnel:

- **Inputs + bcfp comparison:** `PGUSER=postgres PGPASSWORD=postgres
  PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg bash data-raw/snapshot_bcfp.sh
  --with-bcfp-views --force` (tunnel-free, public sources). **Known bug
  (RUNBOOK §6):** the 1.6 GB `streams_vw` fgb silently fails to load via
  `/vsizip//vsicurl` (ogr2ogr exits 0). For bcfp streams parity you need to
  curl-download + unzip + load locally, or use the tunnel.
- **link output:** re-run `lnk_pipeline_run(conn, "PARS"/"LFRA", cfg, loaded,
  schema, mapping_code = TRUE)` to repopulate persist (`fresh_default`).
- M1's `~/.Renviron` defaults `PG_*_SHARE` to the tunnel (`:63333`). For local
  docker use `Sys.setenv()` in R to point at `:5432` (see fresh/CLAUDE.md, the
  m1-testing pattern).

## Environment

- docker fresh-db compose: `~/Projects/repo/fresh/docker/` (`docker compose up -d db`).
- bcfp tunnel: `ssh -o BatchMode=yes -L 63333:127.0.0.1:5432 db_newgraph -N -f`
  (flaky from M4; M1 reaches it natively). Build is tunnel-free; only parity diff needs it.
- bcfp this week: model_run_id 123 (`v0.7.15-...`). Snapshot reloaded 2026-05-23.
