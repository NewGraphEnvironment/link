# Progress — Weekly CSV sync skips four copied bcfishpass files; Keogh and Adams dam fixes missing (#429)

## Session 2026-10-31

- Plan-mode exploration — phases approved by user (revised at the gate: `ko` moves into an overlay, copies stay verbatim)
- Created branch `429-weekly-csv-sync-skips-four-copied-bcfish` off origin/main (`e5899a02`)
- Scaffolded PWF baseline from issue #429 with approved phases
- Next: start Phase 1
- Phase 1 done: `.lnk_overlay_apply()` (R/lnk_overlay.R); `lnk_load_overrides()` applies `files: <key>: overlay:` on local reads and muffles only "incomplete final line"; overlay paths resolved in `lnk_config()` (inheritance included) and hashed in `.lnk_config_files()`. bcfishpass presence: `ko` stripped from the copy (now differs from upstream at QUES ST and UTRE CH only) into `overrides/wsg_species_presence_overlay.csv` (CARP, KOTL, NATR, PARS; #107). Proof: loaded tables identical to the pre-change snapshot for bcfishpass, default and default_tuned except `ko`'s column position (appended); tokens unchanged (`acc-bcfp-3`, `acc-v3`). The hash test was green under its mutation at first (the overlay is also hashed via provenance); rewritten on a child bundle with no provenance entry, it now fails under the mutation.
- `audit_configs.R`: presence header via the loader; overlay paths count as declared; fixed a latent `print(df, n = Inf)` crash that fired on any drift.
- Plan review (Plan agent, spawned 19:10Z) folded in: `planning/active/review-plan.md`. Overlay now inserts an added column in sort order (`ko` before `pk`), so the loaded bcfishpass list is `identical()` to the pre-change snapshot; `R/lnk_overlay.R` mapped `any` in the pretest map and the overlay CSV added to the presence row; dead `user_modelled_crossing_fixes_20240825.csv` deleted from `bcfishpass` and `default`; `token_input` flag replaced by a before/after spec comparison in the sync.
