# Code-check round 2 — branch 347-study-area-run-sh-counts-finished-groups (HEAD 8de0aeda)

## Findings

- **[severity: bug]** data-raw/study_area_hosts.sh:192-210 (host_release), :335-372 (hosts_kept_report);
  data-raw/study_area_run.sh:1571-1574; RUNBOOK.md:1242-1250 — `groups` (measured) treats "has
  `<schema>.streams` rows" as "unconsolidated finished work". It also covers a group that FAILED on the
  host, and the recovery text says to consolidate it.
  `lnk_pipeline_run()` writes streams, habitat and barriers in a pre-persist (R/lnk_pipeline_run.R:240)
  before access and mapping_code. It writes streams_access and streams_mapping_code only in the final
  persist (:315). Persist is not transactional across tables (R/lnk_pipeline_persist.R).
  - **What happens.** A group that errors anywhere after the pre-persist leaves streams rows on the
    host, with no `date_end` and no `done` marker. consolidate correctly leaves it out of the bucket.
    host_release then finds its streams rows and keeps the host with "streams rows left after
    consolidate". hosts_kept_report lists the group under `groups` with `groups_measured = yes`.
  - **What the operator is told.** The banner, the INCOMPLETE block and the RUNBOOK all say
    "consolidate ONLY groups still on the host (groups_measured = yes)".
  - **The consequence.** schema_consolidate DELETEs the dispatcher's rows for that group in every
    table, then copies a partial group. The dispatcher's complete earlier-run copy is lost, including
    its streams_access and streams_mapping_code: the host has no rows for those tables, so nothing
    replaces them. This is the round-1 defect one axis over. Round 1 kept already-consolidated groups
    out of the "recover these" list; this lets never-finished groups into it.
  - **Where it bites hardest.** The same mix appears in the abort path. After a source's COPY fails
    mid-way, `groups` mixes finished groups, which must be recovered because the dispatcher's copy was
    already deleted, with partial ones, which must not be. Nothing in the TSV tells them apart.
  - **Spend.** Any host with one post-pre-persist failure is also never released, so it is billed
    until an operator acts on that instruction.
  - **Reproduced** with stubbed ssh and the lib as is. Bucket AAAA,BBBB; AAAA closed and `done`;
    BBBB failed and still has streams rows. The result is consolidate bucket AAAA and the host KEPT,
    and the TSV reads `groups = BBBB`, `groups_measured = yes`, while the recovery text says to
    consolidate it.
  - **Fix direction.** Split the measured set by finished status: remaining ∩ (finished ∪ log done)
    is recoverable, and remaining \ (finished ∪ log done) is partial or failed (or still running on a
    session that exited non-zero) and must not be consolidated. Record the two as separate columns,
    and decide whether partial-only leftovers should hold the host at all.

- **[severity: fragile]** data-raw/study_area_run.sh:1571-1576, data-raw/study_area_hosts.sh:367-371,
  RUNBOOK.md:1242-1246 — the recovery steps for a kept host stop at consolidate and burn. By then the
  run's post-consolidate recompute has already run over ALL_WSGS without the kept host's groups.
  - **Recovered groups are not recomputed.** They arrive with the host's per-host
    streams_access / streams_mapping_code, built against an incomplete barrier set.
  - **Their neighbours were recomputed against stale data.** They were recomputed against stale or
    absent barriers for the recovered groups.
  - **Nothing says so.** The driver's own comment calls this the "silently WRONG" failure mode, and
    `log_recompute` reports the run's recompute as complete. A recovery that does not end with a
    recompute (`wsg_recompute_one.R` / the pool, `merge = TRUE`) over the recovered groups and
    everything downstream of them ships per-host access with no signal.
