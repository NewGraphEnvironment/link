# Pending issue drafts (not yet filed)

Two issue bodies drafted 2026-09-01, shown to the user, **awaiting the explicit
"file it"** that `CLAUDE.md` requires before `gh issue create`.

| draft | title |
|---|---|
| `issue_draft_A_code_identity.md` | Code-identity gaps in `fresh.log`: `fresh_sha` unread from DESCRIPTION, `fresh_dirty` never set, `bcfishobs` unpinned |
| `issue_draft_B_source_artifact.md` | Record source-artifact identity: the object store cannot list versions, so unrecorded is unrecoverable |

Both are link-side only — no fork changes, nothing upstream, no smnorris
involvement. B absorbs and supersedes #247.

**B is time-sensitive.** `nrs.objectstore.gov.bc.ca` serves `x-amz-version-id`
and honours `?versionId=` re-fetch, but refuses `?versions` and `?list-type=2`
(`AccessDenied`). So a version-id not recorded at load time cannot be recovered
later — the bucket will not answer retrospectively. Any FWA reload before B lands
rotates ids we could have captured.

Filing these is step 1 of the plan; A is ~1-2 h and needs no decision.
