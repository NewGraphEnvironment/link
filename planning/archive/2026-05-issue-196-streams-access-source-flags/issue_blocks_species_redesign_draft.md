# DRAFT ISSUE — review before filing (not filed)

**Title:** Rethink `blocks_species` — carry barrier ingredients, classify access late + per-context; add evidence-based dam-override

**Labels:** design, research

## Motivation

`blocks_species text[]` (computed once in `lnk_barriers_unify`) bakes a binary
per-species blocks/doesn't onto every barrier at unify time. Two problems
surfaced in #196 (see `RUNBOOK.md` §5):

1. It conflates two orthogonal axes bcfp keeps separate: **natural access**
   (per-species, gradient-typed, observation/habitat-overridden) vs.
   **anthropogenic descriptor** (dam/pscis/modelled, passability-typed). Dams
   get baked into access wrongly.
2. It's computed before the override is known, so the "fish above ⟹ passable"
   evidence (observations/habitat) can't subtract from it.

bcfp has no binary blocks predicate — it builds per-species access sets from
*ingredients* (gradient class, falls, subsurface) + evidence overrides, and
tracks anthropogenic barriers separately. "Nothing is black-white."

## Direction (research/design)

- Carry barrier **ingredients** on the unified table: `barrier_type`,
  `gradient_class`, `passability` (CABD status), `up_passage_type` (fishway),
  source — instead of (or alongside) the pre-baked `blocks_species`.
- Classify access **late + per-context**, per species, reusing fresh's existing
  `label` / `label_block` gradation rather than a fresh binary.
- **dam-override** (the renamed "dam-passability" idea): let dams be overridden
  out of the relevant set by the SAME evidence rules as natural barriers
  (`lnk_barrier_overrides`: observations / confirmed habitat / control) — many
  CABD dams exist on paper but are passable (decommissioned, partial, fishway,
  or fish demonstrably above). Reuse the rules engine; do NOT build a bespoke
  fishway model. The name shouldn't bake in the mechanism (fishway is one case).
- **This is a deliberate departure from bcfp** (bcfp never overrides dams
  per-species) — opt-in, and it breaks the exact-reproduction correctness bar
  (CLAUDE.md). Sequence it AFTER the match-bcfp access fix (Phase 4d issue).

## Depends on

- Phase 4d (access-set reproduction) lands first — establishes the natural-only
  per-species access view this generalizes.
