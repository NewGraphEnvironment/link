## Outcome

Two fixes before the next provincial `default` run (#361), released as link 0.68.0. **#277:** the PSCIS-to-modelled-crossing pick tied because link had skipped a bcfishpass step (keep the nearest instream modelled crossing per PSCIS per blue line, before the pick); the plan first assumed bcfishpass tied the same way, and the Plan review disproved it. Ported, with id tie-breaks. Review then kept finding the same mechanism elsewhere: **a statement that keeps one of several joined rows without naming which**, usually after a measure-range join that repeats a position where two FWA segments overlap by ~1 mm. Barrier ids, both nearest-stream snaps, `lnk_match()`, the gradient ltree enrich, the placeholder numbering and the lift count were each fixed; the review loop ended on an enumeration of every such construct in `R/` (findings.md), because rounds 2 and 4 each found a defect inside an earlier fix. **#244:** `default` sets `pipeline: cabd_additions_barriers`, so the five US dam placeholders become barriers; the `bcfishpass` bundle keeps bcfishpass's behaviour (bcfishpass never makes them crossings). **#345:** the golden dams test pins ADMS's 7 dam ids. **#316** was measured before the plan and left out (comment on #316). Mechanics in RUNBOOK §2a, §2b, §5 and §8c.

## Measurement

- The pick built twice minutes apart: at 0.67.0, 464 of 17,377 PSCIS picked a different modelled crossing; at the branch, 0. Against 0.67.0, 656 change modelled crossing and 56 change stream (toward bcfishpass's picks).
- ADMS and ELKR built twice at the branch: every persisted table identical, barriers included.
- Main against branch on ADMS, ELKR and NATR: accessible km identical; spawning or rearing moves by at most 0.094 km per species (ADMS CH spawning +0.088; NATR GR rearing +0.094).
- Placeholders as barriers, LARL / KETL / SKGT, knob on against off: segments, habitat and per-species access identical; 19,065 mapping codes go `NONE` to `DAM` in the second token only (KETL RB 6,778, WCT 5,358; LARL BT 1,000, RB 1,038, WCT 978; SKGT BT 1,931, RB 1,982).
- Overlap positions province-wide (`fresh_default`): 3,513 gradient positions match two segments, 1,530 with different localcodes (all took the lower segment so far; the new statement gives identical codes on 141,810 ADMS / BULK / ELKR positions); one falls point (USIK) joins two segments.
- Wrong turns kept: the plan's "bcfishpass ties the same way" (disproved by the Plan review); a KETL access difference between knob-on and knob-off that came from my harness recomputing KETL before LARL existed, not from the knob; a harness race on `CREATE SCHEMA IF NOT EXISTS` between two build lanes.

## Evidence

`data-raw/logs/provincial_prep_367/*` (README there). Reviews: `review-plan.md`, `review-round*.md` in this directory.

## Owed

- Tag v0.68.0 (`/gh-pr-merge`, on your word)
- Update #361's "Before the run" checklist (v0.68.0, schema rename, `--refresh-primitives`); close #339
- Draft, not post, a note to bcfishpass on its `load_crossings.sql` dropping the placeholders, if its `load_dams.sql` comment shows they were meant to count

Closed by: PR (this branch, `367-before-the-next-provincial-default-run-a`)
