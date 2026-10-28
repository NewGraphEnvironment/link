## Outcome

`default` now breaks streams at a fish observation only at each species' farthest-upstream record on each stream line (`pipeline: observation_breaks: top_per_species`); the `bcfishpass` bundle keeps every observation (`all`, the value when absent). The validator's docs were corrected for observations that no longer start a segment. The main thing learned overturns the issue's premise: the access walk counts a record within 1 m of a segment's start as upstream, so a species' own top break never changes its own code 2. A species turns to 1 at the first cut more than 1 m above its top, and kept tops serve as that cut for species recorded below them. A smaller, near-exact set exists and is not built. It goes back to the operator. Six code-check rounds also turned the acceptance into one exact rule. A segment's codes depend only on where it starts, and the walk's tests are monotone in that start, so access can move only in the direction a start moved. Record: `research/observation_breaks.md`; mechanics: RUNBOOK §2c.

## Measurement

Five groups (LKEL, BULK, UPCE, PARS, ELKR) built at main and at the branch on m4's local fwapg, BEFORE and AFTER of each run back to back:

- **Segments** fall 0.7 to 3.6 % (PARS 46,341 → 46,004; ELKR 40,027 → 38,601), exactly the count `cuts.sql` predicted before building; observation positions fall to 17 to 59 %.
- **Minutes** do not move beyond noise (model −4 to +6 %, recompute within 5 s). ELKR's first BEFORE build (6.67 min) did not reproduce on a reverse-order repeat (3.80 / 3.92 min).
- **Sampling bias closes.** At UPCE's FISS sites, sites with fish against sites without sat on median segments of 98 and 195 m before, and 411 and 385 m after.
- **Access moves only by the direction rule** (`n_violation` 0 on every piece): 1 → 2 on 6.1 km, all at species' tops; no blocked/open or 2 → 1 change.
- **`bcfishpass` builds of BULK and PARS** have the same segment counts, break census and parity values as #326 round 2. **The validator** scores the same records.

Wrong turns kept in `findings.md` and `review-round{1..6}.md`: the issue's "top is where code 2 changes" premise (round 2), a "never 2 to 1" claim broken by released breaks (round 3), a near-break classifier that could not fail (round 4), and a tributary-mouth case accepted without probing, which FWA cannot hold (round 5). BULK's BEFORE build stalled 44.6 min once in fresh's near-river walk and was cancelled; the retry took 5.1 min.

## Evidence

`data-raw/logs/observation_breaks_396/` (its README indexes it).

## Owed

- Every persisted `default` group re-segments again at the next provincial run (stacks on #326's owed re-model, #377's runs row); the `bcfishpass` schema does not
- The operator's call: keep `top_per_species` or move `default` to the near-exact set (per species, the lowest record of any species more than 1 m above its raw top; `exact_set.csv`)

Closed by: PR (opened from this branch)
