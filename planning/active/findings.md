# Findings — #246 pre-flight gates

All measured on **m1** (the dispatcher), 2026-08-30. Nothing here is inferred.

## Issue claims verified

| claim | measured |
|---|---|
| `fresh` schema has no log tables | confirmed — `fresh_default` has all 4 |
| 93 WSGs / 2,865,775 rows | exact match |
| orphan state | 31 `working_*` schemas, 49 `zz_lnk_mc_scratch_*` tables |
| primitives stale | `cabd.dams` 2026-05-23, `fresh.modelled_stream_crossings` 2026-05-26 |
| cypher image | `cypher-20260512-warm` bakes link 0.35.0 + fresh 0.31.0 |
| both configs → same schema | `bcfishpass` → `fresh`, `default` → `fresh` |

`zz_lnk_mc_scratch_*` live **inside** the persist schema
(`wsg_recompute_one.R:76`, `paste0(sch, ".", mc_name)`), so
`DROP SCHEMA fresh CASCADE` does take them. An `on.exit` drops them per run;
the 49 survivors are from crashed runs.

## Root cause is narrower than the issue states

`DESCRIPTION:34` already pins `NewGraphEnvironment/fresh@v0.33.0` and `:40`
declares `fresh (>= 0.33.0)`. **The pin is never resolved** because `fresh` is
in **Suggests** and `pak::local_install()` defaults to `dependencies = NA`
(verified: `formals(pak::local_install)$dependencies` is `NA`).

20 files under `R/` call `fresh::` with **zero** `requireNamespace()` guards,
including a default argument on an exported function
(`lnk_wsg_downstream_check.R:335`, `outlets = fresh::frs_wsg_outlets()`), and
`lnk_pipeline_connect.R:101` does `getFromNamespace(".frs_run_connectivity")`.
fresh is a hard runtime dependency mis-declared as optional.

**So the fix is a declaration fix, not an install line.** `upgrade = FALSE`
suppresses *gratuitous* upgrades, not *required* ones — 0.31.0 does not satisfy
`>= 0.33.0`, so pak is forced to resolve it and consults `Remotes`. Line 58 of
`cypher_prep.sh` needs no edit; it starts doing the right thing the moment the
declaration is honest.

## Version boundary

| fresh tag | `frs_wsg_drainage` | `frs_wsg_outlets` |
|---|---|---|
| v0.31.0 | absent | absent |
| v0.32.0 | **exported** | absent |
| v0.33.0 | exported | **exported** |

Floor is **v0.33.0**, not "newer than 0.31.0". The issue is imprecise here.

## The sentinel bug fails toward PASS (found post-approval)

`study_area_run.sh:203` greps the prep log for `snapshot_bcfp.sh: complete`.
Two independent defects:

1. **Fail-toward-pass (dangerous).** `snapshot_bcfp.sh:277` emits the sentinel;
   `cypher_prep.sh:85`'s `tail -5` copies it into the prep log. `lnk_persist_init`
   then runs at lines 100–126. A persist_init FATAL exits 1 **with the sentinel
   already logged**, so `grep -q` succeeds, the umbrella prints
   `✓ cyphers prepped`, and WSGs run against a half-prepped cypher.
   `cypher_prep.sh:98`'s own comment anticipates this class inside prep — but
   the umbrella still reads the wrong line.
2. **Fail-toward-stop (false alarm).** The skip-if-current path at
   `snapshot_bcfp.sh:111–113` prints `snapshot_bcfp: …skipping.` (note: no
   `.sh`) and exits 0, never reaching the sentinel → spurious FATAL.

`=== READY` (`cypher_prep.sh:127`) is the only line implying every stage passed.
Same bug at `wsgs_run_pipeline.sh:267`.

## Parity must key on `repo_sha`, not `link_sha`

`.lnk_pkg_git_sha()` (`lnk_stamp.R:264`) resolves from `.git` in the package
dir. On the dispatcher link is `pkgload::load_all`'d from a checkout → real SHA.
On cyphers it is pak-installed → `NA`. `fresh_sha` is `NA` on **both**. So a
naive `link_sha` comparison always fails and a `fresh_sha` comparison is a
vacuous `NA == NA` pass — a check that looks like a check.

The honest key is `repo_sha`: the git state of `~/Projects/repo/link` observed
**on each host**, which on a cypher is exactly what
`git reset --hard origin/$BRANCH` produced (`cypher_prep.sh:51`).

**Subtle distinction, easy to conflate:** the cypher writing its *own* observed
SHA into its *own* `~/.Renviron` is evidence. The dispatcher exporting
`LINK_GIT_SHA` over ssh would launder the dispatcher's claim into the cypher's
provenance and make the gate circular. Do the first, never the second.
`FWAPG_GIT_SHA` is the exception — cyphers have no fwapg checkout, so the
dispatcher's value is the only one available and is explicitly a shared input.

## `last_analyze` is NULL on every primitive

The issue's Phase 2 bullet says assert `max(last_analyze)`. Measured: **NULL for
all ten** primitive tables; only `last_autoanalyze` is populated. Empty in bash
reads as "nothing to see" — the exact anti-pattern CLAUDE.md documents.

Use `GREATEST(last_analyze, last_autoanalyze)`. Postgres `GREATEST` ignores
NULLs (unlike MySQL) and is NULL only when every argument is — the behaviour
wanted. The seven FWA tables are bulk-restored and never analyzed, so they carry
no vintage at all and are excluded; the four snapshot-loaded primitives are the
axis.

## `tofu plan` is a false-green credential probe

Two distinct DO credentials, both minted 2026-05-18, both expired 2026-08-30:
`access-token` in doctl's config (used by pre-flight and reserved-IP recovery)
and `do_token` in `rtj/env/do/dev/cypher/terraform.tfvars` (what actually spins
droplets). `tofu plan` against a zero-resource workspace returns `Plan: 2 to add`
without ever calling the DO API.

The existing `doctl compute droplet list` **does** hit the API — its weakness is
asserting only an exit status on a command whose healthy answer is an empty
list. `tofu workspace list` exercises the **s3 backend** (AWS creds), not DO;
labelling it a DO check is what let the old pre-flight stay green.

## `schema_consolidate` deletes before it copies

`schema_consolidate.R:272–276` DELETEs the destination bucket, `:313–316` COPYs.
A cypher that produced nothing therefore **deletes** the dispatcher's prior rows
for those WSGs and returns `ok = TRUE`. Under #246 the run was not merely
failing to add data — it was removing it and reporting success. This is why the
post-consolidate coverage assertion is the highest-value item.

Tables are selected solely by having a `watershed_group_code` column
(`:155–161`), so `log` / `log_input` travel but `log_parameters_fresh` /
`log_dimensions` never do (RUNBOOK:464–467 states this).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| | |
