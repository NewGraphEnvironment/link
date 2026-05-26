## Outcome

Reproduced bcfp's per-species accessibility so dam-downstream segments emit the dam descriptor (`SPAWN;DAM`/`REAR;DAM`/`ACCESS;DAM`) instead of a bare habitat token. The mapping_code phase now drives `accessible` from a new per-species `barriers_<sp>_access` view (`lnk_barriers_views`) = natural barriers only (gradient@species-threshold ∪ falls ∪ subsurface) MINUS the observation/habitat override, ∪ all user-definite (override-exempt). Dams stay in `barrier_sources` (token2 only).

The load-bearing design decision (after a Plan-agent review and user push-back on a per-WSG shortcut): **all three access inputs are persisted province-wide** so the cross-WSG downstream walk is correct in every WSG, not just the run's own — natural barriers (already), `user_barriers_definite` (new `USER_DEFINITE` family in `lnk_barriers_unify`, ltree-resolved via the FWA join), and the override (new `<persist>.barrier_overrides` table). A per-WSG view would have been quietly wrong for natural barriers in downstream/sibling WSGs.

Validated against `bcfishpass@v0.7.15`: PARS BT 98.95%, LFRA BT 97.77% / CO 97.90% per-segment mapping_code match. The DB run caught + fixed a real bug — `barrier_overrides` PK needed `watershed_group_code` (boundary-stream override positions are computed by two adjacent WSG runs and collided) — and surfaced the provincial-accumulation property: PARS only emits `;DAM` once PCEA+UPCE (holding the Bennett/Peace Canyon dams it drains through) are persisted. Residual ~1-2% is token1 habitat-presence (`ACCESS`↔`SPAWN`/`REAR`, governed by dimensions/rules), a separate pre-existing concern, not the dam-access fix.

Follow-ups: #201 (blocks_species redesign + evidence-based dam-override, builds on this natural-access foundation); possible drift-validate extension for persist species-column count (stale bt+co wide tables surfaced during validation). Mechanism documented in `RUNBOOK.md` §5.

Closed by: PR #202 (squash `2beb42f`), tagged **v0.40.4**. Commits a82a7fc → e4353b6.
