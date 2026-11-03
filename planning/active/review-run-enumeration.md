# Code check, branch 441-minimal-run: closing enumeration

Round 4 (`review-run-round4.md`) enumerated 101 claims in the lines the branch adds: 92 matched, 3 mismatched, 6 unsupported. Each of the 9 was fixed in `addc49ac` and re-checked against its source:

| # | claim (file) | fixed to | source checked |
|---|---|---|---|
| A1 | #376 answerable, #371 waits (CLAUDE.md Owed) | the five issues listed with no judgment; the operator decides | `gh issue view` bodies: #369, #371, #376 name a provincial `default` run; #374, #375 a provincial run |
| A2 | #369 summarised as idle cloud minutes (CLAUDE.md) | dropped; named only | as A1 |
| A3 | #374 answerable (CLAUDE.md) | dropped; named only | as A1 |
| B1-3 | per-host FWA spread "not different FWA data" (CLAUDE.md, research, findings) | "whether the hosts hold the same FWA rows is not measured" | m4 exact count 4,907,441 against reltuples 4,910,797 (psql, 2026-11-03) |
| C | relay "during m1's consolidate" (findings.md) | "mid-copy", one probe at about 22:36 UTC | `checks/tailscale_path.txt` |
| D | Tests pass at PRs 1 to 5 (task_plan.md) | unticked; what each PR recorded | Phase 1 line (5,232); round 4's reading of PR 5's record |
| E | "the two files", the 20:30 HEAD (progress.md) | named, labelled as read in-session | `findings.md` Phase 0 names the same two files; `checks/verify_extra.log` check 5 |

The 92 matching claims are in round 4's table. Loop ended on this enumeration after four rounds (rounds 2, 3 and 4 each found a defect inside the previous round's fix).
