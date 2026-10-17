# Plan review — #347 (Plan agent, 2026-10-17, delivered as reply text; written here by the parent)

Summary of findings and disposition. Claims checked against code before acting.

| id | finding | verified | disposition |
|---|---|---|---|
| B1 | A "known" DB probe can undercount: `.lnk_log_run_finish()` is soft (R/lnk_log.R:1007-1020) so a persisted group can keep `date_end` NULL; a lost `LNK_RUN_UID` gives NULL run_uid on every row. Release on DB alone would burn work | yes | bucket = DB ∪ log-done (done prints only after persist); release measured after consolidate by rows left in `<schema>.streams` for the host's groups, which needs no run_uid |
| G1 | "Consolidated" assumed, not measured; consolidate DELETEs copied rows on the source (schema_consolidate.R:420-450) | yes | post-consolidate probe of what remains on the host |
| G2 | ssh session drop may leave the remote loop running | plausible | hold any host whose dispatch session exited non-zero |
| G3 | kept banner must come from the trap; explicit exit needed | yes | trap prints via burn_cyphers; end block exits 1 |
| G4 | burn verification limited to burned hosts | — | already by droplet name |
| G5 | `CY_BURNED` set even when cypher_down failed | yes | set only when tofu state is 0; failed burn listed as kept |
| G6 | TSV lacks run_uid, schema, group list, ip recipe | yes | added |
| G7 | "known, empty" has two causes | yes | covered by B1's fix |
| O1 | arrays the trap reads must be declared top-level before the trap | yes | already; comment added |
| O2 | preflight must run before CYPHERS_UP=1 and fail closed | yes | preflight_local precedes the spin; doctl failure already fails |
| O3 | red-first shown by mutation | yes | findings say so |
| A1 | default `cypher` droplet warns every run | yes | not warned unless `default` is a workspace |
| A2 | --keep-cyphers exit status | — | does not count as failure; still reported |
| A3 | unknown host in consolidate sinks the others | plausible | unknown hosts excluded from consolidate, kept |
| S1 | CSV newline safe from sync | yes | — |
| S2 | consolidate deletes dispatcher's prior log rows per group | not checked | follow-up draft |
| AC1 | mutation criterion wording | — | PR says "count from the log with main's sed" |
| AC2 | ssh stub discards command/stdin | yes | stub records both; test asserts route and SELECT; route checked live through local docker |
| AC3 | fail, not skip, without bash >= 4 when the lib exists | — | done |
