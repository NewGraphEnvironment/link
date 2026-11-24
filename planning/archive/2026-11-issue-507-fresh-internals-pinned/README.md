# #507: fresh's internals pinned by argument, at fresh 0.56.0

**Outcome:** link 0.90.0. `lnk_preflight_fresh()` checks the four fresh internals link reaches through `getFromNamespace()` against their ordered formals (leading run and defaults at run time, exact in the test). `.lnk_fresh_internal_callsites()` requires every such call to be one of them. The pin moves to fresh v0.56.0. Backlog move 18 (#504); the owner chose 0.56.0 over 0.57.0, which gets its own move.

## Measurement

- **The internals check bites.** Swapping two declared formals turns 3 tests red. A fake `getFromNamespace(".frs_fake", "fresh")` turns the set-equality test red.
- **The suite and check pass on 0.56.0.** On fresh 0.56.0 from a scratch library: 1,534 tests, 0 failed or errored. `devtools::check()` gives 0 errors, 0 warnings and 5 notes; the one note this branch caused (`utils:::`) was fixed.
- **The suite cannot run on the shared library's 0.55.1:** `load_all()` refuses it at the new floor. The plan expected only the floor's checks to fail.
- **The gate's map covers the bump.** Its reach at v0.56.0 is the same 19 fresh files, and all 7 changed files are mapped. Its pick takes 11 groups.
- **Digests:** six builds, before and after, under another session's database load. See `data-raw/logs/fresh_pin_507/README.md` and the PR for the result.

## Evidence

`data-raw/logs/fresh_pin_507/` (the builds, digests, reach and the gate's pick).

## Review

`/code-check branch` ran 4 rounds. Round 1 found that compare.R did not check the groups were built (fixed). Round 2 was clean. Round 3 found that a non-closure at an internal's name passed (fixed). Round 4 was clean. No round found a defect inside an earlier fix.
