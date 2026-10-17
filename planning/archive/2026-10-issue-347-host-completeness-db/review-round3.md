# Code-check round 3: link#347 branch (`study_area_hosts.sh`, `study_area_run.sh`)

Reviewer: subagent, 2026-10-17. Scope: `merge-base...HEAD` diff, the two scripts in full,
the test file, RUNBOOK "Which host may be burned (link#347)", and the R / consolidate
context. Test file run: `NOT_CRAN=true` `test_file()`: 27 blocks, 0 failed, 0 error, 0 skipped.
No repo file edited; demos ran in the scratchpad.

## Mechanism

Your reading is right as far as it goes ("a proxy defines a set, the set drives an
action, and the action's safety depends on a property the proxy does not measure"), but it
is too wide to tell a sound proxy from a broken one. Every set in this code is a proxy. What
the four bugs so far share is narrower.

**The code turns an observation into a cause, and the operator acts on the cause.** A probe
measures *rows present on host H at time T*. The lib then labels the group "finished",
"partial / failed build" or "the recompute already ran without these". Each label holds
only if two things are true that no probe checks:

1. **Provenance.** The rows were written by *this* run's `lnk_pipeline_run()`. Nothing
   checks that the host's persist schema held no rows for the bucket before dispatch.
2. **Settledness.** Nothing changes the state after T. The host's dispatch session has
   ended, and the dispatcher-side step the text names (the recompute) actually ran.

R1 ("streams rows mean nothing left / unconsolidated") and R2 ("streams rows mean
finished") were the cause labels getting the observation wrong. R2's fix ("no
finish signal means a failed build, never consolidate") is correct only once (2) holds:
on every path where the host's session has exited 0. In the EXIT trap and on the
`CY_RUN_RC != 0` path that has not been established, so the same mistake comes back in
the opposite direction. The recompute sentence in `hosts_kept_report` asserts a dispatcher
state it never measures. This is the same pair of lists happening to agree: the lib's
labels and the driver's actual progress agree on the happy path and nowhere else.

**Where it reaches:** every label `host_split` and `hosts_kept_report` emit (recoverable,
partial, the recompute instruction), and the consolidate bucket (DONE_LOG). The full table
is below. Three findings are unsafe.

## Findings

### 1. In-flight groups are labelled "partial, do NOT consolidate" when the session may still be running (unsafe: under-reports, so finished work is burned)

`data-raw/study_area_hosts.sh:128-149` (`host_split`), `:387-403` (kept report), `:408-417`
(banner); `:285-290` (`.hosts_keep_cause`).

`CY_PARTIAL` means "streams rows present, no finish signal *at the time of the probe*". The
comments (`:131`, `:229-231`, `:247`) and the banner treat that as "a failed build that must
never be consolidated, so rebuild it". That holds only when the host's dispatch session has
ended (`CY_RUN_RC = 0`). `host_release` guarantees this for the release path. Two paths do
not:

- **The EXIT trap after dispatch has started** (`CY_HOLD=1`; accounting may not have run;
  `CY_RUN_RC` unset). I measured this in the scratchpad: a bash script that gets SIGTERM
  while it `wait`s runs its EXIT trap **and its background child stays alive**. In the
  driver that child is the `ssh … for w in $B_SPACE; do Rscript …` session at
  `study_area_run.sh:1076`, so the remote bucket loop keeps building groups after the trap
  has written the TSV. A plain `kill <driver pid>` does this, and so does any SIGTERM from a
  supervisor.
- **`host_release` with `CY_RUN_RC != 0`** (`:237-238`): the WHY says "groups may still
  be running there", but the banner still prints `partial, do NOT consolidate` and "Never
  groups_partial".

Demo (scratchpad `demo/run.sh`: stubbed ssh, host holding AAAA complete and BBBB pre-persisted;
the trap state is `CY_HOLD=1` with no accounting):

```
cy[job1] (cypher-job1): run stopped before consolidate released it; may hold finished groups
  finished, still on the host: AAAA
  partial, do NOT consolidate: BBBB
```

BBBB finishes on the host a minute later. An operator following the TSV consolidates AAAA
only and runs `burn_command`, which destroys BBBB's finished, paid build. That is the loss
#347 exists to prevent (re-runnable, but lost). `groups_measured = yes` makes it read
as authoritative. Fix: where `CY_RUN_RC` is not `0`, set `groups_measured` to something
other than `yes` (or probe the host for a live `wsg_run_one.R` and refuse to classify while
one runs). Word the reason and banner as "still running / not finished when probed:
re-measure after the remote loop ends", not "partial, never consolidate".

### 2. The kept-host banner claims the recompute ran without the kept groups, on paths where it never ran (unsafe: silently wrong access for the other groups)

`data-raw/study_area_hosts.sh:413-415`, also RUNBOOK §"Which host may be burned"
("The run's recompute ran without the kept groups, so after consolidating recompute each
one and each run group upstream of it").

`hosts_kept_report` prints this unconditionally, and it is reached from the EXIT trap on
every abort after dispatch. On at least two of those paths the post-consolidate recompute
never ran for **any** group:

- consolidate failure: `study_area_run.sh:1348`, `exit 1`;
- the coverage FATAL: `:1395`. That one fires exactly when a kept host holds a group the
  dispatcher never had (a new schema, or a first-time group on an unknown or `RC != 0`
  host), the kept-hosts case itself, and it exits before `:1450`.

Neither path prints the final INCOMPLETE banner. The only recompute instruction the operator
sees is "recompute each one and each run group upstream of it". Every group that *was*
consolidated (from other cyphers, and the dispatcher's own) but is not upstream of a kept
group keeps its per-host `streams_access` / `streams_mapping_code`. CLAUDE.md records those
as wrong across buckets (FINA 75 % before recompute). Nothing reports this, and the compare
looks complete. The sentence asserts a state nobody measured, the same shape as R2's
recompute finding. Fix: track whether the recompute pool ran (for example a
`RECOMPUTE_RAN=1` set after `run_recompute_pool` and read by the banner). Before it has
run, say "the recompute did NOT run: recompute every run group
(`wsg_recompute_one.R` over ALL_WSGS) after recovering".

### 3. (Low, latent: not reachable on the current image) "Has streams_mapping_code rows" is read as "finished by this run"

`data-raw/study_area_hosts.sh:117-126` (`host_complete`), `:144-146`; RUNBOOK
("`streams_mapping_code` rows, which only the final persist writes").

Within one `lnk_pipeline_run()` the claim holds:

- `lnk_pipeline_setup(overwrite = TRUE)` drops `working_<wsg>`, so the pre-persist's
  `mapping_present` probe (`R/lnk_pipeline_persist.R:186-192`) is FALSE.
- The final persist writes mapping code last, and each statement autocommits. Rows
  present therefore means every earlier table was written.

But the probe reads the **persist** table, which can hold rows this run never wrote, and
the pre-persist does not DELETE them (it skips mapping code entirely). Cypher hosts spin
from a `--keep-data` warm snapshot (rtj `planning/archive/2026-05-issue-97-warm-snapshot/`),
so the image's fwapg volume, persist schemas included, is on every new droplet.
`cypher_prep`'s `lnk_persist_init(force_recreate = TRUE)` drops only tables with
`GENERATED` drift, never rows. Consider an image baked from a host that had run a
mapping-code build. A bucket group whose run here fails after the pre-persist, or SKIPs, or
fails early, then reads as recoverable. Recovery consolidates new streams/habitat/barriers
beside stale `streams_access` / `streams_mapping_code`, or plain stale rows, over the
dispatcher's copy.

**Not reachable today:** the image in use is `cypher-20260512-warm` (link 0.35.0), which
predates `streams_mapping_code` (v0.40.0). Stale `streams` rows alone only add to
`partial`, which is safe on the release path. Cheap guard: assert at prep or dispatch that
`host_remaining <ip> <bucket>` is empty, so the observation is known to describe this run.
Otherwise drop "only the final persist writes it" from the RUNBOOK, because the claim is
about who wrote the rows, and the probe measures only whether rows exist.

### Considered and not reported (fail safe or unreachable). Detail in the table.

- consolidate bucket from DONE_LOG with no rows in `$SCHEMA` on the host (a schema mismatch).
  The dispatcher DELETE runs before the COPY. Unreachable while `LNK_SCHEMA` is in the ssh
  string, and loud (coverage FATAL, pre-consolidate backup).
- The source DELETE failing after a successful COPY (`schema_consolidate.R:466-469`,
  ok = TRUE) leaves finished rows on the host, which is then held and listed for recovery.
  Re-consolidating restores identical rows, then recompute: an over-report, safe.
- The trap's ssh probes have `ConnectTimeout` only, and no command timeout. A host that
  accepts and then hangs would stall the trap before the TSV and redaction, but no data is
  lost. Not reproduced and not likely (a SELECT on the persist takes no conflicting lock).

## Full table: every place a set or host state drives an action

| # | file:line | action | property needed for safety | proxy used | concrete disagreement | direction |
|---|---|---|---|---|---|---|
| 1 | hosts.sh:176-214, run.sh:1291-1307 | completeness report, then `RUN_INCOMPLETE`, then exit 1 | every expected group built this run, or legitimately SKIPped | DB `run_uid` + `date_end` ∪ log `SKIP` | `LNK_RUN_UID` lost or the soft `date_end` UPDATE failed: the group is finished but reported missing | safe (over-reports) |
| 2 | hosts.sh:221-225, run.sh:1300, 1311-1349 | consolidate (DELETE on the dispatcher, then COPY) | the host holds a complete build of the group, from this run, in `$SCHEMA` | DB finished ∪ log `done` (known hosts only) | `done` printed but the rows are in another schema on the host: the dispatcher copy is deleted and nothing is copied | unsafe, but unreachable today and loud (coverage FATAL, backup) |
| 3 | hosts.sh:222 / run.sh:1301 | unknown host left out of consolidate | the probe route works, or consolidate would sink the others | sentinel-framed answer | none found | safe (kept) |
| 4 | run.sh:1324-1327, 1334-1338 | skip a host with an empty bucket; zero sources is its own branch | an empty bucket never reaches `schema_consolidate` | the CSV is empty | none | safe |
| 5 | hosts.sh:233-252, run.sh:1359-1361 | release (`CY_HOLD=0`), then burn | no finished build whose only copy is on the host; host settled | RC = 0 ∧ known ∧ (left ∩ fin) = ∅ | a finished group killed between persist and `done` with **zero** mapping-code rows reads partial (edge case, essentially unreachable); a source DELETE that failed after COPY leaves rows, so the host is held | safe (RC = 0 makes the state settled) |
| 6 | hosts.sh:128-149, 246-247, 400-403, 408-412 | label `partial`: "never consolidate", "rebuild them" | the group failed and will not finish | streams rows ∧ no DB / `done` / mapping-code signal *when probed* | EXIT trap mid-dispatch (SIGTERM leaves the ssh session and the remote loop alive, measured) or `CY_RUN_RC != 0`: an in-flight group is labelled partial, so the operator burns it after it finishes | **unsafe: Finding 1** |
| 7 | hosts.sh:144-146, 387-401 | label `groups` (recoverable): "consolidate these" | complete build from this run, still on the host | streams rows ∧ (DB ∨ `done` ∨ mapping-code rows) | stale mapping-code rows on the persist (`--keep-data` image or earlier rows) for a group that failed or SKIPped this run: stale or mixed rows overwrite the dispatcher | **unsafe, latent: Finding 3** (current image predates the table) |
| 8 | hosts.sh:387-393, 405 | `measured = no`: groups = candidate set | the operator must not consolidate blind | `groups_measured` column + banner | the TSV `groups` column holds already-consolidated groups | safe by instruction |
| 9 | hosts.sh:413-415, RUNBOOK | recompute instruction ("ran WITHOUT these; recompute these + upstream") | the run's recompute ran for every non-kept group | none: an assertion | consolidate failure (run.sh:1348) or coverage FATAL (run.sh:1395) exits before the recompute (run.sh:1450): consolidated groups are left un-recomputed | **unsafe: Finding 2** |
| 10 | hosts.sh:285-299, 384, run.sh:1561-1562 | `KEPT_CAUSE_N`, then exit non-zero | a host kept for cause is never an exit 0 | `CY_WHY` set ∨ `CY_HOLD=1` | none (`--keep-cyphers` alone is the only cause-free keep, and requires `CY_HOLD=0`) | safe |
| 11 | hosts.sh:304-357 | `CY_BURNED=1` | the droplet is gone | tofu state count = 0 ∧ doctl does not list it | a tofu or doctl failure: not marked, kept with a WHY | safe |
| 12 | hosts.sh:264-281, run.sh:692-699 | refuse a spin into a workspace whose droplet is up | never adopt a kept droplet | DO droplet name; doctl failure is fatal | none found | safe |
| 13 | hosts.sh:73-97 | known vs unknown | an empty answer means an empty host | both sentinels, only codes between them | a motd or noise on stdout, or ssh exit 0 with no output: unknown | safe |
| 14 | hosts.sh:111-115, 122-126 | missing `streams` / `streams_mapping_code`: unknown | wrong DB or schema never reads as empty | strict NOTABLE | none | safe |
| 15 | hosts.sh:102-104 | missing `log` table: known and empty | — | non-strict | the finished set is empty, so missing is over-reported; consolidate still takes `done` | safe |
| 16 | run.sh:1054-1056 | hold from dispatch | no exit path burns a host that may hold work | `CY_HOLD=1` before ssh | none; a spin or prep failure burns all, which is correct (nothing written) | safe |
| 17 | run.sh:1086-1091 | `CY_RUN_RC` | the session ended cleanly | ssh exit status (public IP, not Tailscale SSH) | a link drop gives 255, so the host is held | safe |
| 18 | run.sh:1383-1396 | coverage FATAL | every run group has rows on the dispatcher | any streams rows | stale earlier-run rows pass (documented; `RUN_INCOMPLETE` carries it) | safe given `RUN_INCOMPLETE` |
| 19 | run.sh:1366-1369, 1414+ | recompute over `ALL_WSGS` | every input group consolidated this run | the bucket union | failed or kept groups are recomputed on stale rows (#348, pre-existing) | pre-existing, not this branch |
| 20 | run.sh:934-935 | overlapping buckets: last writer wins | — | — | pre-existing | pre-existing |
| 21 | hosts.sh:387 (in the trap) | ssh probes inside the EXIT trap under `set -e` | the trap completes and writes the TSV | `ConnectTimeout=20`, no command timeout | a host that accepts and then hangs stalls the trap before the TSV and redaction; no data loss | note, not reproduced |

`set -e` inside the trap: every probe call sits in an `if`, a `||` or an `elif`, and
`n=$(…) || n="?"` covers pipefail. Nothing found.
