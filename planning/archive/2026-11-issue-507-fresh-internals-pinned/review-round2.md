## Checklist read
Not read in full (budget); judged by the index headings. R/lnk_preflight_fresh.R and its test: code-check-r.md (match.call/formals handling, `nzchar`/empty-symbol, `identical` on reader results, `[[` on atomic), none applied. compare.R/digest.R/run.sh: code-check.md "A guard that fails toward pass", "A wrapper's exit is not the work", code-check-shell.md "a && b || c" (not present). Not read: remaining ~all headings (not tool-relevant).

Ran test-lnk_preflight_fresh.R database-free against the fresh 0.56.0 library: 70 pass, 0 fail. Internal signatures match /tmp/link507/fresh_0560/R. The four getFromNamespace callsites in R/ match the pinned set.

## Clean
No issues found. Round 1 fix in compare.R verified: exit-0 row required per step x config x group, digest group sets equal to builds, and a retried group's last row decides. (Minor, not flagged: digest.R's token read would show two rows for a group if a retry left a closed log row in a prior try; both steps would need to differ, and the compare would then fail loud.)
