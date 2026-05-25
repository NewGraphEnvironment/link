# Study-area run (tunnel-free, M1-dispatch)

Lean alternative to the 5-host `provincial_run_runbook.md` for running the **3
FWCP study areas** (Peace / Fraser / Skeena) mapping_code parity. Reuses the
proven per-WSG build + cypher lifecycle but is **tunnel-free** (compare =
local bcfp snapshot, no `:63333`) and **M1-as-dispatcher** (no M4). Built for
link#175. Companion: `provincial_run_runbook.md` (shared mechanics),
`RUNBOOK.md` (the access/mapping_code machinery), `data-raw/README.md`.

## One command

```bash
cd ~/Projects/repo/link
# largest area on the dispatcher (fast/free M1); smaller areas on the cyphers
bash data-raw/study_area_run.sh \
  --cy-workspaces=job1,job2 \
  --focal=<Fraser focal csv>  \   # -> dispatcher (M1)
  --focal=<Peace focal csv>   \   # -> cy1 (job1)
  --focal=<Skeena focal csv>      # -> cy2 (job2)
```

Focal lists live in `~/.claude/.../memory/study-areas-peace-fraser-skeena.md`.
`--focal` count MUST equal `1 + N(--cy-workspaces)`; first = dispatcher, rest =
cyphers in order. Dispatcher-only (no cyphers): omit `--cy-workspaces`, pass one
`--focal`. Pre-req: dispatcher has `fresh.streams_vw_bcfp`
(`snapshot_bcfp.sh --with-bcfp-views`); branch pushed to origin (cyphers pull it).

## What it does

1. **Pre-flight** (tunnel-free): local fwapg up, `fresh.streams_vw_bcfp` present,
   doctl/tofu (only if cyphers).
2. **Drainage-closed DS-first buckets** (`study_area_wsgs.R`): each focal set →
   its closure (every WSG it drains through, via `public.wsg_outlet`,
   `f.outlet <@ w.outlet`) ordered downstream-first (`nlevel(outlet) ASC`),
   then **filtered to bundle-species presence** (link#157).
3. **Spin + prep** cyphers (`cypher_up.sh`, `cypher_prep.sh` with
   `CYPHER_PREP_BRANCH=<dispatcher branch>`).
4. **Run** each host's bucket DS-first (`wsg_run_one.R` =
   `lnk_pipeline_run(mapping_code=TRUE)`), dispatcher local + cyphers via ssh,
   per-WSG **soft-fail**.
5. **Consolidate** cyphers → dispatcher (`schema_consolidate.R`, shape-tolerant).
6. **Burn** cyphers (then a trap-EXIT safety net).
7. **Compare pass 1** all run WSGs tunnel-free (`study_area_compare.R`).
8. **Post-consolidate recompute** the diverged WSGs (any species `<99%`) on the
   dispatcher — now that ALL barriers are consolidated, re-model them against
   the complete barrier set (`wsg_run_one.R`), order-independent.
9. **Compare pass 2** (final CSV).

## Post-consolidate recompute — the correctness guarantee

Each WSG's accessibility (hence its `mapping_code` token1 ACCESS/SPAWN/REAR and
token2 DAM/…) depends on whether a blocking barrier exists **downstream** —
possibly in a *different* WSG (the provincial-accumulation property,
`RUNBOOK.md` §5). When WSGs are distributed across machines, each machine holds
only its own bucket's barriers while it runs, so a WSG's access is computed
against an **incomplete** barrier set → wrong tokens.

**Drainage-closed + DS-first bucketing is NOT sufficient on its own.** It
*reduces* divergence (downstream often persists first within a bucket) but does
not eliminate it: downstream barriers can be cross-bucket, or arrive late in
DS-first order. Caught 2026-05-25 — FINA 75.5% / PARA 68.6% per-host → both
**99%+** after re-modelling on the full consolidated barrier set.

So the methodology is **distribute (any bucketing) → consolidate → recompute →
compare**, and the *recompute* is what makes it correct **regardless of machine
count or WSG assignment**. The bucketing is now just a speed knob (less
divergence → less recompute), not a correctness lever. Today the recompute uses
the full pipeline on diverged WSGs (slow); the cheap access-only recompute that
reuses persisted streams/habitat is **link#205** — that makes recompute-ALL
viable and the guarantee bulletproof rather than threshold-based.

## Gotchas that cost real time (2026-05-25)

- **A per-WSG FATAL burns the cyphers with un-consolidated data.** A
  species-less closure WSG (LEUT) errored `No species resolved for AOI` →
  `|| exit 1` → driver FATAL → trap `cypher_down` → an entire run's Peace+Skeena
  data gone. **Fixes:** species-presence filter the closure (link#157) AND
  per-WSG soft-fail (never abort a host before consolidate). The cyphers were
  NOT externally destroyed — the driver's own trap burned them.
- **Cyphers checkout `main` by default.** The driver scripts + branch link only
  exist on the feature branch → cyphers must run `CYPHER_PREP_BRANCH=<branch>`,
  and the branch must be **pushed** first (`cypher_prep` does `git fetch origin
  && git reset --hard origin/$BRANCH`).
- **Fresh-droplet sshd race.** `cypher_up` returns when the IP is assigned,
  before sshd is up → scp `Connection closed`. Poll ssh before scp.
- **Wide-table shape drift across hosts.** `streams_access` /
  `streams_mapping_code` carry one column per species; a host seeding persist
  from `parameters_fresh` (11 sp) vs `cfg$species` (8 sp) breaks the positional
  COPY-consolidate. `cypher_prep` now uses `cfg$species`; `schema_consolidate`
  COPYs shared columns by name (link#204).
- **Cypher cost is ~$0.06/hr each.** "Minimize idle" means don't leave them up
  for HOURS (the 2026-05-12 10-hr incident), not shave minutes. Don't
  over-engineer early-burn for cents.

## Scripts

| Script | Role |
|---|---|
| `data-raw/study_area_run.sh` | driver: pre-flight → spin → prep → run DS-first → consolidate → burn → compare |
| `data-raw/study_area_wsgs.R` | focal → drainage-closed, DS-first, species-filtered WSG list |
| `data-raw/wsg_run_one.R` | one WSG: `lnk_pipeline_run(mapping_code=TRUE)`, local, host-agnostic |
| `data-raw/study_area_compare.R` | tunnel-free `lnk_compare_mapping_code` loop → CSV |
