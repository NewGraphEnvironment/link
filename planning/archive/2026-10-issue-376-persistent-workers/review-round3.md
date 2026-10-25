# Code-check round 3 (#376): branch 7e855364...HEAD

## Checklist read

- `index_code-check.md`: read whole. `code-check.md`: the prose of every H3 under `## Mechanisms` up to "A fixture that cannot reach the failure mode" in full, the opening of "A proxy is not the property", and "Verification that reads its own output" in full (table rows skipped); the other Mechanism H3s and every "Rules that stand alone" / Security / Spreadsheets section were read only as index lines (about 30 not read in full).
- `index_code-check-shell.md`: read whole. `code-check-shell.md`: "Over Tailscale SSH to a Mac, `ssh` exits 0 …" read in full. Headings this diff touches (`wait` with no argument, a second `trap … EXIT`, Put cleanup on the EXIT trap, A variable in a sed replacement, `grep -c`, Quoting, Heredoc precedence, A failed `cd`) were checked against the code from their index lines only; about 95 not read in full.
- `index_code-check-r.md`: read whole. `code-check-r.md`: no section read in full. `system2` / `tryCatch` / `%||%` / `on.exit` shapes were checked against the index lines; about 120 not read in full.
- `index_code-check-spatial.md`: read whole. No heading applies to this diff (no spatial code), so none read in full.

## Mechanism

**Code written for a cloud host is reused for a persistent worker, and it still assumes the host is the driver's alone, built fresh for this run, and holds only what this run put there.** A cypher's environment, database, schema, logs and name are all made by the driver for one run, so a check on what the driver *sent* covers everything that host *reads*. On a worker, every one of those has a second source the driver never sees: the machine's own files, its own tables and other sessions on it. Each round has found one place where the cypher-era check covers only the driver's own source:

- round 1: tables found by "has `watershed_group_code`", the shape of the whole schema, not link's own tables;
- round 1: redaction of the literal target only, not every name ssh writes for that host;
- round 2: values checked line by line, or checked where only some of their sources pass through.

Where the assumption reaches (checked against the code):

| reach | second source the driver does not see | state |
|---|---|---|
| the leg's environment (`remote_leg_cmd` exports) | the worker's `~/.Renviron`, which R applies **after** the environment | **open: finding 1** (only `FRESH_GIT_SHA` and `LINK_GIT_SHA` are refused) |
| redaction (`remote_redact_targets`) | ssh's own messages of the form `<user>@<host>:` | **open: finding 2** |
| tables consolidate and the drop touch | other tables in the schema | fixed in round 1 for today's tables; **finding 4**: the list is not tied to `lnk_persist_init`, so a new persist table would be skipped without notice |
| values pasted into remote strings | values whose source is outside the driver's argv | enumeration is missing `LNK_BCFP_MODEL_VERSION` (**finding 5**) and `VINTAGE_MAX_DAYS` (validated, so harmless); `ORIGIN_URL`'s check lets credentials through (**finding 3**) |
| when redaction runs | writers still running after the EXIT trap (worker prep runs beside the cypher spin) | **finding 6** |
| the code under each group | fresh is the worker's shared install; only link's clone HEAD is checked per group | not a finding: another session that reinstalls fresh mid-run changes later groups, and the per-row `fresh_sha` plus `study_area_verify.sql`'s one-pin assertion catch it after the run, not before |
| model inputs | the worker reloads no primitives, but the rows carry the dispatcher's `FWAPG_GIT_SHA`, `BCFISHOBS_GIT_SHA` and bcfp pin (stamp = what the driver sent) | not new: cyphers already load their own snapshot at prep time. The worker widens the gap, since with `--refresh-primitives` it alone models on an older load, within the vintage window |
| DB route | worker R uses `localhost:5432`, while accounting, identity and consolidate use `docker exec fresh-db` | accepted tradeoff; it fails closed (strict `host_remaining` holds the host) |
| log rows | consolidate step 5 deletes a worker's own log rows for the bucket's groups from other runs | accepted tradeoff |

## Findings

- **[severity: bug]** data-raw/study_area_remote.sh:106 (`remote_leg_cmd`), data-raw/worker_prep.sh:94-118 (`check_versions`). Every variable the worker leg exports can be overridden by the worker's `~/.Renviron`. R applies `~/.Renviron` after the process environment and replaces values already set there. Measured here: `LNK_SCHEMA=from_env LNK_HABITAT_GATE=0 R_ENVIRON_USER=<file setting both> Rscript -e 'Sys.getenv(...)'` prints `from_renviron 1`. RUNBOOK §8d states the same fact, and prep acts on it for only two variables, `FRESH_GIT_SHA` and `LINK_GIT_SHA`. The rest of the leg's exports are not checked: `LNK_SCHEMA`, `LNK_HABITAT_GATE`, `LNK_GUARD_DOWNSTREAM`, `PGOPTIONS`, `LNK_STATEMENT_TIMEOUT_MIN`, `FWAPG_GIT_SHA`, `BCFISHOBS_GIT_SHA`, `LNK_RUN_UID`, `LNK_RUN_LABEL`, `LNK_BCFP_MODEL_VERSION`, `LNK_LOAD` and `LNK_TEST_STALL_WSG`. A worker is by definition a machine other sessions use, so a dev `~/.Renviron` there is likely. What each override does:
  - `LNK_SCHEMA=fresh_default` in it makes `wsg_run_one.R` persist every group into that schema. That replaces the worker's own builds of those groups, per WSG. Accounting reads `$SCHEMA`, so the driver sees nothing and holds the host. Data on the worker is lost, and the driver only reports "held".
  - `LNK_HABITAT_GATE=1` gates at model time. RUNBOOK §3 says that gate is one-way, so the recompute cannot restore what it blanks, and the result is silently wrong habitat.
  - `FWAPG_GIT_SHA` or `BCFISHOBS_GIT_SHA` stamps another SHA on every row, which the parity gate cannot see (its `fwapg_sha` is the exported value read back).
  - `LNK_RUN_UID` writes the rows under another uid.
  - `PGOPTIONS` alone is caught by `wsg_run_one.R`'s bound check; the rest are not.

  Fix in prep, in the same `Rscript` that `check_versions` uses. Export each leg variable set to a sentinel, and refuse when `Sys.getenv()` differs. That covers `Renviron.site` and `R_ENVIRON_USER` as well as `~/.Renviron`. Take the list from the one place the leg's exports are built, so the two cannot drift.

