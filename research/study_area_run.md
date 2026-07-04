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

Focal lists + study-area definitions: [`research/study_areas.md`](study_areas.md).
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
7. **Post-consolidate recompute ALL run WSGs** on the dispatcher via
   `wsg_recompute_one.R` → [lnk_access()] `merge=TRUE` (cheap access-only,
   reuses persisted streams/habitat/barriers; ~10s/WSG) + `lnk_mapping_code`.
   Because it is cheap, every run WSG is re-settled — bucketing is a speed
   knob, not a correctness lever (link#205).
8. **Compare** all run WSGs tunnel-free (`study_area_compare.R`) → CSV.

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
count or WSG assignment**. The recompute is **`lnk_access(merge=TRUE)` +
`lnk_mapping_code`** (link#205): cheap access-only, reusing the persisted
streams / habitat / barriers / barrier_overrides — no full pipeline, ~10s/WSG
(FINA: 11.86s wall vs ~90s full pipeline, identical bcfp parity). Two
non-obvious things had to be true for it to be cheap:
1. AOI-scope the segments as a **real table** (with indexes + `ANALYZE`),
   not a view — otherwise the planner picks the ~800k-row barriers as the
   outer driver and the join cost explodes by ~1000×.
2. Persist `streams` / `barriers` need **ltree GIST/btree indexes**
   (`lnk_persist_init` builds them; matches `fresh`'s working-table pattern).
3. `lnk_mapping_code` must filter access by `watershed_group_code` when the
   table has that column (persist) — the original `id_segment IN (…)` query is
   cartesian against persist because `id_segment` is per-WSG, not globally
   unique (link#203).

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
| `data-raw/wsg_recompute_one.R` | one WSG cheap post-consolidate recompute (`lnk_access(merge=TRUE)` + `lnk_mapping_code`) — link#205. Sets `statement_timeout`/`lock_timeout` so a runaway/locked query fails fast |
| `data-raw/study_area_compare.R` | tunnel-free `lnk_compare_mapping_code` loop → CSV |

## Cypher operational gotchas

The tunnel-free M1-dispatch runner tripped over things the older `wsgs_run_host.R`
+ `research/provincial_run_runbook.md` already solved. The worst (2026-05-25): a
species-less closure WSG (LEUT) errored "No species resolved for AOI" → `|| exit 1`
→ driver FATAL → the trap's `cypher_down` **burned the cyphers with their
un-consolidated data** — a whole run's Peace + Skeena gone, self-inflicted (the
driver's own trap, not external destruction).

- **Always species-filter the WSG set** to bundle-species presence (link#157,
  `wsgs_run_host.R:88` pattern) — closure pulls in unmodelable WSGs.
- **Per-WSG soft-fail; never abort a host before consolidate** — one bad WSG must
  become a compare gap, not total data loss.
- **Cyphers checkout `main` by default** → pass `CYPHER_PREP_BRANCH=<branch>` AND
  push the branch first (`cypher_prep` does `git reset --hard origin/$BRANCH`).
- **Wait for sshd before scp** to a fresh droplet (`cypher_up` returns pre-sshd).
- **Cyphers cost ~$0.06/hr each** — "minimize idle" means don't leave them up for
  hours, not shave minutes; don't over-engineer early-burn.
- **Read the records first** (`RUNBOOK.md`, `research/provincial_run_runbook.md`,
  `data-raw/wsgs_run_host.R`) before re-deriving orchestration.

### Correctness knob: post-consolidate recompute

Per-segment access (hence mapping_code) depends on **downstream** barriers, possibly
in another WSG (provincial accumulation, RUNBOOK §5). Distributed hosts each see only
their own bucket's barriers mid-run → incomplete → wrong tokens. **Drainage-closed +
DS-first per-host is NOT sufficient** (it only reduces divergence): 2026-05-25 had
FINA 75.5% / PARA 68.6% per-host → 99%+ only after re-modelling on the consolidated
barrier set. So recompute the diverged WSGs on the dispatcher post-consolidate.
Bucketing is a speed knob, not a correctness lever. Authoritative result: median
**99.66%**; genuine divergences SETN salmon ~94%, UNRS BT 61.8%. The full-pipeline
recompute is ~2× on diverged WSGs; a cheap access-only recompute (#205) makes
recompute-all bulletproof + ~1×.
