# Findings — #40 config provenance + run stamps

## Current state

- `lnk_stamp()` does NOT exist yet. Issue #24 proposed a narrower
  "report appendix" version. #40 supersedes #24 with a runtime-stamp
  scope; same function name, broader contract.
- "provenance" is already used in `R/lnk_override.R` and `R/lnk_load.R`
  for *user CSV provenance columns* (reviewer, review_date) — that's a
  different concept (per-row data lineage). The #40 work is per-file
  bundle provenance, parsed from the manifest. Disambiguate naming
  carefully — call the new slot `cfg$provenance` and the file-level
  manifest section `provenance:` to make the namespacing clean.
- `R/lnk_config.R` is a clean target for extension. Reads `config.yaml`,
  resolves files, returns a structured list with class `lnk_config`.
  Adding a `provenance:` parser is a small addition.

## Manifest shape (what to add)

Mirror the issue's proposed format:

```yaml
provenance:
  overrides/user_modelled_crossing_fixes.csv:
    source: https://github.com/smnorris/bcfishpass
    path: data/user_modelled_crossing_fixes.csv
    upstream_sha: ea3c5d8
    synced: 2026-04-13
    checksum: sha256:<computed>
  rules.yaml:
    generated_from: dimensions.csv
    generated_by: lnk_rules_build
    generator_sha: <link sha at build time>
  dimensions.csv:
    source: link (hand-authored)
    upstream_sha: <link sha at last edit>
    synced: 2026-04-13
```

Keys per file:

- **All files**: `checksum: sha256:<hex>` — recomputable
- **External-source files**: `source` URL + `path` within source repo +
  `upstream_sha` + `synced` date
- **Generated files**: `generated_from` (input file), `generated_by`
  (function name), `generator_sha` (sha of generator code at build)
- **Hand-authored link files**: `source: link (hand-authored)`,
  `upstream_sha` = link sha at last edit, `synced`

## Coverage scope

For PR 1, do checksums on every file the manifest already references:
- `rules_yaml`, `dimensions_csv`, `parameters_fresh`
- All `overrides/*` (per `overrides:` block)
- All optional `files:` (`habitat_classification`, `observation_exclusions`, `wsg_species`)

That's ~10 files for bcfishpass, ~3-5 for default. Doable.

## Backfill data

bcfishpass SHA: `ea3c5d8` (per `research/default_vs_bcfishpass.md` Versions section, was the last sync). Date: 2026-04-13 (per #40 issue body). Apply to all bcfishpass-sourced overrides.

For `link`-sourced files (rules.yaml, dimensions.csv): `upstream_sha`
should be the link git SHA at the time of generation. Easy to set on
this PR's sha; harder for historical files. Acceptable to use HEAD at
PR-merge time as the baseline — drift detection works forward from
there.

## Checksum implementation

Use `tools::md5sum()` for portability (base R) or `digest::digest()`.
Issue requests sha256. base R has no sha256, but `digest::digest(file = ..., algo = "sha256")` does. Add `digest` to Suggests if not already there.

Format: `sha256:abcd1234...` — the `sha256:` prefix is in the issue's
example and makes the algorithm explicit. Important if we later change
to a different algorithm.

## lnk_config_verify() shape

```r
lnk_config_verify(cfg, strict = FALSE)
```

Returns a tibble:

| col | type | meaning |
|-----|------|---------|
| file | chr | relative path from cfg$dir |
| expected | chr | checksum from manifest |
| observed | chr | recomputed checksum |
| drift | lgl | TRUE when expected != observed |

`strict = TRUE` → `stop()` if any row has `drift == TRUE`. Default
prints message + returns tibble.

## lnk_stamp() shape

```r
lnk_stamp(cfg, conn = NULL, aoi = NULL, start_time = Sys.time(),
          db_snapshot = TRUE, ...)
```

Returns `lnk_stamp` S3 list:

```r
list(
  config_name = cfg$name,
  config_dir = cfg$dir,
  provenance = lnk_config_verify(cfg),  # current observed checksums
  software = list(
    link = list(version = packageVersion("link"),
                git_sha = .lnk_git_sha()),
    fresh = list(version = packageVersion("fresh"),
                 git_sha = .lnk_pkg_git_sha("fresh")),
    R = R.version.string
  ),
  db = if (!is.null(conn) && db_snapshot) {
    list(
      bcfishobs_obs_count = .lnk_db_count(conn, "bcfishobs.observations"),
      fwa_streams_count = .lnk_db_count(conn, "whse_basemapping.fwa_stream_networks_sp"),
      bcfishpass_habitat_linear_sk_count = NA_integer_  # tunnel-side, requires conn_ref
    )
  } else NULL,
  run = list(
    aoi = aoi,
    start_time = start_time,
    end_time = NULL  # caller fills via end_lnk_stamp(stamp)
  )
)
```

Plus `as.markdown.lnk_stamp(stamp)` and `print.lnk_stamp()`.

## git SHA discovery

Three-tier fallback:

1. `Sys.getenv("LINK_GIT_SHA", "")` — set by CI or by user
2. If `.git` dir exists at `system.file("..", package = "link")` parent, run `git rev-parse HEAD` — works for `devtools::load_all()` from source
3. Otherwise NA — note in stamp output. `packageVersion()` is always
   available regardless.

bcfishpass SHA: not derivable from R session. Pull from cfg$provenance
itself — every external file already records its `upstream_sha`. Stamp
shows aggregate "bcfishpass synced from `ea3c5d8`" if all bcfishpass-
sourced files agree; "mixed" otherwise.

## Wire-in: compare_bcfishpass_wsg.R

Currently the function uses `message(...)` for milestones. Add at the
top:

```r
stamp <- lnk_stamp(config, conn, aoi = wsg)
message(paste(format(as.markdown(stamp)), collapse = "\n"))
```

Produces stamp at the head of each WSG's stderr — captured into
`data-raw/logs/*.txt` by the standard `> log 2>&1` redirect.

## Tests strategy

- `test-lnk_config.R`: extend with provenance parsing test (read a
  fixture config.yaml with provenance block, assert `cfg$provenance`
  shape).
- `test-lnk_config_verify.R`: new file. Build a tmp config dir with
  known files + checksums, verify clean. Mutate a file, verify drift
  detected. `strict = TRUE` errors.
- `test-lnk_stamp.R`: new file. Mock `conn = NULL` + check shape.
  Mock `system()` git call where possible; otherwise rely on env var
  `LINK_GIT_SHA` set in test setup.
- `test-lnk_config_resolve_dir.R` already exists — leave alone.

No DB connection needed for any new test. Snapshot calls only fire when
`conn` non-NULL.

## Stretch — when to add what

- **Phase 5 (lnk_stamp) is the largest single piece.** Could split
  this PR into two if it gets unwieldy: PR 1 = provenance only, PR 2 =
  lnk_stamp. Issue's "first PR" includes both, so keep together unless
  test surface explodes.
- Markdown rendering should be functional but not pretty for #24
  appendix purposes — a follow-up can tune layout when consumers exist.
