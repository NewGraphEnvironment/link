# Task: Code-identity gaps in fresh.log — fresh_sha unread from DESCRIPTION, fresh_dirty never set, bcfishobs unpinned (#264)

## Problem

`fresh.log` has 39 rows. Three code-identity columns carry no usable
information, and one model input has no code pin at all:

| column | filled | why |
|---|---|---|
| `fresh_sha` | 15 / 39 | cyphers only — the dispatcher's value **is available and never read** |
| `fresh_dirty` | 0 / 39 | never set on any host |
| `bcfishobs_sha` | — | the column does not exist |

The standing explanation for the dispatcher's NULL `fresh_sha` — repeated in
`CLAUDE.md`, `RUNBOOK.md`, `research/study_area_run.md` and
`data-raw/study_area_verify.sql` — is that m1 installs `fresh` locally
(`RemoteType: local`, no `RemoteSha`). Measured 2026-09-01, that is false:
m1's installed `fresh` carries `RemoteType github`, `RemoteRef v0.33.0`,
`RemoteSha 7f12d99115b7…` — byte-identical to what every cypher records.
`.lnk_pkg_git_sha()` simply never reads `RemoteSha`. The host-aware tolerance
in `study_area_verify.sql` §1b is a workaround for an *unread* field, not an
absent one.

`bcfishobs` is a **model input**, not a reference dataset:
`lnk_barrier_overrides()` counts its observations upstream of each barrier to
decide which are skipped, so different `bcfishobs` code → different barriers →
different `mapping_code`.

The 217-WSG run is next; a row written without these is not retroactively
fixable.

## Decisions taken (user-approved at plan time)

1. **bcfishobs mirrors fwapg: gate, not a dirty column.** `bcfishobs_sha` only;
   `preflight_local()` fails the run on a dirty checkout. Diverges from the
   issue body's proposal 3 — a column FALSE on every row by construction is the
   same no-information failure as link#257. Issue body edited in Phase 6.
2. **`fresh_sha` becomes a pre-flight parity key.** Its exclusion was
   documented as "`NA` on both hosts, so comparing it is a vacuous pass"; that
   rationale expires here.
3. **One resolver, two wrappers** — `.lnk_pkg_git_state()`.
4. Extras in scope: `fresh_sha_source` column (mirrors `bcfp_pin_source`) and
   the `-1` reltuples sentinel fix.

**Finding that changes proposal 2:** with the resolver built correctly a cypher
resolves `fresh_dirty = FALSE` anyway, from the `RemoteSha` tier — a pak
install from a published ref is by definition not a working tree. So
`FRESH_GIT_DIRTY` in `cypher_prep.sh` is no longer the mechanism; it is a
second, explicit observation on top of one. Kept, and relabelled.

## Phase 1: `.lnk_pkg_git_state()` — one resolver

- [ ] Tests first: both known answers per tier against real installs
      (`fresh` has `RemoteSha`, `link` is `RemoteType: local` and has none);
      env override wins over both; clean and dirty checkout for the `.git` tier
- [ ] Premise asserted inline, so a future install-method change fails naming
      the real cause rather than the behaviour under test
- [ ] `.lnk_pkg_git_state()` in `R/lnk_stamp.R`; `sha` and `dirty` each resolve
      through their own tier list (env → DESCRIPTION → `.git` → NA), tier
      detection done once, returns `list(sha, dirty, source)`
- [ ] `.lnk_pkg_git_sha()` / `.lnk_pkg_git_dirty()` become thin wrappers
- [ ] `.lnk_git_dirty_pathspec` / `.lnk_git_dirty_at()` untouched

## Phase 2: log columns and the bcfishobs resolver

- [ ] `.lnk_bcfishobs_sha()` mirroring `.lnk_fwapg_sha()`, with the fork note
- [ ] `lnk_stamp()` gains `bcfishobs_sha` beside `fwapg_sha`
- [ ] `cols_log` + `cols_log_recompute` gain `bcfishobs_sha`, `fresh_sha_source`
- [ ] Both wired into **both** INSERT sites, asserted on both
- [ ] `log_input`: store NULL, not `-1`, for PG's never-analyzed sentinel

## Phase 3: shell — resolve once, export to every leg

- [ ] `preflight_local()` resolves `BCFISHOBS_GIT_SHA`, fails on a dirty
      checkout, exports it
- [ ] Export added to **both** ssh strings that carry `FWAPG_GIT_SHA`
- [ ] `cypher_prep.sh` writes `FRESH_GIT_DIRTY` — strip list **and** write block
- [ ] `bash -n` both scripts; each export confirmed inside the quoted ssh body

## Phase 4: pre-flight parity

- [ ] `fresh_sha` added to `keys` and `forbid_na` defaults
- [ ] The now-false rationale rewritten in both preflight files
- [ ] `lnk_preflight_stamp()` field order unchanged — no shell contract move
- [ ] Tests: an unresolved `fresh_sha` fails parity; matching SHAs pass;
      `@examples` updated (they hardcode `fresh_sha = "NA"`)

## Phase 5: the false rationale, and tightening the verifier

- [ ] Every stale "m1 installs fresh locally" claim removed (`git grep RemoteType`)
- [ ] `study_area_verify.sql` §1b: `fresh_sha IS NULL` unconditional FAIL on
      every host; accumulator kept, no ordered `CASE`
- [ ] DO block: `fresh_sha` and `bcfishobs_sha` in the every-row provenance
      assertion; host-aware branch deleted
- [ ] Single-fault sweep — no arm labelled FAIL may exit 0

## Phase 6: issue body, then PR

- [ ] Issue #264 body **edited** (not commented) to match decisions 1–4
- [ ] `/planning-archive`, `/gh-pr-push`

## Validation

- [ ] Tests pass (baseline 1825 pass / 0 fail / 16 warnings)
- [ ] `devtools::document()` clean, NAMESPACE unchanged
- [ ] `lintr::lint_package()` no worse than baseline
- [ ] Live end-to-end on one WSG + a recompute, read back from the DB —
      four columns non-NULL on **both** log tables
- [ ] `data-raw/study_area_verify_negative.sh` fails when it should and passes
      when it should
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
