# Review — round 3 (link#262, branch `262-provenance-gaps-before-217-wsg-run`)

Third pass, scoped at the **round-2 fixes only** (`round2fix.diff`). Both target files
read in full; rounds 1 and 2 read first and nothing from them is repeated.

Probes run against the live `fwapg` (`localhost:5432`), not reasoned about:

- psql exit codes for `-c` and for a multi-statement heredoc, with and without
  `ON_ERROR_STOP=1`;
- a bash simulation of the negative script's new trap/`SCRATCH_MADE` ordering under a
  failing setup heredoc;
- `study_area_verify.sql` executed against a synthetic scratch schema in three states
  (unpinned / unpinned+`unpinned_ok` / pinned control).

## Findings

- **[bug] data-raw/study_area_verify.sql:180-185 — the `unpinned_ok` escape turns a §1b
  `CASE` arm into a *conditionally sanctioned* state while leaving it above two real FAIL
  arms, so it now shadows them.** This is round-2 finding 1's mechanism, reproduced by
  round-2 finding 2's fix.

  The comment at :186 states the invariant as *"every FAIL arm is above this line; every
  NOTE below it"*. That is no longer sufficient — the invariant the ordering actually
  needs is *every arm above the line is **unconditionally** a failure*. The
  `bcfp_model_version IS NULL` arm at :180 is not: with `-v unpinned_ok=` it is a
  sanctioned, exit-0 state, and it sits above `link_dirty` (:182) and
  `fresh_sha NULL on a cypher` (:184).

  `fresh_sha` is the one that matters, because **§1b's verdict is its only reporter** —
  the DO block deliberately omits it (:363-366), correctly, since NULL is expected on the
  dispatcher. So the link#246 acceptance criterion is silently unreported on exactly the
  host class it exists for. Measured, one synthetic cypher row with `bcfp_model_version`
  NULL and `fresh_sha` NULL:

  ```
  # -v unpinned_ok='tunnel down, sanctioned'
  cypher-job1 | FAIL: bcfp_model_version NULL -- unpinned (see -v unpinned_ok=)
  NOTICE:  NOTE: 1 row(s) unpinned, accepted: tunnel down, sanctioned
  === verify: OK ===                                              rc=0

  # control: same row, bcfp_model_version set
  cypher-job1 | FAIL: fresh_sha NULL on a cypher                  rc=0
  ```

  So a 217-WSG run over an unpinned baseline exits 0, prints OK, and never tells the
  operator a cypher ran an unverifiable `fresh`. `link_dirty` is covered because the DO
  block still raises on it; `fresh_sha` has no such backstop.

  Fix: either move the bcfp arm below every unconditional FAIL arm, or stop making
  severity ordering load-bearing at all — round 2 already suggested
  `concat_ws('; ', …)` over per-condition expressions, which removes the class rather than
  the instance. A third arm added under the same unwritten rule is the third time.

- **[fragile] data-raw/study_area_verify.sql:181, :392-396, :400 — on the sanctioned path
  the script's own output contradicts itself.** The §1b verdict text is not escape-aware,
  so a run invoked with `-v unpinned_ok=` prints `FAIL: bcfp_model_version NULL` and then
  `=== verify: OK ===` with rc 0 (measured above). The final `RAISE NOTICE` also still
  claims the run is `… segmented and provenanced`, which is the one thing it is not.

  An operator (or a grep in a wrapper) scanning for `FAIL` gets a hit on a run the script
  declares good, which is the shape that trains people to ignore the word. Make the arm
  read `NOTE: bcfp_model_version NULL -- unpinned, accepted by -v unpinned_ok=` when the
  escape is in force (the value is already available as the `assert_unpinned_ok` psql
  variable after the `\gset` at :291, or via a second `\if`), and qualify the PASS text.

- **[bug] data-raw/study_area_verify_negative.sh:60-85 — the two round-2 fixes interact
  and reopen the scratch-schema leak the early trap was added to close.** Adding
  `-v ON_ERROR_STOP=1` to the shared `PSQL` array changes the setup heredoc (:72-83) from
  *continue-and-exit-0* to *abort with rc 3*. Under `set -euo pipefail` that aborts the
  script **inside the window between `CREATE SCHEMA` and `SCRATCH_MADE=1` at :85**, so the
  trap fires with `SCRATCH_MADE=0`, takes the `return 0` branch, and leaves a partially
  built `zz_lnk_verify_negative` in the database.

  Measured, with the exact ordering of the shipped script and a deliberately failing
  fourth statement:

  ```
  script rc=3
  schemata WHERE schema_name='zz_lnk_sim_neg'  ->  1     # leaked
  ```

  Before the `ON_ERROR_STOP` change this could not happen: psql exited 0, `SCRATCH_MADE=1`
  was reached, and the trap dropped the schema. The comment at :55-59 asserts the trap was
  moved early *"so `set -euo pipefail` can[not] exit with no trap registered, leaking the
  scratch schema"* — and the failure it names is precisely the one the other fix in the
  same commit made reachable. Both fixes are individually right; neither was measured
  against the other.

  Fix: set `SCRATCH_MADE=1` **before** the heredoc rather than after. The first statement
  in it is `DROP SCHEMA IF EXISTS`, so an over-eager drop is idempotent and free —
  `SCRATCH_MADE` should mean *"this script may have created it"*, not *"it definitely
  finished"*. Self-heals on the next run only because of that same `IF EXISTS`; a run that
  never happens leaves it indefinitely.

