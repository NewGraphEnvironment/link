# Findings — study_area_run.sh counts finished groups from log text (#347)

## Issue context

## Problem

`study_area_run.sh` decides which groups each cloud host finished by reading the host's run log, and the reading is wrong often enough to lose work.

`bucket_done()` matches `^\[wsg_run_one\] <WSG> … done`, anchored at the start of a line. R writes warnings to stderr in the same stream, and a warning flushed without a newline puts the marker mid-line:

```
8: In st_read.DBIObject(conn, query = query) :[wsg_run_one] FIRE done in 4.6 min (persist=fresh_default)
```

In run `20261017_004619-3f4c713b` (#246, 241 groups, `default`) that hid 18 finished groups: 2 of 50 on job1, 12 of 55 on job2, 4 of 60 on job3. Each was persisted on its host with one log row for the run_uid (checked on the hosts before burn).

The driver then does what its design says with a short count:

1. consolidates only the groups it counted;
2. **burns the cloud hosts right after consolidate**, destroying the 18 groups' only copy;
3. fails the coverage check on whatever is missing and exits before the recompute.

They were saved only because the operator paused the driver (`kill -STOP`) before the burn and the 18 were consolidated by hand.

## Proposal

- **Count completion from the database, not the log.** For each host, read `<schema>.log` for this `run_uid` (one row per finished group, with `date_completed` set) over the same ssh the consolidate uses. The log text stays for diagnosis only.
- **Never burn a host whose work is not consolidated.** When a host's finished set (from the DB) is larger than what consolidate took, keep it and say so at the end, as `--keep-cyphers` does.
- **Quieter logs:** `configs/default/overrides/cabd_blkey_xref.csv` has no final newline, so every group's log carries an `incomplete final line` warning. It is noise, not the cause.

## Acceptance

- A host log with every `done` marker mid-line still reports the host complete (fixture).
- A host with an unconsolidated finished group is not burned (mocked `cypher_down.sh`).
- Restore the anchored match and the fixture fails.


## Errors Encountered

| Error | Resolution |
|-------|------------|
