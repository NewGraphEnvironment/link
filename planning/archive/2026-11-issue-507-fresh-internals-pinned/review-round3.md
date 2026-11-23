## Checklist read
- R/lnk_preflight_fresh.R: code-check-r.md "match() treats NA...", "deparse(body(f))...", "`[[` on a named ATOMIC vector...", "`vapply(..., USE.NAMES = FALSE)`..." index lines (not full text, none apply); code-check.md Mechanisms prose skimmed ("A guard that fails toward pass", "A proxy is not the property"). 0 further headings read.
- Probed in a scratch copy (removed): `...` formal, primitive, non-function, `...`-forwarding and over-long getFromNamespace calls.

## Findings
- **[fragile]** R/lnk_preflight_fresh.R `.lnk_fresh_mismatched_internal_formals` — a non-function object at the name is skipped (`next`) and `missing_internal` tests only `exists()`, so a fresh that turns an internal into a non-function passes the pre-flight. A trailing `...` formal counts as "no default" and fails (documented intent is "trailing optional", `...` is optional). A primitive reports a mismatch with `have: ` empty. Real fresh internals are closures with fixed formals, so none of these fire today.
  - **Rule:** code-check.md "A guard that fails toward pass"
- **[fragile]** R/lnk_preflight_fresh.R `.lnk_fresh_internal_calls_in` — `match.call()` errors (uncaught) on a head-matching call with too many arguments or one containing `...`; verified. That aborts `.lnk_fresh_internal_callsites()` over the whole namespace, but only in a test, and only for code that would itself fail at run time. All 10 current `getFromNamespace(` sites in R/ are literal and well-formed, so no current breakage; the failure is loud, not silent.
  - **Rule:** none

RUNBOOK/NEWS quantifiers checked against the code: "leading formals in order, later formals have defaults", "bare, utils:: or utils:::, positional or named", "non-literal x or ns refused" all match. The NEWS "(default ...)" and "four internals" match the list. Nothing else wrong.
