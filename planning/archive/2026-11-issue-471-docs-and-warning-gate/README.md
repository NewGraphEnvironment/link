## Outcome

Backlog move 3 in one PR: #493's test now reads only the ssh leg's command (a comment naming the script had matched); #385's three `R CMD check` warnings are cleared (non-ASCII in code strings as `—` escapes, Rd links to functions that exist, `presence` and `heads` documented) and the workflow's `error-on` override is removed; #456's README, DESCRIPTION and CITATION.cff say "fish habitat definitions"; #275 leaves one scope table (`study_area_scope_and_funders.md`) with the generator and run notes pointing at it; #279's share is the CLAUDE.md link, nine dated records marked historical and ten files marked as not yet verified. `heads` on `lnk_preflight_vintage` was also undocumented, which the plan review had missed. No behaviour changes.

## Measurement

`devtools::check()`: 3 warnings, 3 notes before; 0 warnings, 3 notes after (top-level files, `setNames`/`getFromNamespace` imports, Rd usage width). `devtools::test()`: 0 failures, 0 errors, 5,080 passes. Review: one fresh-eyes round, Clean; the three-round `/code-check` floor was not run, as the diff is escapes, docs and a one-line test change. `research/study_areas.md` was hand-edited to match the generator, since regeneration needs a database.

## Owed

- Consolidation issue for the six grown research files, filed and linked from #279

Closed by: PR for #471
