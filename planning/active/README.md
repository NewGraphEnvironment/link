# planning/active

Empty — #262's PWF is archived at
`planning/archive/2026-09-issue-262-provenance-gaps/`.

The two follow-up drafts that lived here are filed:

- **#264** — code-identity gaps in `fresh.log` (`fresh_sha` unread from
  DESCRIPTION, `fresh_dirty` never set, `bcfishobs` unpinned). Link-side only,
  no decision needed, ~1-2 h.
- **#265** — record source-artifact identity. Absorbs #247 (commented, not
  closed — superseding is a scope call). **Time-sensitive:** the object store
  honours `?versionId=` but refuses listing, so any FWA reload rotates
  version-ids we can no longer recover.
