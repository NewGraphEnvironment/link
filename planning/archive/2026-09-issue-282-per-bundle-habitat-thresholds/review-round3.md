# Review round 3 — #282 branch (`main...HEAD`, HEAD `babcb16`)

Reviewer: code-check round 3 (subagent). Worked in repo copies under the session
scratchpad; the working tree was not touched. One disclosure: running the changed test
files in a copy executed `skip_if_no_db()` in `tests/testthat/setup.R`, which issues
`CREATE SCHEMA IF NOT EXISTS working` against local docker fwapg. The schema already
existed (`NOTICE: ... already exists, skipping`), so nothing changed; everything else in
those files was reads.

Changed test files, run in a copy with `NOT_CRAN=true`: test-lnk_config 127 pass,
test-lnk_log 270, test-lnk_pipeline_classify 19, test-lnk_pipeline_connect 10,
test-dictionaries 42, test-lnk_config_verify 40. 0 fail, 0 error, 0 skip.

## Verdict

**No new defect in the branch diff.** The three round-2 fixes hold. I checked the
depth-3 absolutize, the `.dir` propagation through a three-level merge, the
bundle-thresholds callers and the fallback hash.

The mechanism does reach four places the branch did not fix:

- **Two real defects that predate the branch.** One of them contradicts an invariant
  the branch's new comment states (F1, F2).
- **Two latent inconsistencies.** Both agree today only because of current file contents
  (F3, F4).

## The mechanism

**A config's resolved input set has no single owner.** The input set is which files,
from which bundle, at which absolute path, and under what stable name. Each consumer
re-derives it from the raw manifest with its own rule:

- relative to the leaf dir, or to the parent dir, or to the CWD;
- `lnk_rules_build()`'s own default of fresh's copy;
- a `sprintf("inst/extdata/configs/%s/...")`;
- a hardcoded `bundles <- c("bcfishpass", "default")`.

All three round-2 findings are this mechanism:

- **(a)** The merge re-derived "is this path resolved yet" per layer, assuming a parent
  field was still raw.
- **(b)** The thresholds path was re-derived by each `lnk_rules_build()` caller instead
  of being asked of `cfg`.
- **(c)** The hash enumerated its inputs separately from the thresholds resolver, which
  alone knew about the fallback.

The consumers agree because the bytes coincide, not because they share a derivation:

- all six thresholds CSVs are byte-identical to fresh's copy (sha256 `7b904a18…`,
  including installed fresh 0.34.0);
- `default`'s `dimensions.csv` happens to override `rear_lake_ha_min` for every
  lake-rearing species.

The remedy for the class is one resolver, for example `.lnk_config_inputs(cfg)`,
returning role, absolute path, stable name and bundle. The hash, snapshot, verify, rules
build and audit would all consume it. That is a refactor, not a fix for this PR.

## Findings

### F1. `config_hash` depends on the host's `LC_COLLATE`, not only on its bytes. Real; predates the branch.

`R/lnk_log.R` (`ord <- order(rel)`, unchanged from `main:R/lnk_log.R:78`).
`order()` on a character vector uses the shell sort, which collates by locale.

Measured on m1 with the same `cfg`:

| locale | `.lnk_config_hash(lnk_config("default"))` |
|---|---|
| en_US.UTF-8 | `sha256:008ed3a1…` |
| `Sys.setlocale("LC_COLLATE", "C")` | `sha256:4669cd38…` |

The two differ. In all four bundles checked, `order(rel)` differs from
`order(rel, method = "radix")`. The pair that flips is:

- `overrides/user_barriers_definite_control.csv`
- `overrides/user_barriers_definite.csv`

ICU and glibc en_US sort `_` before `.`; C sorts `.` before `_`.

Consequences:

- **Why it matters here.** The branch's new comment says the naming makes "the hash the
  same on every host". That holds only while every host has the same collation. A
  cypher whose R runs in C/POSIX, which is common for a non-interactive ssh or a
  container without `LANG`, would log a different `config_hash` for byte-identical
  inputs.
- **What breaks.** The `.lnk_log_config_snapshot` gate re-snapshots under the second
  hash, and any "same config?" join across hosts fails.
- **The fleet today.** It is consistent: run `20260901_234743-6628379d` logged the same
  hash on m1 and cypher (read-only query of `fresh.log`). So this is latent in practice.
- **Fix.** `order(rel, method = "radix")`. That changes every existing hash once
  (written data outlives the fix), so pair it with a NEWS note. rtj's
  `stac_raster-add.R:207` already carries this fix for the same reason.

### F2. `extends:` given as a relative path resolves against the CWD, not the child bundle. Real; predates the branch.

