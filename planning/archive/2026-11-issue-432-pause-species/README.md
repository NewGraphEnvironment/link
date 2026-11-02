# #432: pause a species in a bundle's runs (KO and RB in `default`), folding in #433

## Outcome

A bundle file, `species_modelled.csv`, lists every rules species `t` or `f`, and `lnk_config()` leaves the `f` species out of `cfg$species` (into `cfg$species_paused`). `default` pauses KO (presence column never sourced) and RB (records do not separate rainbow trout from steelhead); `default_tuned` inherits it; `acc-v5` replaces `acc-v4`. At the gate the operator chose "off means off" for #433, judged on what tuning reads: a paused species adds no gradient breaks, and a group where only paused species are present is still modelled for its segments and barriers, because other groups read them. Exploration found that pausing leaves stale habitat rows behind (persist replaces per species), and the plan review found that on a multi-host run they would also survive consolidate, because hosts would hold no paused tables and consolidate replaces only shared ones; `lnk_persist_init()` therefore keeps the paused species' shape, a full build clears what it no longer classifies, and the verifier asserts it. The three code-check rounds found two guards scoped wider than what the run builds or reads (the variants harness against the whole file, the validator against the bundle's current pause rather than the schema's builds); round 3's enumeration of every species-keyed guard in the diff ended the loop. Write-up: `research/species_paused.md`; mechanics: RUNBOOK §7, "Pausing a species".

## Measurement

Six groups built before (07203cde) and after (a6942b5d), fresh 0.52.0 both:

- Segments fall 0.23 % (BULK) to 6.04 % (KETL); MURT 5.36 %, KOTL 2.85 %.
- Barrier and override rows identical in all six; accessible km unchanged for every modelled species.
- Habitat moves only in KOTL (BT rearing 20.9 km flips, +5.4 km net on 2,161; WCT rearing 9.8 km, −4.8 net) and KETL (WCT rearing 0.4 km).
- 33 of KOTL's 1,473 fish records sit on a segment that changed (median gradient shift 0.012, largest 0.083); 4 of KETL's 47.
- 73 groups lose a gradient class (presence groups expanded); 7 groups have only paused species present and stay in the run, which stays at 241 (234 if the resolver had not counted paused species; CHUK has only DV and was never in it).
- A re-model over old RB rows cleared SALR's 10,676 to 0; MURT alone passes the full verifier.

Wrong turn kept: the plan said 8 paused-only groups; CHUK's RB comes only through presence-group expansion, which the resolver does not read, so it was never modelled. And a first "before" arm on the branch could not run, because the branch retires the token the before config resolves to, so it ran from a worktree at the baseline.

## Evidence

`data-raw/logs/species_paused_432/` (its README indexes it)

## Owed

- Every `default` group re-models at the next provincial run: KO and RB habitat, access and mapping-code values go, and segmentation moves where Phase 4 measured. Add the 8 no-species groups to the run's notes, with `expected_n` unchanged at 241.

(Seven groups, not eight: see Measurement.)

Closed by: PR (to be opened) for #432
