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

## Sentinel gate — both known answers, measured

Four fixtures, old grep vs new anchored grep:

| fixture | old `grep -q "snapshot_bcfp.sh: complete"` | new `grep -qx "=== READY"` |
|---|---|---|
| snapshot completed, **persist_init FATAL** | **PASS** (the bug) | FATAL |
| full prep succeeded | PASS | PASS |
| `CYPHER_PREP_STAGE=install` partial prep | FATAL | FATAL |
| snapshot legitimately **skipped**, prep OK | FATAL (false alarm) | PASS |

Both defects reproduced and both fixed. The `-x` anchor is what stops the
install-stage sentinel satisfying a full-prep check.

## fresh symbol list cross-validated by two independent methods

A source scan of `R/` (comments stripped) and a walk of link's own parsed
namespace both return the same 12 `fresh::` call sites. The namespace walker
is what ships, because it works for an installed package where `R/` does not
exist — a source scan would find nothing there and report a clean drift check.

Symbols mentioned in roxygen/comments but never called: `frs_habitat`,
`frs_aggregate`, `frs_cluster`, `frs_db_conn`, `frs_edge_types`,
`frs_point_snap_knn`, `.frs_access_label_filter`, `.frs_connected_waterbody`,
`extdata`. Notably **`frs_point_snap_knn` is not exported by fresh 0.33.0** —
adding it to the required list from a naive grep would have broken the check on
every host for a reason unrelated to fresh.

Drift guard verified by restoring the bug: dropping `frs_wsg_outlets` from
`.lnk_fresh_required()` fails `test-lnk_preflight_fresh.R:78`, with the patch
proven to have taken before the result was believed.

## Pre-flight gates — both known answers, measured live on m1

Every gate exercised in both directions before shipping. No droplets, no spend.

| gate | firing case | passing case |
|---|---|---|
| primitive vintage | `--vintage-max-days=7` → FATAL, all four primitives named with ages (100/100/97/100 d) | `--vintage-max-days=200` → `✓ oldest 99.5 d` |
| persist schema | `--config=default` → FATAL naming `--schema=` | `--config=default --schema=fresh_default` → `persist: fresh_default` |
| tfvars `do_token` | `LNK_PREFLIGHT_DO_TOKEN=dop_v1_deadbeef…` → `✗ HTTP 401` | real token → `✓ HTTP 200` |
| DO reachability | `LNK_PREFLIGHT_DO_URL=https://127.0.0.1:1/…` → `✗ could not reach the DO API` | — reported distinctly from 401, not collapsed into it |
| branch pushed | unpushed branch → `✗ has no upstream` | after push (below) |
| worktree clean | uncommitted work + `N_CY>0` → `✗` ; `N_CY=0` → `WARN` only | clean tree |
| fwapg SHA | — | `✓ fwapg_sha e6e1eb0f4718` |

### A false positive the first run caught

The dispatcher fresh gate initially reported `✗ missing required symbols`
against a perfectly good fresh 0.33.0. Cause: the gate ran
`LNK_LOAD=loadall Rscript -e '...lnk_preflight_fresh...'`, but `LNK_LOAD` is
only read by the *driver scripts* — a bare `-e` never loads the package, so
the function did not exist, R exited non-zero, and the gate reported an
assertion failure for a broken invocation.

That is the same conflation the gates exist to prevent, one level up. Fixed by
loading inside the expression and giving "could not run the check" its own exit
code and its own message, so nobody is sent to debug fresh when the harness is
what broke.

## Bucketing derivation reproduces the issue's numbers

`data-raw/study_area_buckets.R` (union-find over per-WSG
`frs_wsg_drainage()` closures, then greedy LPT over components):

| claim | issue | derived |
|---|---|---|
| focal WSGs | 96 | 96 |
| raw closure | "close to 125" | **125** |
| modelable | 119 | **119** |
| drainage-independent components | 22 | **22** |
| dropped by species presence | LNRS, LEUT, LFRT, MFRT, UFRT, LKEC | **exact match** |
| dispatcher bucket | 39 | **39** |
| overlap between hosts | zero | **zero** (asserted, not assumed) |

Liard confirmed: LIAR, LMUS, ULRD, DEAR, FROG, BEAV and DUNE are all absent
from the focal set and all present in the closure — the mechanism behind the
93 → 119 growth.