- **[fragile] data-raw/study_area_verify_negative.sh:105-159 — the new escape is the one
  control in the file with no negative test.** The script's own header argues *"a guard
  nobody has seen fail is decoration"*, and `unpinned_ok` is a control that **suppresses a
  raise**: if it were mis-wired the failure direction is silent (verify never fails on an
  unpinned run and nobody finds out). The wiring is in fact correct — I measured both
  directions, rc 3 without and rc 0 with — but that is a fact about today, established by
  hand, and there are now four assertions in the SQL and three cases in the script.

  A case 4 is cheap against the existing scratch schema:
  `UPDATE ${SCRATCH}.log SET bcfp_model_version = NULL` → expect FAIL without the flag and
  PASS with it, then restore. Two answers, which is what makes it a test.

  Related, same line of defence: the "written reason IS the control" claim at :78-80 is
  not enforced. `nullif(current_setting(…), '')` rejects an empty value and a bare
  `-v unpinned_ok` (both → NULL → raise, verified), but `-v unpinned_ok=' '` is accepted.
  The sibling it cites, `lnk_wsg_downstream_check(override=)`, rejects a bare `TRUE`.
  `nullif(btrim(…), '')` closes it, and a minimum length would close it properly.

## Checked, no finding

- **`ON_ERROR_STOP=1` is genuinely inert for the `-c` probes that share the array** — the
  comment at :38-39 is correct, measured rather than assumed. A `-c` statement against a
  missing relation returns **rc 1 either way**, so neither `RUN_UID=$(…)` (:44) nor
  `VICTIM=$(…)` (:122) changes behaviour. Both already aborted the script under `set -e`
  via the failing command substitution, and neither previously "returned empty" on error.
  `VICTIM` empty-because-the-table-is-empty still exits 0 and still reaches the explicit
  `⊘ SKIPPED` branch, which increments `fails` — the direction is unchanged and correct.
  The `cleanup()` drop is `2>/dev/null || true`, so ON_ERROR_STOP cannot make the trap
  itself fail.
- **Splitting the provenance assertion loses nothing.** Old predicate
  `link_sha IS NULL OR fwapg_sha IS NULL OR bcfp_model_version IS NULL OR link_dirty`;
  new halves are `(link_sha IS NULL OR fwapg_sha IS NULL OR link_dirty)` and
  `bcfp_model_version IS NULL`. The union is identical term-for-term — no condition is
  checked by neither half, and none is now double-counted in a way that changes the
  verdict. Both halves carry the same `run_uid = $1` scoping.
- **`n_pin` / `v_unpin` are correctly wired through `set_config` → `current_setting`.**
  All four `set_config` calls are one statement at :287-290, so `lnk.unpinned_ok` cannot be
  unset while `lnk.run_uid` is set — `current_setting('lnk.unpinned_ok')` throwing would
  require running the DO block in isolation, which is equally true of the three pre-existing
  GUCs and is not a new exposure. `\set unpinned_ok ''` → `set_config(…,'')` →
  `nullif(…,'')` → NULL → raise; a supplied reason → NOTICE. Verified end to end in both
  directions against live data. `:'unpinned_ok'` is psql-quoted, so a reason containing a
  quote is safe.
- **The EXIT trap is `set -u`-safe on every path.** `cleanup()` dereferences exactly
  `VERIFY_LOG`, `SCRATCH_MADE`, `PSQL` and `SCRATCH`; all four are assigned above the
  `trap` at :67 (`PSQL` :40, `SCRATCH` :30, the other two :60-61). The `${SCRATCH_MADE:-0}`
  default was correctly dropped along with the need for it. Both statements are in `||`
  lists so `set -e` cannot abort the handler, and the handler does not `exit`, so the
  script's status is preserved. The earlier `exit 1` at :51 precedes the trap, correctly —
  nothing exists to clean there.
- **One trap, not two.** Confirmed there is now exactly one `trap … EXIT` in the file, and
  the tempfile cleanup moved into the surviving handler rather than being dropped.
- **`R/lnk_log.R` roxygen correction is accurate.** `cypher_prep.sh:225` does run
  `snapshot_bcfp.sh` and its `lnk_baseline_append()` is not gated on `--with-bcfp-views`,
  so the retraction is right and the restated rationale (tier 0 exists for *agreement
  across hosts*, since the compare runs on the dispatcher against the dispatcher's
  `fresh.streams_vw_bcfp`) matches what `preflight_local()` actually does. Comment-only;
  no behaviour touched.
