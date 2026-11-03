# Code check, branch 441-minimal-run, round 2

## Checklist read

- code-check.md: the prose of all 14 H3s under `## Mechanisms` (table rows skipped). The 23 headings under "Rules that stand alone", "Security" and "Spreadsheets and PDFs" by index line only.
- code-check-shell.md: in full "Empty arrays under `set -u` on bash 3.2", "`&` binds to the whole `&&` list, so assignments never reach the parent", "Over Tailscale SSH to a Mac, `ssh` exits 0 whatever the remote command returned", "A failed `cd` lets every later command run in the directory you were already in". The other 66 by index line only.
- code-check-r.md (116) and code-check-spatial.md (94): index only, since the branch changes no R or spatial code.
- Not read in full: 23 + 66 + 116 + 94 = 299 headings.

## What was checked (no finding)

- `launch.sh`: the 241 focal groups (48/49/48/48/48) match `buckets.md` and the run's resolved buckets, with no duplicates. `cd` is guarded and the `${BCFISHOBS_DIR:?}` guard is fine. The empty `pre` array is safe under bash 5.1, which the header requires.
- Against `phases.tsv`, the checks, `consolidate_*.log`, `calibrate.log`, `host_speeds*.tsv`, `plan.tsv` and the database: legs 87.4/103.3/159.8/168.1/183.0 (sum 701.6), ratio 0.693, group minutes 690.2 (median 2.32; QUES 20.9 job3, MORK 12.8 job2, BULK 10.7 job1), recompute 241 rows, 126.8 summed, median 0.41, HOMA 4.98, 21:51:33 to 00:15:29, tails 29.4 and 12.3 min, critical path 228.2, prep 10.0, cloud host-hours about 9.86, consolidates 47.6/13.1/13.3/12.8, barriers 562.2 s and streams 2,093.3 s, 4,987,761 segments over 241 groups, 19 GB, one link sha 193cb8aa (0.78.1, clean) and one fresh sha 245c8d8d over 5 hosts, tokens on 241 rows, gate at 24b2cbb3 with 11 picks, no TIMEOUT or halt in any host log, the 34 `notes` all link#227 warn-mode guard notes. All match.
- The droplets' ssh address is `tofu output droplet_ip` = `module.droplet.ipv4_address` (public), so "cloud hosts are reached at their droplets' public addresses" holds. Cloud streams copied at about 5.2 MB/s (job1 1.87 GB in 361 s), which supports attributing m1's slow copy to its path.
- Public-repo hygiene: in every added or modified file, no IPv4 other than `0.0.0.0/0` in tofu plans, no IPv6 or tailnet address, no real `user@host` (only `cypher@<host>`, `<worker1>`, `<endpoint>`), and no token or key pattern. The regex matched its positive controls.

## Findings

- **[severity: fragile]** CLAUDE.md:21. A defect inside round 1's fix. The new fact reads "**During the run** m4 reached m1 through a Tailscale relay … so m1's consolidate ran at about 700 KB/s". The evidence is one probe, `~22:36 UTC`, mid-copy (`checks/tailscale_path.txt`), against a run from 20:33 to 00:21 UTC, and the path went direct by 00:31. "During the run" widens the one sample to the whole run, which is what round 1 asked to stop. The research section ("At about 22:36 UTC, mid-copy") and the RUNBOOK ("mid-copy") were narrowed; this line was not. Two more points. The 22:36 entry in `tailscale_path.txt` was written after the fact: the file was created in e1f9c06b at 00:31 UTC, with an approximate time, so it transcribes the probe rather than capturing it. And round 1's reviewer pinged m1 at 00:30 UTC, a minute before the "after the run" probe, which may itself have driven the path direct (round 1 said so). Suggested wording: "m4 reached m1 through a relay at ~22:36 UTC, mid-copy (one probe)".
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** CLAUDE.md:21, RUNBOOK.md:2611, research/study_area_run.md:334, planning/active/findings.md:100, planning/active/progress.md:42. "About 700 KB/s" is not derived from anything committed, and it disagrees with the bytes. The research sentence pairs it with "(`barriers` 9.4 min, `streams` 34.9 min)" as if derived from them. The row text of m1's 49 groups in `fresh_default_minimal` (sum of `octet_length(row::text)`) is 1,826,786,754 bytes for streams and 309,380,089 for barriers. Over 2,093.3 s and 562.2 s that is about 870 KB/s and 550 KB/s, or about 805 KB/s for the two together (round 1 measured the same). The number is published in five places. Either give the measured figures (about 0.55 to 0.87 MB/s) or drop the rate and keep the times.
  - **Rule:** code-check.md "One fact derived twice"

- **[severity: fragile]** CLAUDE.md:18, the new block's **Owed**. It omits open items that earlier blocks assign to "the next provincial run", which this run was:
  - #376 (OPEN): acceptance 2 is "a provincial run with a worker, longest leg within 10 % of its packing estimate", plus the worker's `--host-speeds` value. This run is that measurement: longest leg job1 183.0 against 202.3 (9.5 % under), worker leg 87.4 against 202.8. It is neither recorded nor listed as owed.
  - #259's "re-run `packing_259/fit.R` on post-#326 minutes" and #261's "re-run `predictors.R` / `correlations.R` on the next provincial build". Neither was run on this branch, and neither is listed. `research/study_area_run.md:301` still says "The next provincial run re-fits both (`fit.R` on its rows)". This run is the next provincial run, and it did not.
  - #446 (OPEN) appears only in the renamed "before launch" block's "Owed before launch" list, which now reads as finished.
  - "The calibrator's second and third runs (#163)": #163 is CLOSED, as is #259, which folded it in. So the owed item points at no open issue.
  - **Rule:** code-check.md "Written data outlives the fix" (enumerate every artifact quoting a derived value and its owed follow-ups). The nearest exact heading is "Documentation Staleness".

- **[severity: fragile]** research/study_area_run.md:319 and 326. Round 1's fix put "the plan's 1,012" in the parenthetical, but the lead still says "0.69 of **the history's** minutes" and the table cell still reads "1,012 (history)". Of the 1,012, 7.4 min is KTSU and OKAN at the median: `plan.tsv` has empty `minutes` and `measured_by` for both, and the history weights alone sum to 1,004.4. The ratio and the table are against the plan, not the history. The difference is small (0.693 against 0.698), but the label is wrong in the sentence the fix was meant to correct.
  - **Rule:** none
