# #409: adopt fresh v0.46.0, the walk prefilter in the recompute

## Outcome

link now pins fresh v0.46.0 (floor and `Remotes:`), which carries fresh#272's scoped downstream walk and fresh#242's group-matched connectivity passes. No link code changed: link already passed `aoi` on every downstream walk, and a new test holds it to that, beside one holding the fresh floor to the `Remotes:` tag. Outputs did not move, recompute or model time. The plan review found the risk worth checking first: fresh 0.45.0's new tiebreak on the feature id could move the two values link reads from an array's first element. A read-only count showed no two anthropogenic features share a position on the dispatcher's build, so `dam_dnstr_ind` cannot move there. Five code-check rounds found no defect in package code and two in the measurement driver (a refused run's log overwritten on resume; a `RESUME` that matched nothing reported ALLDONE); every other finding was a documentation claim wider than the record (the numbers held; the clauses interpreting them and the populations they named did not). The loop ended on an enumeration of every claim against its producer. The research write-up is `research/recompute_cost.md`, "Measured since fresh#272".

## Measurement

Each group's whole recompute on the dispatcher's 2026-10-23 build, run alternately under fresh v0.44.0 and v0.46.0, serial, each version's fastest run: CHWK 686 → 75 s, LSKE 580 → 178, LKEL 111 → 46, SALR 42 → 23 (77 % less over the four); SETN 1,424 → 804 s (its second pair ran after the PR opened, 06:10 to 06:53 UTC; 60 % less over all five). 172 of 172 table digests unchanged; 48 of 48 walks the same features (order changed in 9 natural walks, which link reduces to membership). ADMS, NATR and ELKR built twice at model time: 25 of 25 non-empty group-tables identical. Under 0.46.0 the walks are 41 to 83 % of a run (66 to 96 % before), and every PSCIS and dam walk got slower by 1.0 to 3.9 s, with the cause unmeasured; fresh's own temp-table timing (0.07 to 0.7 s) is less than that. This is below #261's 6.3× to 24.6× server-side estimate for the walk alone, and is what #394's "walk each set once" addresses. Wrong turns kept in `findings.md`: a scratch library that silently held 25 dependency copies (sf and s2 at newer versions); two refused runs (autovacuum's lock, another session's walks) and a driver that then overwrote a refusal log; a cause stated for the per-call rise that nothing measured, corrected over two review rounds.

## Evidence

`data-raw/logs/prefilter_409/` (its README indexes scripts and outputs: `recompute/`, `model/`, `ties_*`, `reach.md`, `pick_only.md`).

## Owed

- Re-prep the cloud hosts and the persistent worker for fresh v0.46.0 (`--auto-install`, RUNBOOK §8d) before the next dispatch
- Run the full pre-run gate (`pretest_run.sh --config=default --schema=fresh_default`) at the new pin before the next provincial run; the bump voids the 2026-10-29 record
- #394 is unblocked: measure it on top of this release
- The next provincial run's `log_recompute` minutes against 2026-10-23's, at `-j8` on the dispatcher (G7)

Follow-up filed: #411 (`lnk_access()`'s own scoped streams table). Not done here: #410's body still describes the mapping-code walks as province-wide.

Closed by: PR (opened from branch `409-adopt-fresh-v0-46-0-the-walk-prefilter-f`), release v0.69.6 (`5d320bae`)