**One deliberate difference.** The cypher split is 27/26/27 where the issue
says 28/24/28. The *components* are identical; only the packing differs,
because this weights by stream-segment count from `fwa_stream_networks_sp`
rather than by WSG count. A one-WSG component can outweigh a three-WSG one,
so segment count is the better proxy for work. The dispatcher figure (39) is
unaffected and matches.

Two consecutive `--write` runs are byte-identical, so the doc can be
regenerated in CI or by a reviewer without churning the diff.

## /code-check: five rounds, and what each found

| round | findings | notable |
|---|---|---|
| 1 | 6 | TSV `na.strings` seam: the parity gate printed "host parity clean" with `fwapg_sha` unresolved on every host |
| 2 | 3 | blocker **inside** round 1's fix — the new `~/.Renviron` guard was unreachable AND killed prep on every fresh droplet |
| 3 | 2 (+1 adjacent) | the completeness gate aborted with `CYPHERS_UP=1`, so the trap burned cyphers and destroyed work that had succeeded |
| 4 | 3 | round 3's two new guards were themselves unreachable — same `grep`-under-`set -e` class as round 2 |
| 5 | **0 — clean** | verified by restoring each round-4 fix and across 16 helper inputs |

**Rounds 1→4 each landed a blocker inside the previous round's fix.** The
recurring mechanism was not carelessness about the *rule* — the rule was
written down in the very comment above each defect — it was fixing one
*instance* of a class without sweeping the diff for the others. `grep` exiting
1 under `set -euo pipefail` caused three separate aborts in three separate
places across three rounds.

What ended it was replacing the remembered form with one that cannot be got
wrong: `csv_lines()` / `csv_count()`, built on `sed` (exits 0 having deleted
every line) rather than `grep -v '^$'` (exits 1). The two remaining
`grep -v '^$'` instances were swept even though both are provably unreachable
today, because the unsafe form is what gets copied next.

**One bug was caught by reading a probe's own output rather than by review:**
`printf '%s'` emits no trailing newline, so `wc -l` counted separators and
`csv_count "MORR,BULK"` returned 1. A host that completed its whole bucket
would have been reported incomplete. The test printed `job1 expected=1` for a
two-element bucket; the number was the tell.

**A backstop that did not back anything up.** Round 3's fix rested on the
coverage post-condition catching any gap. Round 4 showed it could not: it
asserts rows *exist*, not that they are *from this run*, and since the persist
accumulates and consolidate's DELETE is bucket-scoped, an excluded WSG keeps
its previous run's rows and passes. `RUN_INCOMPLETE` now carries the failure to
a non-zero exit at end-of-script — after the artifacts are written, so the
operator gets both the output and an honest status.

## Does the cypher split respect drainage closure? — audited

Asked post-review, checked rather than argued. Four properties, all on the
derived 4-host split:

| property | result |
|---|---|
| raw closures of distinct components pairwise disjoint | **0 overlapping pairs** |
| every host bucket drainage-closed (`closure(w) ∩ modelable ⊆ bucket`, for every `w`) | **0 violations** |
| DS-first order valid within each host, across concatenated components | **0 violations** |
| blocking dams in the 6 species-dropped WSGs | **none** |

The third is the one worth naming: a host can hold several components, and
its bucket is those components' DS-first lists concatenated. That is safe
*because* components are drainage-independent — no flow path crosses a
component boundary, so inter-component order is free. It is now checked
rather than reasoned about.

The fourth closes the residual gap. LEUT, LFRT, LKEC, LNRS, MFRT and UFRT sit
in the closure but are dropped by species presence, so they are never
modelled and never persist barriers. If one carried a blocking dam, a WSG
above it would be modelled with that dam invisible — the #227 failure. None
of the six holds a dam at all, so the gap is benign.

Both assertions are now **in the generator**, and both were verified by
restoring the bug: moving one WSG off its component's host gives
`host 1 bucket is not drainage-closed - missing HARR`, and reversing a host's
order gives `TAKL is ordered before its downstream LFRA, HARR, ...`. The
un-corrupted script exits 0 and `research/study_areas.md` is byte-identical,
so the assertions verify without changing the output.