`R/lnk_config.R:185` calls `.lnk_config_resolve(manifest$extends, ...)`, which leads to
`.lnk_config_resolve_dir()` and then `normalizePath(name_or_path)`. That resolves
against `getwd()`. Every other config-relative path — rules, dimensions, `files:` and
provenance — resolves against the bundle dir.

Measured with a custom `child/config.yaml` carrying `extends: ../base`:

- from the repo cwd: `lnk_config(child)` fails with `No config directory found at path: ../base`;
- after `setwd(child)`: it loads, with the chain `child, base`.

Scope: this does not affect `default_tuned`, which uses a bare bundle name. The branch
does make `extends:` a first-class production mechanism, so the first custom tuned
bundle written with a relative parent loads only from one directory. A cwd-dependent
config also yields a cwd-dependent chain, and so a cwd-dependent hash name.

### F3. A thin bundle inherits a `rules.yaml` built from the parent's thresholds, not its own. Latent.

`lnk_rules_build()` bakes two things from the thresholds CSV into `rules.yaml`:

- **The species set.** A species is skipped when absent from the CSV, and
  `cfg$species <- names(rules)`.
- **`rear_lake_ha_min`**, wherever `dimensions.csv` does not override it.

`fresh::frs_habitat` then takes `lake_ha_min` from the rule
(`fresh/R/frs_habitat.R:1231`, `utils.R:281`), not from the CSV range.

`default_tuned` inherits `default/rules.yaml`, which was built from
`default/parameters_habitat_thresholds.csv`. So a tuned value can be split between two
sources, and nothing detects it:

- the CSV reaches classify via `frs_params(csv = tuned)`;
- the rule still carries the parent's value, or the parent's species set.

Measured:

| bundle | all `rear_lake_ha_min` set to 7 | effect |
|---|---|---|
| `default` | rules byte-identical | dims override every lake species, so `default_tuned` is safe today |
| `bcfishpass` | SK's rule changes | would bite a thin bundle extending bcfishpass |

No guard would catch it:

- `audit_configs.R` §2 runs only over `c("bcfishpass", "default")`;
- `build_rules.R` has no way to build a thin bundle's rules.

`frs_params()` silently leaves `$rules` unset for a species present in the rules but
absent from a tuned CSV.

When it bites: the first #284 calibration that touches `rear_lake_ha_min` in a
bcfishpass-derived thin bundle, or one that adds or drops a species row.

### F4. `audit_configs.R:91` aborts instead of flagging when a bundle declares no thresholds. Latent.

The call is `lnk_rules_build(..., thresholds = lnk_config(b)$files$parameters_habitat_thresholds$path)`.

- When the entry is absent, this passes `NULL`.
- `lnk_rules_build()`'s `if (thresholds == "")` then errors with `argument is of length zero`.
- That kills the audit mid-run, before §3c, which is the section that would have
  flagged "declares no files$parameters_habitat_thresholds".

Today it is unreachable, because both hardcoded bundles declare the file. It is one
more consumer re-deriving the path without the resolver's fallback.
`.lnk_habitat_thresholds_csv(cfg)` is the call that agrees with the runtime.

## Enumeration

### A. Every consumer of a bundle's thresholds CSV path

