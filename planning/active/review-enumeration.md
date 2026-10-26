# Code-check — the enumeration that ends the loop (#374, 2026-10-26)

Rounds 2 and 3 each found a defect inside the previous round's fix, so by `/code-check`'s stopping rule only an enumeration ends the loop.

**Mechanism** (round 3's statement, adopted): a check infers a fact (a group landed, a job started, a gate ran, a comparison happened) from a record that has a second writer, a second clock, or a second reason to be empty. When the record is absent or does not parse, the check takes the safe-looking answer.

**Candidate set:** every line the branch added that turns a missing, failing or unparseable value into a decision. It was listed mechanically with `git diff -U0 b24778b9...HEAD` over the six code files, grepping for `|| true|return|<var>=`, `2>/dev/null`, `is.na`/`is.nan`, `-e`/`-s`/`-r`, `file.exists`, zero-length and `nrow` tests, `tryCatch`, `character(0)`, `NA_real_` and `${VAR:-`. That gave 62 hits; each is judged below by group.

| site | absent / failing → | verdict |
|---|---|---|
| `recompute_landed`: unreadable file, header, run_uid, `.hosts_query` | `return 1` | fails closed (mutants) |
| `recompute_landed`: no state file | no remote group landed | fails closed (`in_flight` is written before a copy) |
| `recompute_ready`: unreadable file, header, bad code | `return 1` | fails closed (mutants) |
| `recompute_ready`: dependency outside the run or SKIP | landed | by design: no row this run writes |
| scheduler: `mkdir` / first append fails | `return 1`, nothing launched | fallback pool runs everything |
| scheduler: a later append fails | stop, `return 4` | fallback + audit `start_unrecorded` (test) |
| scheduler: poll fails (`landed=""`, `ready=""`) | nothing launched that poll | fails closed |
| scheduler: **`recompute_order` prints nothing** | **final set never drained: hang** | **found by this enumeration; now falls back to the queue unordered (test + mutant)** |
| scheduler: final file malformed | `return 1` | fallback pool |
| scheduler: stop file / parent gone | stop launching, wait own jobs | by design |
| finish: final write fails | stop file → scheduler stops | fallback pool |
| finish: `first`, `n_early`, `cp` of the launch record | blank / 0 / no copy | display and evidence only; the audit reads `RC_DIR` |
| finish: fallback pid wait, `done_rc` fails | `done_rc=""` → relaunch all | more work, never less; recompute of settled access is idempotent |
| finish: `fallback.txt` write fails | audit sees no fallback | audit exits 2 (fails closed) |
| finish: empty coverage with early launches | `RUN_INCOMPLETE=1` | fails closed |
| run: trap `touch` stop fails | scheduler keeps polling | it exits when the parent is gone |
| run: dependency map exit / header / zero rows | FATAL before dispatch | fails closed |
| run: `LNK_LOG=0` set | FATAL before dispatch | fails closed (round 3) |
| audit: any R error | exit 2 | fails closed |
| audit: no state file / launch file / fallback file | empty | each yields `EARLY` or `start_unrecorded` where a start is unproven (tested) |
| audit: dependency with no `ok` row | never landed | `EARLY` if its dependant started early, else final set by design (tested) |
| audit: `ok` row with unparseable time | `landing_unparsed` | exit 2 (tested) |
| audit: no start recorded | fallback → `after_final`; never launched and no row → `no_recompute_row`; else `start_unrecorded` | exit 2 unless nothing ran or it ran after every landing (tested, incl. `LNK_LOG=0`) |
| audit: overlap (group on dispatcher and a remote) | dispatcher arm skipped | remote arm binds: overlap consolidated after the dispatcher leg |
| deps: FWA returns nothing | stop | fails closed |
| view key: catalog unreadable / no comment / def NA | replace (no key) | a lock taken again, never a stale view (test + mutant) |
| `digest_test.R`, `ab_compare.R`: nothing compared; negative control not discriminating | stop / non-zero | fails closed |

Nothing in the set sits above its source of truth after the round-3 fixes and the ordering fallback. Loop ended by enumeration (3 reviewer rounds).
