# Two barrier-rule sets on #321's parity groups (link#341)

**Measured:** 2026-11-24 on m1's local fwapg, on the AFTER-386 `bcfishpass` proof build (`fresh_386_after_bcfp`, its kept working `crossings`). **Produced by:** `Rscript compare.R fresh_386_after_bcfp w386ab_ bcfishpass <out> ADMS,BULK`.

Rule sets (`rules_*.csv`):

- **province**: the built-in rule, the source's own status.
- **added**: the province's result, or a PSCIS assessment with outlet drop above 0.6 m, or slope times length above 120 (the `high` thresholds `lnk_thresholds()` shipped until 0.93.0).
- **in_place**: for a PSCIS crossing the two measured rules, keeping the province's result only where both measurements are null; every other crossing keeps its status.

## Crossings that change class, against the province (`classes.csv`)

| group | set | PSCIS to barrier | PSCIS to not a barrier | PSCIS crossings | modelled and CABD |
|---|---|---|---|---|---|
| ADMS | added | 3 | 0 | 69 | unchanged |
| ADMS | in_place | 3 | 27 | 69 | unchanged |
| BULK | added | 1 | 0 | 1,564 | unchanged |
| BULK | in_place | 1 | 779 | 1,564 | unchanged |

Assessed crossings with neither measurement: ADMS 20 of 69, BULK 566 of 1,564 (`unmeasured_*.csv`). Measured against these two thresholds, most crossings PSCIS calls a barrier or potential barrier are neither: the province's result reads more than outlet drop and slope.

## Below-barrier km per crossing (`km_below_barriers.csv`) and marks (`marks.csv`)

- **added** moves the below-barrier totals of 2 crossings per species in each group (ADMS BT 3.6 km spawning, 5.2 rearing; BULK 1.7 km for most species). The anthropogenic mark moves on 0 of ADMS's 15,787 segments and 10 of BULK's 42,988; the PSCIS mark on 243 and 11.
- **in_place** moves BULK's totals for 185 to 290 crossings per species (BT 2,784 km spawning and 4,885 km rearing moved, summed over crossings) and the anthropogenic mark on 3,602 segments (PSCIS 7,449). ADMS: anthropogenic 43, PSCIS 658.

## Does a rule change need a re-model? (`timing.csv`, `unmeasured_*.csv`)

Not a full one. Per group, the totals take one `lnk_aggregate()` call (ADMS 11 to 13 s, BULK 20 to 24 s) and the marks one `lnk_access()` pass (ADMS 6 to 8 s, BULK 28 to 30 s) over the build's persisted streams and habitat. But `crossings` is not persisted, and the persisted `barriers` hold only the crossings today's rules select: the added set selects 3 ADMS and 1 BULK main-line crossings the persisted table does not hold. So a rule that widens the set re-runs the crossings phase for each group, then the recompute; a rule that only narrows it can be applied to the persisted rows.