| # | Site | How it resolves | Consistent? |
|---|---|---|---|
| 1 | `R/lnk_config.R:321` `.lnk_habitat_thresholds_csv` | `cfg$files$…$path`, else fresh's copy with a message | canonical |
| 2 | `R/lnk_pipeline_classify.R:75` | resolver (#1) unless arg given | yes |
| 3 | `R/lnk_pipeline_connect.R:82` | resolver (#1) unless arg given | yes |
| 4 | `R/lnk_log.R:73` (hash fallback) | resolver (#1), only when undeclared | yes |
| 5 | `R/lnk_log.R:689-694` (snapshot) | `loaded$…` (read from the same `cfg$files` path), else resolver | yes, same file. The two branches format text differently (numeric-read vs `colClasses = "character"`), which is cosmetic |
| 6 | `R/lnk_rules_build.R:42` | own default = fresh's copy; not cfg-aware | independent; correct only if callers pass it |
| 7 | `data-raw/build_rules.R:27,35` | hardcoded bundle paths (top-level rules at :19 use fresh's default) | yes (same bytes) |
| 8 | `data-raw/regen_provenance.R:33` | `sprintf` bundle path, 2 bundles | yes |
| 9 | `data-raw/audit_configs.R:91` | `lnk_config(b)$files$…$path`, no fallback | F4 |
| 10 | `data-raw/audit_configs.R:259,278` (§3c) | fresh's copy (header reference) + per-bundle path | yes |
| 11 | `data-raw/exp_gradient_extra_breaks.R:45` | fresh's copy for break classes, while classify now reads `default`'s | different source; bytes identical today (experiment script) |
| 12 | `data-raw/compare_adms.R:236,268` | `fresh::frs_habitat` with fresh's default params | legacy; implicit fresh copy |
| 13 | `configs/default_{extrabreaks,rearbreaks}/config.yaml` `gradient_classes` | values hand-copied from fresh's CSV | derived twice; agrees today |
| 14 | every `rules.yaml` (species set, `rear_lake_ha_min`) | baked at build time from the building bundle's CSV | F3 for thin bundles |

### B. Every place that decides "the set of files a config consists of"

| # | Site | Set | Consistent? |
|---|---|---|---|
| 1 | `.lnk_config_hash` (`R/lnk_log.R:52`) | chain `config.yaml`s + rules + dimensions + `files:` + provenance paths + fresh fallback | most complete; F1 (collation) |
| 2 | `lnk_config_verify` (`R/lnk_config_verify.R:87`) | declared `provenance:` only (via `.lnk_provenance_path`) | by design (declared-vs-observed); blind to `config.yaml` and the fallback |
| 3 | `lnk_stamp` (`R/lnk_stamp.R:90,127`) | #1 for the hash, #2 for `config_drift` | yes |
| 4 | `.lnk_log_config_snapshot` (`R/lnk_log.R:684`) | values of parameters_fresh, thresholds, dimensions | by design (values, not files); rules covered by hash only |
| 5 | `lnk_load_overrides` (`R/lnk_load_overrides.R:39`) | every `cfg$files` entry (now includes thresholds) | yes; nothing iterates `loaded` to write tables |
| 6 | `data-raw/audit_configs.R:39` | §1-3: hardcoded `bcfishpass, default`; §3c: every directory | **inconsistent within the script**: `default_tuned`, `default_extrabreaks` and `default_rearbreaks` are never provenance-verified or rules-regen-checked (F3) |
| 7 | `data-raw/regen_provenance.R:28,80-95` | 2 bundles × 4 hardcoded files (not thresholds) | editing a thresholds CSV leaves its checksum stale, so verify reports drift. No failure |
| 8 | `data-raw/sync_bcfishpass_csvs.R:156,252` | provenance entries sourced from smnorris/bcfishpass; writes bcfishpass + default only | thresholds excluded correctly (source is fresh); thin bundles inherit via `extends` (hash picks up `extends:default/...`); extrabreaks/rearbreaks copies not synced (predates branch) |
| 9 | Log-table enumerations: `R/lnk_log.R:395` (create), `R/lnk_log.R:684` (snapshot), `R/lnk_persist_init.R:337` (validate) | three lists | consistent now; pinned by `test-lnk_log.R:237,681` |
| 10 | `data-raw/schema_consolidate.R` | tables with `watershed_group_code` | `log_parameters_*` (keyed on `config_hash`) never travel home from cyphers. Predates the branch; the new table inherits it |

### C. Every place that resolves a config-relative path

| # | Site | Base | Consistent? |
|---|---|---|---|
| 1 | `R/lnk_config.R:96-114` rules/dimensions | leaf dir unless absolute | yes |
| 2 | `R/lnk_config.R:229-231` merge rules/dimensions | `.lnk_config_absolutize` (parent dir unless already absolute) | yes (round-2 fix verified) |
| 3 | `R/lnk_config.R:249` `.lnk_config_absolutize_files` (merge), `:266` `.lnk_config_resolve_files` (leaf) | parent dir / leaf dir unless absolute | yes |
| 4 | `R/lnk_config.R:211` + `:336` `.lnk_provenance_path` | `.dir` (set on first inheritance, preserved deeper), else leaf dir | yes, including depth 3 |
| 5 | `R/lnk_config.R:185` → `:285` `.lnk_config_resolve_dir` for `extends:` | **CWD** | **no** (F2) |
| 6 | `R/lnk_log.R:84-92` hash naming | first matching chain dir (leaf plain, ancestors `extends:<basename>/`) | yes; deterministic given the layout |
| 7 | `data-raw/regen_provenance.R:43` | `dirname(cfg_path)` (leaf yaml only) | yes for what it edits |
| 8 | `data-raw/sync_bcfishpass_csvs.R:253` | `file.path(bundle, rel)` | yes |
| 9 | `data-raw/audit_configs.R` §2/§3 `repo_path(sprintf(...))` | assumes each bundle holds its own dimensions, rules and overrides | only true for full bundles; thin bundles are excluded rather than resolved |
