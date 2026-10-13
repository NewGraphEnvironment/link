# Code-check round 1 — branch 328-build-dunc-into-fresh-default (base 2edc4105)

Reviewer: subagent, 2026-10-12. Read-only SELECTs against local fwapg, plus one read-only
`lnk_wsg_downstream_check(DUNC)` call from a scratchpad script.

## What was checked and holds

- **README / verify.txt / DB agree** on every figure: 63,067 segments; 3,493.0 km order >= 2 on all three
  sides; fresh 26,827; run window 15:31:35–15:33:45 UTC (2.17 min); run_id, config_hash, link `8215d2d`
  clean, fresh `e247ca1`, fwapg `f9718cb` vs `e6e1eb0`; the six FWA fingerprints (fwa_stream_networks_sp
  4,907,804 rows / 10,287,677,440 bytes); 19 checks (7 + 1 + 1 + 2 + 3 + 3 + 2); parity table
  (BT +2.0 / +0.9 / +2.2, WCT +1.3 / +0.4 / +17.0).
- **Guard claim**: re-running the guard gives `pass`, six dams (Brilliant, Corra Linn, Lower/Upper
  Bonnington, South Slocan Dam and Generating Station), all in KOTL.
- **Headwater claim**: no other group's outlet (fresh `wsg_outlet.csv`) has a wscode under DUNC's
  `300.625474.096683`.
- **LARL downstream of DUNC**: LARL's outlet is on the Columbia (`300.600588`) below the Kootenay
  confluence (`300.625474`), so "KOTL, LARL" as the downstream groups holds.
- **Log rows** (CLAUDE.md): exactly PINE (2026-08-06, link 0.44.3), KOTL / LARL / SLOC (2026-08-27,
  link 0.45.1, fresh 0.33.0; KOTL / SLOC `322389a` clean, hash `3cfde7…`; LARL `8c8c29b` dirty, `44e452…`)
  and DUNC. 56 groups in `fresh_default`; 98 / 59 / 39 in `fresh.streams` / `streams_access` / `log`.
- **fwapg range** `e6e1eb0..f9718cb`: extras, docs, Dockerfile and one `load.sh` URL change (same
  object-store source). "Unrelated commits" holds.
- **verify.R SQL**: every persist table has `PRIMARY KEY (id_segment, watershed_group_code)`, so a
  count-equality inner join on the full PK does prove one row per segment. The `streams_access` /
  `streams_mapping_code` join pins both sides' group to DUNC, so it is a full-PK join too. NA paths in
  `check()` fail (isTRUE), not pass. The `fr == 0` check is labelled as fresh.log only, which is what it tests.
- **Infra identity**: no IPs, ssh aliases or tunnel ports. `:5432` and the `m1-` run_id prefix already
  appear throughout the repo; the `/Users/airvine/...` path in run.log appears in 224 committed logs.

## Findings

- **[fragile / doc]** CLAUDE.md:20 ("49 of the 56 have under 1.5 segments per FWA line … only PARS, PINE
  and the four Columbia groups are dense") — 49 + 6 = 55. CHWK is at 1.54 (8,866 / 5,766), so it is in
  neither group, and a reader who reconciles the counts finds one missing. HARR is 1.497, so the 49 is
  right at exactly 1.5. Fix: "50 of the 56 have under 1.6" (CHWK 1.54 is the highest sparse group; the
  lowest dense one is PARS at 2.62), or name CHWK.

- **[doc, PWF integrity]** planning/active/task_plan.md, Phase 2 fourth box — ticked `[x]`, but its text
  says the log row carries "clean link_sha = HEAD … run_uid". `run_uid` is NULL (accepted by design), and
  verify.R checks link_sha against the build commit `8215d2d`, not HEAD. The ticked box claims two things
  that did not happen. Reword it to match what was checked.

- **[doc]** planning/active/task_plan.md, "Decided" paragraph — gives KOTL, LARL and SLOC all as "link
  `322389a`, … config_hash `3cfde7…`". LARL is `8c8c29b` (dirty), hash `44e452…`. README and findings.md
  have it right; only the plan frame is wrong. It goes into the archive as written unless fixed.

No bugs or security issues in verify.R, README.md or the CLAUDE.md figures beyond the arithmetic gap above.