- **[severity: security]** data-raw/study_area_remote.sh:163-164 (`remote_redact_targets`). The lookbehind `(?<![A-Za-z0-9._@-])` excludes `@`, so a host name that follows `user@` is never redacted unless the whole `user@host` is itself a redact entry. ssh's commonest failure line has exactly that shape: `<user>@<HostName>: Permission denied (publickey).` (format confirmed against github.com). With `--workers=m4box` and `ssh -G` HostName `m4box.tail1234.ts.net`, I ran the shipped `remote_redact_init` / `remote_redact_targets` on a copy, with `ssh -G` stubbed. Results:
  - `airvine@m4box.tail1234.ts.net: Permission denied (publickey).` came back unchanged;
  - `airvine@m4box: Permission denied` came back unchanged;
  - only `connect to host m4box.tail1234.ts.net port 22` was redacted.

  This is exactly what `${TS}_reach_<worker>.log` records when a worker's key is not authorised, and `--preflight-only` writes that file too. It is committed evidence in a public repo. Drop `@` from the lookbehind; replacing the longest name first already stops a bare host from eating part of `user@host`. Then add the `user@<HostName>:` line to the redaction test.

- **[severity: security]** data-raw/study_area_remote.sh:115-117 (`worker_prep_env`) and data-raw/study_area_run.sh:459-462. The origin-URL check `*[!A-Za-z0-9._:/@~+-]*` accepts userinfo, so `https://user:ghp_token@github.com/...` passes. That origin then goes to four places:
  - the remote command line, visible in the worker's `ps`;
  - the worker clone's `.git/config`, which persists on a machine other sessions use;
  - worker_prep's FATAL line, `$DIR's origin is '$got', not the run's '$ORIGIN'`, which lands in `${TS}_prep_<worker>.log`;
  - committed logs, because redaction covers worker names, not URL credentials.

  Refuse an origin that carries userinfo (`*://*@*`). Only a token-bearing origin is exposed.

- **[severity: fragile]** data-raw/schema_consolidate.R:237-258 (`consolidate_link_tables`, `consolidate_persist_core`) and data-raw/study_area_hosts.sh:434. These are two hand lists, and the test holds them equal to each other (test-study_area_hosts.R:924-927), not to what `lnk_persist_init()` creates (R/lnk_persist_init.R:370-525). Before this branch, consolidate copied any `watershed_group_code` base table, so a new persist table was carried automatically. Now a table added to `lnk_persist_init()` and not to these lists has three outcomes:
  - consolidate leaves it out with only a `NOTE`, and reports `ok`;
  - `host_release` checks only `streams`, so it lets the host go;
  - the cypher is burned with that table's rows.

  The loss is silent. Derive the list from the code that creates the tables, or add a test against `lnk_persist_init`'s set. Or treat a source table outside the list that holds rows for the bucket as an error rather than a NOTE.

- **[severity: fragile]** data-raw/study_area_remote.sh:106 and data-raw/study_area_run.sh:1112-1124. `LNK_BCFP_MODEL_VERSION` goes single-quoted into the leg string, and nothing checks it. It is missing from findings.md's "values pasted into remote strings" table. Its source is either the ledger CSV, which holds a third-party `bcfishpass.log.model_version`, or, when the ledger has no row, the operator's own environment: the `else` branch warns and leaves whatever was already exported. A `'` in it breaks the remote command the way the other values were guarded against. Today's real values (`v0.7.14-113-ga7373af`) are safe. This is pre-existing on the cypher leg; it is reported because the enumeration claims to be complete. Check it whole, like `RUN_LABEL`, or unset it in the `else` branch. `VINTAGE_MAX_DAYS` (host_vintage, :1415) is also missing from the table, but it is integer-validated.

- **[severity: fragile]** data-raw/study_area_run.sh:1600-1615 against :663 (`on_exit` → `redact_log_addresses`). Worker prep runs in background subshells beside the cypher spin, and a FATAL there (tofu or droplet_ip failure, :1633-1650) exits through the trap without waiting on `WK_PREP_PIDS`. The trap redacts and returns while `remote_run` is still appending ssh's output (including the `user@host:` lines above) to `${TS}_prep_<worker>.log`. Whatever is written after the redaction pass stays unredacted. Before this branch, the only writers left running after the trap were legs; this adds one in the run's most failure-prone phase. Wait for the prep pids in `on_exit` before redacting, or kill them (bounded wait).
