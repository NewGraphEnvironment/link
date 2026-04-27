# Findings — link#64 shape fingerprint

## What "shape" actually means

Two dimensions of source-table change can break consumers:

1. **Column structure** — names added / renamed / removed / reshaped.
   Caught by hashing the header line.
2. **Column types** — same headers, different value types (e.g.,
   `'t'`/`'f'` text → `1`/`0` integer). Caught only by sampling
   actual data and inferring types.

The 2026-04-26 break was BOTH (long → wide reshape AND text → integer
indicators). Either fingerprint type would catch it. Header-only is
much simpler and sufficient for the current failure mode. Type
fingerprint can extend later if a type-only break ever surfaces.

## Fingerprint algorithm

```r
shape_fingerprint <- function(file_path) {
  first_line <- readLines(file_path, n = 1, warn = FALSE)
  if (length(first_line) == 0) return(NA_character_)
  # Normalize: strip trailing whitespace + carriage return, force
  # consistent line ending. Avoids false drifts from CRLF vs LF or
  # trailing spaces in the header.
  normalized <- sub("\\s+$", "", first_line)
  paste0("sha256:", digest::digest(normalized,
                                    algo = "sha256",
                                    serialize = FALSE))
}
```

Implementation in both:
- `data-raw/sync_bcfishpass_csvs.R` (sync time, against fetched bytes)
- `R/lnk_config_verify.R` (verify time, against on-disk file)

## Computing baseline shape_checksum for current files

For each tracked file in `inst/extdata/configs/<bundle>/overrides/`,
hash the first line. Both bundles share the same files byte-for-byte
today (post auto-sync), so the fingerprint pairs match.

Quick recon to validate the algorithm — e.g., from one file:
```bash
head -1 inst/extdata/configs/bcfishpass/overrides/user_habitat_classification.csv \
  | tr -d '\r' | sed 's/[[:space:]]*$//' \
  | shasum -a 256
```

## Workflow flag mechanism

Existing pattern in `sync-bcfishpass-csvs.yml`: R script writes
`/tmp/sync_summary.md`; subsequent shell step reads it. Extending:

```r
# In sync_bcfishpass_csvs.R, after diff loop:
drift_kind <- if (length(shape_drifts) > 0) "shape" else
              if (length(byte_drifts) > 0) "byte" else "none"
writeLines(drift_kind, "/tmp/sync_drift_kind")
```

```yaml
# In workflow YAML:
- name: Open + auto-merge PR if any drift
  run: |
    DRIFT_KIND=$(cat /tmp/sync_drift_kind 2>/dev/null || echo "none")
    case "$DRIFT_KIND" in
      none)  echo "No drift — exit clean"; exit 0 ;;
      byte)  # existing auto-PR + auto-merge path
             ...
             gh pr merge "$PR_URL" --merge --delete-branch ;;
      shape) # new path: open PR with label, no auto-merge, fail loud
             gh pr create ... --label schema-drift ...
             gh label create schema-drift --color B60205 --description "..." || true
             # Don't auto-merge; exit non-zero so the Actions tab shows red
             exit 2 ;;
    esac
```

Need to ensure the `schema-drift` label exists before applying. The
`gh label create` is idempotent if `|| true` swallows the
"already exists" error.

## lnk_config_verify integration

Current `lnk_config_verify()` returns:

```
file | expected | observed | drift | missing
```

Where `expected` and `observed` are the byte sha256s; `drift` is TRUE
when they differ.

Extension:

```
file | byte_expected | byte_observed | byte_drift |
       shape_expected | shape_observed | shape_drift | missing
```

Or — to avoid widening the tibble — stack with a `kind` column:

```
file | kind  | expected | observed | drift | missing
foo   | byte  | sha256:.. | sha256:..  | FALSE | FALSE
foo   | shape | sha256:.. | sha256:..  | FALSE | FALSE
```

Long format is more queryable but breaks existing test assertions.
Wide format with `byte_drift` and `shape_drift` columns is
backward-compatible: rename current `drift` → `byte_drift`, add
`shape_drift`. Document the rename in NEWS.

Going wide. Keeps the function shape easy to read at the REPL.

## Test fixture for shape drift

The 2026-04-26 reshape changed the first line from:
```
blue_line_key,downstream_route_measure,upstream_route_measure,watershed_group_code,species_code,habitat_type,habitat_ind,reviewer_name,review_date,source,notes
```
to:
```
blue_line_key,downstream_route_measure,upstream_route_measure,watershed_group_code,species_code,spawning,rearing,reviewer_name,review_date,source,notes
```

Test pattern:
1. Build a tmp config bundle with one CSV at original shape
2. Verify clean
3. Mutate the CSV's first line (replace `habitat_type,habitat_ind` with
   `spawning,rearing`)
4. Verify reports `shape_drift = TRUE`

Mirrors the existing byte-drift test pattern in
`test-lnk_config_verify.R`.

## Workflow integration test

Hard to test the GHA YAML directly without running a full Actions
workflow. Acceptable for v1: rely on the unit test of the R script's
drift-kind output + manual workflow_dispatch validation post-merge
(same pattern used to validate the original sync workflow when it
first landed in PR #60).

## Version bump

0.12.0 → 0.13.0 — minor. Adds a new field to `provenance:` schema and
a new column to `lnk_config_verify()`'s return; renames `drift` →
`byte_drift`. Pre-1.0; renames are documented and backward-compat-
breaking is acceptable per existing convention.

## Pacing

Independent of crate's work. Ships standalone. Lands today if the
implementation goes smoothly.
